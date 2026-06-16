import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private let state = AppState()
    private let allowlist = AllowlistStore()
    private var captureEngine: CaptureEngine?
    private let router = AnalysisRouter()
    private var overlay: OverlayController?
    private let eventTap = EventTapController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.refreshPermissions()

        // Dev affordance: when LEXICON_PROMPT_ON_LAUNCH is set, surface the
        // Accessibility prompt on launch if not yet granted. This also registers
        // the app in the Accessibility list so it can be toggled on. Off by default.
        if ProcessInfo.processInfo.environment["LEXICON_PROMPT_ON_LAUNCH"] != nil {
            if !state.accessibilityGranted {
                _ = PermissionsManager.accessibilityGranted(prompt: true)
            }
            if !state.inputMonitoringGranted {
                PermissionsManager.requestInputMonitoring() // registers in the Input Monitoring list
            }
        }

        overlay = OverlayController()
        router.onResult = { [weak self] result, tier, _ in
            guard let self else { return }
            let top = result.suggestions.first?.replacement ?? "—"
            NSLog("[Lexicon] analysis \(tier) goal=\(result.goalId) top=\"\(top)\"")
            // Step 4: render ghost text + suggestions panel at the caret.
            self.overlay?.present(result, caret: self.captureEngine?.caretCocoaRect())
        }

        let engine = CaptureEngine(state: state, allowlist: allowlist)
        engine.onEvent = { [router] event in
            router.handle(event)
        }
        captureEngine = engine

        // Step 5: global Tab interception → insert the armed suggestion.
        eventTap.isArmed = { [weak self] in self?.overlay?.armedSuggestion != nil }
        eventTap.onAcceptTab = { [weak self] in
            guard let self, let s = self.overlay?.armedSuggestion, s.kind.isInsertable else { return }
            let method = Inserter.insert(s, into: self.captureEngine?.focusedElementRef())
            FileLog.write("accepted via Tab [\(method)]: \"\(s.replacement)\"")
            self.overlay?.acceptArmed()
        }
        eventTap.onOtherKey = { [weak self] in self?.overlay?.dismissGhost() }

        statusBar = StatusBarController(
            state: state,
            allowlist: allowlist,
            onEngineSync: { [weak self] in self?.applyEngineState() })

        applyEngineState()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil)
    }

    /// Track the last non-Lexicon foreground app (for the allowlist menu) and
    /// re-sync permissions + engine whenever focus changes.
    @objc private func appActivated(_ note: Notification) {
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           let bid = app.bundleIdentifier, bid != AppConfig.bundleIdentifier {
            state.lastForegroundBundleId = bid
            state.lastForegroundName = app.localizedName ?? bid
        }
        state.refreshPermissions()
        statusBar?.rebuild()
        applyEngineState()
    }

    /// Capture runs only with Accessibility granted and not paused.
    private func applyEngineState() {
        guard let engine = captureEngine else { return }
        if state.captureAllowed {
            engine.start()
        } else {
            engine.stop()
        }
        // The Tab tap needs Accessibility (post) + Input Monitoring (intercept).
        if state.permissionsGranted {
            eventTap.start()
        } else {
            eventTap.stop()
        }
    }
}
