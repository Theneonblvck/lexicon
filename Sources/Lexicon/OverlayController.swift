import AppKit

/// Caret-anchored ghost text: borderless, click-through, never key.
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
        label.textColor = NSColor.tertiaryLabelColor.withAlphaComponent(OverlayStyle.ghostOpacity)
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        contentView = label
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Position + text only; no ordering or opacity change.
    private func layout(text: String, at caret: NSRect) {
        label.stringValue = text
        label.sizeToFit()
        let size = label.frame.size
        setFrame(NSRect(x: caret.maxX + 2,
                        y: caret.minY,
                        width: size.width + 4,
                        height: max(size.height, caret.height)),
                 display: true)
    }

    /// Fade in from hidden: opacity 0 → 0.45 with a small upward drift (§4).
    func appear(text: String, at caret: NSRect) {
        layout(text: text, at: caret)
        let final = frame.origin
        alphaValue = 0
        orderFrontRegardless()
        lexFade(to: OverlayMotion.ghostOpacity,
                duration: OverlayMotion.ghostFadeIn,
                curve: OverlayMotion.surfaceCurve,
                driftFromY: final.y - OverlayMotion.ghostDrift,
                driftToY: final.y)
    }

    /// Armed text changed: dip to 0.18 and back so the swap reads as a thought
    /// changing, not a flicker (§4). Reduce Motion swaps instantly.
    func reArm(text: String, at caret: NSRect) {
        guard !OverlayMotion.reduceMotion else {
            layout(text: text, at: caret)
            alphaValue = OverlayMotion.ghostOpacity
            orderFrontRegardless()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = OverlayMotion.dipDuration / 2
            ctx.timingFunction = OverlayMotion.dissolveCurve
            animator().alphaValue = OverlayMotion.dipLow
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.layout(text: text, at: caret)
            self.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = OverlayMotion.dipDuration / 2
                ctx.timingFunction = OverlayMotion.surfaceCurve
                self.animator().alphaValue = OverlayMotion.ghostOpacity
            }
        })
    }

    /// Dissolve out, sinking a few points as it goes (§4).
    func disappear(duration: TimeInterval = OverlayMotion.fadeOut) {
        guard isVisible else { return }
        let origin = frame.origin
        lexFade(to: 0,
                duration: duration,
                curve: OverlayMotion.dissolveCurve,
                driftToY: origin.y - OverlayMotion.fadeOutDrift) { [weak self] in
            guard let self else { return }
            self.orderOut(nil)
            self.setFrameOrigin(origin)
        }
    }
}

// MARK: - Suggestion row

/// One ranked suggestion row; insertable kinds accept clicks to re-arm the ghost.
final class SuggestionRowView: NSView {
    let suggestion: Suggestion
    var onSelect: (() -> Void)?

    private let accentRule = NSView()
    private let symbolView = NSImageView()
    private let replacementField = NSTextField(labelWithString: "")
    private let rationaleField = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?

