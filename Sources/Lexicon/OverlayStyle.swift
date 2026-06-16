import AppKit

/// Layout and visual constants from docs/UX-SPECIFICATION.md §1–2 (static pass).
enum OverlayStyle {
    static let panelWidth: CGFloat = 320
    static let cornerRadius: CGFloat = 12
    static let padding: CGFloat = 14
    static let rowSpacing: CGFloat = 8
    static let caretGap: CGFloat = 12
    static let screenInset: CGFloat = 8
    static let noCaretInset: CGFloat = 16
    static let ghostOpacity: CGFloat = 0.45
    static let maxVisibleRows = 6
    static let armedFillAlpha: CGFloat = 0.12
    static let scrimAlpha: CGFloat = 0.18
    static let accentRuleWidth: CGFloat = 2
    static let symbolSize: CGFloat = 14

    static var usesSolidSurface: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    static func panelShadow() -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.shadowBlurRadius = 24
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        shadow.shadowColor = NSColor.black.withAlphaComponent(isDark ? 0.40 : 0.18)
        return shadow
    }

    /// Panel root: vibrancy material or solid surface when Increase Contrast is on.
    static func makePanelRoot() -> NSView {
        if usesSolidSurface {
            let view = NSView()
            view.wantsLayer = true
            view.layer?.cornerRadius = cornerRadius
            view.layer?.borderWidth = 1
            view.layer?.borderColor = NSColor.separatorColor.cgColor
            view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            return view
        }
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.masksToBounds = true

        let scrim = NSView()
        scrim.wantsLayer = true
        scrim.layer?.backgroundColor = NSColor.windowBackgroundColor
            .withAlphaComponent(scrimAlpha).cgColor
        scrim.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(scrim)
        NSLayoutConstraint.activate([
            scrim.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            scrim.topAnchor.constraint(equalTo: effect.topAnchor),
            scrim.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        return effect
    }

    static func screenContaining(point: NSPoint) -> NSScreen {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
