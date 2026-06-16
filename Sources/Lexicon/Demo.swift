import AppKit

/// Launched via `Lexicon --demo-ui`. Shows the ghost text + suggestions panel
/// with mock data covering all three suggestion kinds and a +N more overflow row.
final class DemoAppDelegate: NSObject, NSApplicationDelegate {
    private var overlay: OverlayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = OverlayController()
        overlay = controller

        let mock = AnalysisResult(
            goalId: "professional-positive-feedback",
            goalLabel: "Express professional approval and suggest continuation",
            confidence: 0.87,
            suggestions: [
                Suggestion(kind: .cadence,
                           original: nil,
                           replacement: "",
                           rationale: "The closing feels abrupt — a softer transition would land better."),
                Suggestion(kind: .vocabulary,
                           original: "went good",
                           replacement: "went well",
                           rationale: "Standard formal phrasing for evaluating outcomes."),
                Suggestion(kind: .syntax,
                           original: "do it again sometime",
                           replacement: "schedule a follow-up",
                           rationale: "More concrete and action-oriented than the casual phrasing."),
                Suggestion(kind: .vocabulary,
                           original: "i think",
                           replacement: "I believe",
                           rationale: "Elevates formality appropriate for professional feedback."),
                Suggestion(kind: .syntax,
                           original: nil,
                           replacement: "in the near term",
                           rationale: "Adds temporal specificity to the suggestion."),
                Suggestion(kind: .vocabulary,
                           original: "good",
                           replacement: "productive",
                           rationale: "Stronger evaluative vocabulary for stakeholders."),
                Suggestion(kind: .syntax,
                           original: "we should",
                           replacement: "I recommend we",
                           rationale: "Signals considered judgment in professional tone."),
            ])

        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let caret = NSRect(x: screen.midX - 120, y: screen.midY, width: 2, height: 18)
        NSApp.activate(ignoringOtherApps: true)
        controller.present(mock, caret: caret)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            controller.debugSnapshotPanel(to: "/tmp/lexicon-panel.pdf")
            // Re-arm second insertable (index 1 is cadence; index 2 is syntax)
            controller.arm(mock.suggestions[2])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                controller.debugSnapshotPanel(to: "/tmp/lexicon-panel-armed2.pdf")
                NSLog("[Lexicon] demo armed=\(controller.armedSuggestion?.replacement ?? "nil")")
                NSApp.terminate(nil)
            }
        }
    }
}