    init(suggestion: Suggestion) {
        self.suggestion = suggestion
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        buildSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func buildSubviews() {
        let isCadence = !suggestion.kind.isInsertable
        let accent = suggestion.kind.accent

        accentRule.wantsLayer = true
        accentRule.layer?.backgroundColor = accent.cgColor
        accentRule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(accentRule)

        let config = NSImage.SymbolConfiguration(pointSize: OverlayStyle.symbolSize, weight: .regular)
        symbolView.image = NSImage(systemSymbolName: suggestion.kind.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        symbolView.contentTintColor = accent
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbolView)

        let replacementFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let rationaleFont: NSFont = isCadence
            ? NSFontManager.shared.convert(NSFont.systemFont(ofSize: 12), toHaveTrait: .italicFontMask)
            : NSFont.systemFont(ofSize: 11)

        var line1 = ""
        if let orig = suggestion.original, !orig.isEmpty {
            line1 = "“\(orig)” → "
        } else if !isCadence {
            line1 = "+ "
        }
        let displayText = suggestion.replacement.isEmpty ? suggestion.rationale : suggestion.replacement
        line1 += displayText

        replacementField.stringValue = line1
        replacementField.font = isCadence ? rationaleFont : replacementFont
        replacementField.textColor = isCadence ? .secondaryLabelColor : .labelColor
        replacementField.lineBreakMode = .byWordWrapping
        replacementField.maximumNumberOfLines = isCadence ? 2 : 1
        replacementField.preferredMaxLayoutWidth = OverlayStyle.panelWidth - OverlayStyle.padding * 2 - 24
        replacementField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(replacementField)

        if !isCadence {
            rationaleField.stringValue = suggestion.rationale
            rationaleField.font = NSFont.systemFont(ofSize: 11)
            rationaleField.textColor = .secondaryLabelColor
            rationaleField.lineBreakMode = .byWordWrapping
            rationaleField.maximumNumberOfLines = 2
            rationaleField.preferredMaxLayoutWidth = OverlayStyle.panelWidth - OverlayStyle.padding * 2 - 24
            rationaleField.translatesAutoresizingMaskIntoConstraints = false
            addSubview(rationaleField)
        }

        NSLayoutConstraint.activate([
            accentRule.leadingAnchor.constraint(equalTo: leadingAnchor),
            accentRule.topAnchor.constraint(equalTo: topAnchor),
            accentRule.bottomAnchor.constraint(equalTo: bottomAnchor),
            accentRule.widthAnchor.constraint(equalToConstant: OverlayStyle.accentRuleWidth),

            symbolView.leadingAnchor.constraint(equalTo: accentRule.trailingAnchor, constant: 8),
            symbolView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            symbolView.widthAnchor.constraint(equalToConstant: OverlayStyle.symbolSize),
            symbolView.heightAnchor.constraint(equalToConstant: OverlayStyle.symbolSize),

            replacementField.leadingAnchor.constraint(equalTo: symbolView.trailingAnchor, constant: 6),
            replacementField.trailingAnchor.constraint(equalTo: trailingAnchor),
            replacementField.topAnchor.constraint(equalTo: topAnchor, constant: 2),
        ])

        if !isCadence {
            NSLayoutConstraint.activate([
                rationaleField.leadingAnchor.constraint(equalTo: replacementField.leadingAnchor),
                rationaleField.trailingAnchor.constraint(equalTo: trailingAnchor),
                rationaleField.topAnchor.constraint(equalTo: replacementField.bottomAnchor, constant: 2),
                rationaleField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            ])
        } else {
            replacementField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4).isActive = true
        }
    }

    func setArmed(_ armed: Bool) {
        if armed {
            layer?.backgroundColor = NSColor.selectedContentBackgroundColor
                .withAlphaComponent(OverlayStyle.armedFillAlpha).cgColor
            accentRule.isHidden = false
        } else {
            layer?.backgroundColor = nil
        }
    }

