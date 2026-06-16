import AppKit

/// Caret-anchored ghost text: a borderless, click-through, non-activating window
/// that renders the armed suggestion inline at the caret. Never takes focus.
final class GhostTextWindow: NSWindow {
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = NSColor.tertiaryLabelColor
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        contentView = label
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(text: String, at caret: NSRect) {
        label.stringValue = text
        label.sizeToFit()
        let size = label.frame.size
        setFrame(NSRect(x: caret.maxX + 2,
                        y: caret.minY,
                        width: size.width + 4,
                        height: max(size.height, caret.height)),
                 display: true)
        orderFrontRegardless()
    }
}

/// Separate, non-activating floating panel listing ranked suggestions with
/// rationale. Clicking a row re-arms the ghost text. Never steals focus from
/// the host app.
final class SuggestionsPanel: NSPanel {
    var onSelect: ((Suggestion) -> Void)?

    private let header = NSTextField(labelWithString: "")
    private let stack = NSStackView()
    private var rows: [(button: NSButton, suggestion: Suggestion)] = []

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 120),
                   styleMask: [.nonactivatingPanel, .titled, .closable, .utilityWindow],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        title = "Lexicon"
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        header.font = NSFont.boldSystemFont(ofSize: 13)
        header.lineBreakMode = .byWordWrapping
        header.maximumNumberOfLines = 2
        header.preferredMaxLayoutWidth = 300

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(header)

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        contentView = content
    }

    // Never become key — the host app must keep keyboard focus so inserts land there.
    override var canBecomeKey: Bool { false }

    func present(_ result: AnalysisResult, near caret: NSRect?) {
        // Reset rows.
        for (b, _) in rows { b.removeFromSuperview() }
        rows.removeAll()

        header.stringValue = "🎯 \(result.goalLabel)  ·  \(Int(result.confidence * 100))%"

        for (i, s) in result.suggestions.enumerated() {
            let button = makeRow(s, index: i)
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: 300).isActive = true
            rows.append((button, s))
        }

        layoutIfNeeded()
        let fitting = stack.fittingSize
        setContentSize(NSSize(width: max(fitting.width, 320), height: fitting.height))
        position(near: caret)
        orderFrontRegardless()
    }

    func highlight(_ suggestion: Suggestion) {
        for (b, s) in rows {
            b.bezelColor = (s.replacement == suggestion.replacement)
                ? NSColor.controlAccentColor : nil
        }
    }

    private func makeRow(_ s: Suggestion, index: Int) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .regularSquare
        button.alignment = .left
        button.imagePosition = .noImage
        button.cell?.wraps = true
        button.tag = index
        button.target = self
        button.action = #selector(rowClicked(_:))

        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        let title = NSMutableAttributedString(
            string: (s.original?.isEmpty == false ? "“\(s.original!)” → " : "+ ") + s.replacement + "\n",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        title.append(NSAttributedString(
            string: s.rationale,
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: NSColor.secondaryLabelColor]))
        title.addAttribute(.paragraphStyle, value: para,
                           range: NSRange(location: 0, length: title.length))
        button.attributedTitle = title
        return button
    }

    @objc private func rowClicked(_ sender: NSButton) {
        guard sender.tag < rows.count else { return }
        onSelect?(rows[sender.tag].suggestion)
    }

    private func position(near caret: NSRect?) {
        guard let caret = caret, let screen = NSScreen.main else {
            center()
            return
        }
        // Prefer placing the panel just above the caret; fall back to below.
        var origin = NSPoint(x: caret.minX, y: caret.maxY + 8)
        if origin.y + frame.height > screen.frame.maxY {
            origin.y = caret.minY - frame.height - 8
        }
        origin.x = min(origin.x, screen.frame.maxX - frame.width - 8)
        origin.x = max(origin.x, screen.frame.minX + 8)
        setFrameOrigin(origin)
    }
}

/// Coordinates the ghost text and the suggestions panel, and owns the
/// `armedSuggestion` state that Step 5's Tab handler consumes.
@MainActor
final class OverlayController {
    private(set) var armedSuggestion: Suggestion?
    var onArmChanged: ((Suggestion?) -> Void)?

    private let ghost = GhostTextWindow()
    private let panel = SuggestionsPanel()
    private var lastCaret: NSRect?

    init() {
        panel.onSelect = { [weak self] s in self?.arm(s) }
    }

    func present(_ result: AnalysisResult, caret: NSRect?) {
        lastCaret = caret
        panel.present(result, near: caret)
        if let first = result.suggestions.first {
            arm(first)
        } else {
            ghost.orderOut(nil)
            setArmed(nil)
        }
    }

    /// Re-arm the ghost text with a specific suggestion (panel selection).
    func arm(_ s: Suggestion) {
        panel.highlight(s)
        if let caret = lastCaret { ghost.show(text: s.replacement, at: caret) }
        setArmed(s)
    }

    /// Dismiss the ghost only (e.g. a non-Tab keystroke), keep the panel.
    func dismissGhost() {
        ghost.orderOut(nil)
        setArmed(nil)
    }

    /// Tear everything down.
    func dismiss() {
        ghost.orderOut(nil)
        panel.orderOut(nil)
        setArmed(nil)
    }

    private func setArmed(_ s: Suggestion?) {
        armedSuggestion = s
        onArmChanged?(s)
    }

    /// Renders the suggestions panel to a PNG (verification only — captures the
    /// app's own drawing, independent of Screen Recording permission).
    func debugSnapshotPanel(to path: String) {
        guard let view = panel.contentView else { return }
        let data = view.dataWithPDF(inside: view.bounds)
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
