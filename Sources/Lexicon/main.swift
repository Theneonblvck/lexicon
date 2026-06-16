import AppKit

// Lexicon — system-wide writing companion.
// Entry point. Menu-bar-only (accessory) app: no dock icon, no main window.
// Step 1 scope: foundations & permissions. Capture/analysis/overlay/tap arrive
// in later build steps; this binary is intentionally inert until permissions
// are granted.

// Headless verification mode: `Lexicon --analyze "<text>"` runs one analysis
// against the live API (key from LEXICON_API_KEY or Keychain) and exits, without
// starting the menu-bar app. Used to verify the Step 3 analysis layer.
if let idx = CommandLine.arguments.firstIndex(of: "--analyze") {
    let text = CommandLine.arguments.indices.contains(idx + 1)
        ? CommandLine.arguments[idx + 1]
        : "i think the meeting went good and we should do it again"
    let model = ProcessInfo.processInfo.environment["LEXICON_TEST_MODEL"] ?? AppConfig.tier1Model
    let sem = DispatchSemaphore(value: 0)
    Task {
        let started = Date()
        do {
            let r = try await ClaudeAPIClient().analyze(
                text: text, caret: text.utf16.count, model: model)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            print("model=\(model)  \(ms)ms")
            print("goalId=\(r.goalId)")
            print("goalLabel=\(r.goalLabel)")
            print("confidence=\(r.confidence)")
            print("suggestions (\(r.suggestions.count)):")
            for s in r.suggestions {
                print("  • [\(s.kind.rawValue)] [\(s.original ?? "")] → \(s.replacement)   (\(s.rationale))")
            }
        } catch {
            print("ERROR: \(error)")
        }
        sem.signal()
    }
    sem.wait()
    exit(0)
}

// Headless self-test: clipboard-preserving paste fallback save/restore.
if CommandLine.arguments.contains("--selftest-clipboard") {
    let pb = NSPasteboard.general
    let original = "ORIGINAL-CLIP-12345"
    pb.clearContents()
    pb.setString(original, forType: .string)
    Inserter.postKeystrokes = false
    Inserter.pasteFallback("REPLACEMENT-INSERTED")
    let during = pb.string(forType: .string)
    RunLoop.main.run(until: Date().addingTimeInterval(0.5)) // let async restore fire
    let after = pb.string(forType: .string)
    print("during paste: \(during ?? "nil")")
    print("after restore: \(after ?? "nil")")
    print(after == original
          ? "PASS: clipboard preserved across paste fallback"
          : "FAIL: clipboard not restored")
    exit(after == original ? 0 : 1)
}

// Visual demo of the Step 4 overlay UI with mock data (no AX / API needed).
if CommandLine.arguments.contains("--demo-ui") {
    let app = NSApplication.shared
    let demo = DemoAppDelegate()
    app.delegate = demo
    app.setActivationPolicy(.regular) // visible app for screenshotting the panel
    app.run()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // runtime equivalent of LSUIElement
    app.run()
}