    /// Accept feedback: flash the accent fill @0.24 for 120 ms, then restore (§4).
    func flashAccent(completion: @escaping () -> Void) {
        let restore = layer?.backgroundColor
        layer?.backgroundColor = suggestion.kind.accent
            .withAlphaComponent(OverlayMotion.armedFlashAlpha).cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + OverlayMotion.acceptFlash) { [weak self] in
            self?.layer?.backgroundColor = restore
            completion()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        guard suggestion.kind.isInsertable else { return }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseDown(with event: NSEvent) {
        guard suggestion.kind.isInsertable else { return }
        onSelect?()
    }

    override func resetCursorRects() {
        guard suggestion.kind.isInsertable else { return }
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - Panel container

/// Hosts the panel root and reports hover so the dwell auto-dim can recover (§4).
final class PanelContainerView: NSView {
    var onHover: (() -> Void)?
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseMoved(with event: NSEvent) { onHover?() }
}

// MARK: - Suggestions panel

/// Non-activating floating panel listing ranked suggestions. Never steals focus.
final class SuggestionsPanel: NSPanel {
    var onSelect: ((Suggestion) -> Void)?

    private let root = OverlayStyle.makePanelRoot()
    private let stack = NSStackView()
    private var rowViews: [SuggestionRowView] = []
    private var armedRowView: SuggestionRowView?
    private var autoDimTimer: Timer?
    private let headerGoal = NSTextField(labelWithString: "")
    private let headerConfidence = NSTextField(labelWithString: "")

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: OverlayStyle.panelWidth, height: 120),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        root.translatesAutoresizingMaskIntoConstraints = false
        root.wantsLayer = true
        if let layer = root.layer {
            let s = OverlayStyle.panelShadow()
            layer.shadowColor = s.shadowColor?.cgColor
            layer.shadowOffset = CGSize(width: s.shadowOffset.width, height: s.shadowOffset.height)
            layer.shadowRadius = s.shadowBlurRadius
            layer.shadowOpacity = 1
        }
        let container = PanelContainerView()
        container.onHover = { [weak self] in self?.recoverFromDim() }
        container.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let headerRow = NSView()
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerGoal.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        headerGoal.textColor = .labelColor
        headerGoal.lineBreakMode = .byTruncatingTail
        headerGoal.translatesAutoresizingMaskIntoConstraints = false

        headerConfidence.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        headerConfidence.textColor = .secondaryLabelColor
        headerConfidence.alignment = .right
        headerConfidence.translatesAutoresizingMaskIntoConstraints = false

        headerRow.addSubview(headerGoal)
        headerRow.addSubview(headerConfidence)
        NSLayoutConstraint.activate([
            headerGoal.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor),
            headerGoal.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            headerConfidence.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor),
            headerConfidence.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            headerConfidence.leadingAnchor.constraint(greaterThanOrEqualTo: headerGoal.trailingAnchor, constant: 8),
            headerRow.heightAnchor.constraint(equalToConstant: 20),
        ])

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = OverlayStyle.rowSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: OverlayStyle.padding),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -OverlayStyle.padding),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: OverlayStyle.padding),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -OverlayStyle.padding),
        ])
        contentView = container
    }

    override var canBecomeKey: Bool { false }

    func present(_ result: AnalysisResult, near caret: NSRect?) {
        for row in rowViews { row.removeFromSuperview() }
        rowViews.removeAll()
        while stack.arrangedSubviews.count > 1 {
            stack.arrangedSubviews.last?.removeFromSuperview()
        }

        headerGoal.stringValue = result.goalLabel
        headerConfidence.stringValue = "\(Int(result.confidence * 100))%"

        let visible = Array(result.suggestions.prefix(OverlayStyle.maxVisibleRows))
        let overflow = result.suggestions.count - visible.count

        for s in visible {
            let row = SuggestionRowView(suggestion: s)
            row.onSelect = { [weak self] in
                guard s.kind.isInsertable else { return }
                self?.onSelect?(s)
            }
            row.widthAnchor.constraint(equalToConstant: OverlayStyle.panelWidth - OverlayStyle.padding * 2).isActive = true
            stack.addArrangedSubview(row)
            rowViews.append(row)
        }

        if overflow > 0 {
            let footer = NSTextField(labelWithString: "+\(overflow) more")
            footer.font = NSFont.systemFont(ofSize: 11)
            footer.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(footer)
        }

        layoutIfNeeded()
        let fitting = stack.fittingSize
        let totalH = fitting.height + OverlayStyle.padding * 2
        setContentSize(NSSize(width: OverlayStyle.panelWidth, height: totalH))
        position(near: caret)
        // Built hidden; OverlayController triggers animateIn() after the ghost leads.
        alphaValue = 0
        orderFrontRegardless()
    }

    /// Fade the surface in (+6 pt rise), cascade the rows, and arm the dwell timer (§4).
    func animateIn() {
        let final = frame.origin
        lexFade(to: 1.0,
                duration: OverlayMotion.panelFadeIn,
                curve: OverlayMotion.surfaceCurve,
                driftFromY: final.y - OverlayMotion.panelDrift,
                driftToY: final.y)
        if OverlayMotion.reduceMotion {
            for row in rowViews { row.layer?.opacity = 1 }
        } else {
            cascadeRowsIn()
        }
        scheduleAutoDim()
    }

    private func cascadeRowsIn() {
        for (i, row) in rowViews.enumerated() {
            guard let layer = row.layer else { continue }
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 0
            anim.toValue = 1
            anim.duration = OverlayMotion.rowFade
            anim.beginTime = CACurrentMediaTime() + Double(i) * OverlayMotion.rowCascadeStep
            anim.timingFunction = OverlayMotion.surfaceCurve
            anim.fillMode = .backwards
            layer.add(anim, forKey: "cascadeIn")
            layer.opacity = 1
        }
    }

    private func scheduleAutoDim() {
        autoDimTimer?.invalidate()
        guard !OverlayMotion.reduceMotion else { return }
        autoDimTimer = Timer.scheduledTimer(withTimeInterval: OverlayMotion.dwellBeforeDim,
                                            repeats: false) { [weak self] _ in
            self?.autoDim()
        }
    }

    private func autoDim() {
        guard isVisible, alphaValue > OverlayMotion.dimmedAlpha else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = OverlayMotion.autoDimDuration
            ctx.timingFunction = OverlayMotion.surfaceCurve
            animator().alphaValue = OverlayMotion.dimmedAlpha
        }
    }

    /// Recover to full opacity on hover/proximity/new analysis, and re-arm dwell (§4).
    func recoverFromDim() {
        guard isVisible else { return }
        if alphaValue < 1.0 && !OverlayMotion.reduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = OverlayMotion.recoverDuration
                ctx.timingFunction = OverlayMotion.surfaceCurve
                animator().alphaValue = 1.0
            }
        }
        scheduleAutoDim()
    }

    func highlight(_ suggestion: Suggestion) {
        armedRowView = nil
        for row in rowViews {
            let armed = row.suggestion.kind.isInsertable
                && row.suggestion.replacement == suggestion.replacement
                && row.suggestion.kind == suggestion.kind
            row.setArmed(armed)
            if armed { armedRowView = row }
        }
    }

    /// Dissolve out: reverse row cascade (last leaves first) + −3 pt sink (§4).
    func fadeOut(completion: (() -> Void)? = nil) {
        autoDimTimer?.invalidate()
        guard isVisible else { completion?(); return }
        if !OverlayMotion.reduceMotion { reverseCascade() }
        let origin = frame.origin
        lexFade(to: 0,
                duration: OverlayMotion.fadeOut,
                curve: OverlayMotion.dissolveCurve,
                driftToY: origin.y - OverlayMotion.fadeOutDrift) { [weak self] in
            guard let self else { completion?(); return }
            self.orderOut(nil)
            self.setFrameOrigin(origin)
            completion?()
        }
    }

    private func reverseCascade() {
        let n = rowViews.count
        for (i, row) in rowViews.enumerated() {
            guard let layer = row.layer else { continue }
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = layer.presentation()?.opacity ?? layer.opacity
            anim.toValue = 0
            anim.duration = OverlayMotion.rowFade
            anim.beginTime = CACurrentMediaTime() + Double(n - 1 - i) * OverlayMotion.rowReverseCascadeStep
            anim.timingFunction = OverlayMotion.dissolveCurve
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            layer.add(anim, forKey: "cascadeOut")
        }
    }

    /// Tab accept: flash the armed row, then dissolve. Reduce Motion / no armed row
    /// dissolves directly.
    func flashAccept(completion: (() -> Void)? = nil) {
        autoDimTimer?.invalidate()
        guard !OverlayMotion.reduceMotion, let row = armedRowView else {
            fadeOut(completion: completion)
            return
        }
        row.flashAccent { [weak self] in self?.fadeOut(completion: completion) }
    }

    /// Bitmap of the current surface, for cross-fade supersession (§4).
    func snapshotImage() -> NSImage? {
        guard let view = contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    private func position(near caret: NSRect?) {
        let screen: NSScreen
        if let caret = caret {
            screen = OverlayStyle.screenContaining(point: caret.origin)
        } else if let main = NSScreen.main {
            screen = main
        } else {
            center()
            return
        }

        guard let caret = caret else {
            let vf = screen.visibleFrame
            setFrameOrigin(NSPoint(
                x: vf.maxX - frame.width - OverlayStyle.noCaretInset,
                y: vf.minY + OverlayStyle.noCaretInset))
            return
        }

        // Default: below the caret line (panel sits under the active line).
        var origin = NSPoint(x: caret.minX, y: caret.minY - frame.height - OverlayStyle.caretGap)
        if origin.y < screen.visibleFrame.minY + OverlayStyle.screenInset {
            origin.y = caret.maxY + OverlayStyle.caretGap
        }
        origin.x = min(origin.x, screen.visibleFrame.maxX - frame.width - OverlayStyle.screenInset)
        origin.x = max(origin.x, screen.visibleFrame.minX + OverlayStyle.screenInset)
        setFrameOrigin(origin)
    }
}

