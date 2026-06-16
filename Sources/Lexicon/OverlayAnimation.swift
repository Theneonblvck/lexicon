import AppKit

/// Thought-like motion constants and helpers (docs/UX-SPECIFICATION.md §4).
///
/// All motion is opacity-led with a small companion vertical drift, driven on the
/// CA layer via `NSAnimationContext`/`CABasicAnimation`. Every animation collapses to
/// a 100 ms linear opacity step under Reduce Motion (no drift / cascade / auto-dim /
/// cross-fade / dip-swap), per the §4 accessibility requirement.
enum OverlayMotion {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // Fade-in
    static let ghostFadeIn: TimeInterval = 0.36
    static let panelFadeIn: TimeInterval = 0.42
    static let panelLeadDelay: TimeInterval = 0.08   // panel starts 80 ms after the ghost
    static let rowCascadeStep: TimeInterval = 0.03
    static let rowFade: TimeInterval = 0.28

    // Dwell / auto-dim
    static let dwellBeforeDim: TimeInterval = 6.0
    static let autoDimDuration: TimeInterval = 0.90
    static let dimmedAlpha: CGFloat = 0.55
    static let recoverDuration: TimeInterval = 0.22

    // Fade-out
    static let fadeOut: TimeInterval = 0.68
    static let ghostTypingFadeOut: TimeInterval = 0.16   // continued typing: ghost leaves fast
    static let rowReverseCascadeStep: TimeInterval = 0.024
    static let crossfadeOut: TimeInterval = 0.30
    static let acceptFlash: TimeInterval = 0.12

    // Arm dip-swap (ghost text changes without flicker)
    static let dipDuration: TimeInterval = 0.20
    static let dipLow: CGFloat = 0.18

    // Reduce Motion
    static let reducedStep: TimeInterval = 0.10

    // Drift (points; +y is upward in Cocoa)
    static let ghostDrift: CGFloat = 4
    static let panelDrift: CGFloat = 6
    static let fadeOutDrift: CGFloat = 3

    static let ghostOpacity: CGFloat = OverlayStyle.ghostOpacity
    static let armedFlashAlpha: CGFloat = 0.24

    static var surfaceCurve: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
    }
    static var dissolveCurve: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.40, 0.0, 1.0, 1.0)
    }
    static var linearCurve: CAMediaTimingFunction {
        CAMediaTimingFunction(name: .linear)
    }
}

extension NSWindow {
    /// Animate `alphaValue` to `endAlpha`, optionally drifting the frame origin's y
    /// from `driftFromY` toward `driftToY`. Under Reduce Motion this collapses to a
    /// 100 ms linear opacity step with no drift.
    func lexFade(to endAlpha: CGFloat,
                 duration: TimeInterval,
                 curve: CAMediaTimingFunction,
                 driftFromY: CGFloat? = nil,
                 driftToY: CGFloat? = nil,
                 completion: (() -> Void)? = nil) {
        let reduce = OverlayMotion.reduceMotion
        if let driftFromY, !reduce {
            setFrameOrigin(NSPoint(x: frame.origin.x, y: driftFromY))
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = reduce ? OverlayMotion.reducedStep : duration
            ctx.timingFunction = reduce ? OverlayMotion.linearCurve : curve
            animator().alphaValue = endAlpha
            if let driftToY, !reduce {
                animator().setFrameOrigin(NSPoint(x: frame.origin.x, y: driftToY))
            }
        }, completionHandler: completion)
    }
}
