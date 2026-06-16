import AppKit

/// Launched via `Lexicon --demo-ui`. Shows the ghost text + suggestions panel
/// with a mock AnalysisResult so the Step 4 UI can be verified visually without
/// Accessibility, a focused field, or live API calls.
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
                Suggestion(original: "went good",
                           replacement: "went well",
                           rationale: "Standard formal phrasing for evaluating outcomes."),
                Suggestion(original: "do it again sometime",
                           replacement: "schedule a follow-up",
                           rationale: "More concrete and action-oriented than the casual phrasing."),
                Suggestion(original: "i think",
                           replacement: "I believe",
                           rationale: "Elevates formality appropriate for professional feedback."),
            ])

        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let caret = NSRect(x: screen.midX - 120, y: screen.midY, width: 2, height: 18)
        NSApp.activate(ignoringOtherApps: true)
        controller.present(mock, caret: caret)

        // Self-snapshot the rendered panel for verification, then re-arm a
        // different suggestion to prove selection updates the armed state.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            controller.debugSnapshotPanel(to: "/tmp/lexicon-panel.pdf")
            controller.arm(mock.suggestions[1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                controller.debugSnapshotPanel(to: "/tmp/lexicon-panel-armed2.pdf")
                NSLog("[Lexicon] demo armed=\(controller.armedSuggestion?.replacement ?? "nil")")
            }
        }
    }
}