// MARK: - Overlay controller

@MainActor
final class OverlayController {
    private(set) var armedSuggestion: Suggestion?
    var onArmChanged: ((Suggestion?) -> Void)?

    private let ghost = GhostTextWindow()
    private let panel = SuggestionsPanel()
    private var lastCaret: NSRect?
    private var ghostVisible = false

    init() {
        panel.onSelect = { [weak self] s in self?.arm(s) }
    }

    func present(_ result: AnalysisResult, caret: NSRect?) {
        lastCaret = caret
        // Supersession: cross-fade the outgoing surface under the incoming one (§4).
        if panel.isVisible { crossfadeFromCurrentPanel() }

        panel.present(result, near: caret)
        // Ghost leads; panel fades in +80 ms later.
        DispatchQueue.main.asyncAfter(deadline: .now() + OverlayMotion.panelLeadDelay) { [weak panel] in
            panel?.animateIn()
        }

        if let first = result.suggestions.first(where: { $0.kind.isInsertable }) {
            applyArm(first, fresh: true)
        } else {
            ghost.disappear()
            ghostVisible = false
            setArmed(nil)
        }
    }

    /// Public re-arm (panel click / cycling): dip-swaps the ghost text.
    func arm(_ s: Suggestion) {
        guard s.kind.isInsertable else { return }
        applyArm(s, fresh: false)
    }

    private func applyArm(_ s: Suggestion, fresh: Bool) {
        panel.highlight(s)
        panel.recoverFromDim()
        let ghostText = s.replacement.isEmpty ? (s.original ?? "") : s.replacement
        if let caret = lastCaret, !ghostText.isEmpty {
            if fresh || !ghostVisible {
                ghost.appear(text: ghostText, at: caret)
            } else {
                ghost.reArm(text: ghostText, at: caret)
            }
            ghostVisible = true
        }
        setArmed(s)
    }

    /// Continued typing: ghost dissolves fast, panel dissolves over 680 ms (§4/§6).
    func dismissGhost() {
        ghost.disappear(duration: OverlayMotion.ghostTypingFadeOut)
        ghostVisible = false
        setArmed(nil)
        panel.fadeOut()
    }

    /// Esc / focus loss: dissolve both surfaces.
    func dismiss() {
        ghost.disappear()
        panel.fadeOut()
        ghostVisible = false
        setArmed(nil)
    }

    /// Tab accept: flash the armed row, then dissolve both surfaces.
    func acceptArmed() {
        ghost.disappear()
        panel.flashAccept()
        ghostVisible = false
        setArmed(nil)
    }

    private func crossfadeFromCurrentPanel() {
        guard !OverlayMotion.reduceMotion,
              let snapshot = panel.snapshotImage() else { return }
        let frame = panel.frame
        let fader = NSWindow(contentRect: frame,
                             styleMask: .borderless,
                             backing: .buffered,
                             defer: false)
        fader.isOpaque = false
        fader.backgroundColor = .clear
        fader.hasShadow = false
        fader.level = .floating
        fader.ignoresMouseEvents = true
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
        imageView.image = snapshot
        fader.contentView = imageView
        fader.alphaValue = panel.alphaValue
        fader.orderFrontRegardless()
        fader.lexFade(to: 0,
                      duration: OverlayMotion.crossfadeOut,
                      curve: OverlayMotion.dissolveCurve) {
            fader.orderOut(nil)   // strong-captured until the fade completes
        }
    }

    private func setArmed(_ s: Suggestion?) {
        armedSuggestion = s
        onArmChanged?(s)
    }

    func debugSnapshotPanel(to path: String) {
        guard let view = panel.contentView else { return }
        let data = view.dataWithPDF(inside: view.bounds)
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
