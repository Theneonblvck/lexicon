import AppKit

/// Owns the menu-bar item and renders the menu from `AppState` + `AllowlistStore`.
/// Permissions are re-checked every time the menu opens, so grants made in
/// System Settings appear immediately. `onEngineSync` lets the app start/stop the
/// capture engine when permissions, pause, or the allowlist change.
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let state: AppState
    private let allowlist: AllowlistStore
    private let onEngineSync: () -> Void

    init(state: AppState, allowlist: AllowlistStore, onEngineSync: @escaping () -> Void) {
        self.state = state
        self.allowlist = allowlist
        self.onEngineSync = onEngineSync
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "text.cursor",
                                   accessibilityDescription: "Lexicon")
            button.toolTip = "Lexicon"
        }
        menu.delegate = self
        statusItem.menu = menu
        rebuild()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        state.refreshPermissions()
        rebuild()
        onEngineSync()
    }

    func rebuild() {
        menu.removeAllItems()

        addDisabled("Lexicon")
        addDisabled(statusLine())
        menu.addItem(.separator())

        addPermissionItem(title: "Accessibility",
                          granted: state.accessibilityGranted,
                          action: #selector(grantAccessibility))
        addPermissionItem(title: "Input Monitoring",
                          granted: state.inputMonitoringGranted,
                          action: #selector(grantInputMonitoring))

        menu.addItem(.separator())
        addAllowlistSection()

        menu.addItem(.separator())
        let pause = NSMenuItem(title: "Pause capture",
                               action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pause.state = state.isPaused ? .on : .off
        pause.isEnabled = state.accessibilityGranted
        menu.addItem(pause)

        menu.addItem(.separator())
        let about = NSMenuItem(title: "About Lexicon…",
                               action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: "Quit Lexicon",
                              action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: Allowlist UI

    private func addAllowlistSection() {
        addDisabled("Capture allowlist (default-deny)")

        // Quick-approve the app you were just typing in.
        if let bid = state.lastForegroundBundleId {
            let name = state.lastForegroundName ?? bid
            let item = NSMenuItem(title: "Capture in \(name)",
                                  action: #selector(toggleAllowlist(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = bid
            item.state = allowlist.isAllowed(bid) ? .on : .off
            item.isEnabled = state.accessibilityGranted
            menu.addItem(item)
        }

        // Manage all approved apps.
        let approved = allowlist.approvedBundleIds.sorted()
        if approved.isEmpty {
            addDisabled("   (no apps approved yet)")
        } else {
            let sub = NSMenu()
            for bid in approved {
                let it = NSMenuItem(title: bid,
                                    action: #selector(toggleAllowlist(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = bid
                it.state = .on
                sub.addItem(it)
            }
            let parent = NSMenuItem(title: "Approved apps (\(approved.count))",
                                    action: nil, keyEquivalent: "")
            menu.setSubmenu(sub, for: parent)
            menu.addItem(parent)
        }
    }

    // MARK: Rendering helpers

    private func statusLine() -> String {
        if !state.accessibilityGranted { return "● Status: inert — Accessibility required" }
        if state.isPaused { return "● Status: paused" }
        let n = allowlist.approvedBundleIds.count
        return "● Status: active — \(n) app\(n == 1 ? "" : "s") allowlisted"
    }

    private func addDisabled(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addPermissionItem(title: String, granted: Bool, action: Selector) {
        let item = NSMenuItem(title: "\(granted ? "✓" : "✗")  \(title)\(granted ? "" : " — Grant…")",
                              action: granted ? nil : action, keyEquivalent: "")
        item.target = self
        item.isEnabled = !granted
        menu.addItem(item)
    }

    // MARK: Actions

    @objc private func toggleAllowlist(_ sender: NSMenuItem) {
        guard let bid = sender.representedObject as? String else { return }
        if allowlist.isAllowed(bid) {
            allowlist.revoke(bid)
        } else {
            allowlist.approve(bid)
        }
        rebuild()
        onEngineSync()
    }

    @objc private func grantAccessibility() {
        _ = PermissionsManager.accessibilityGranted(prompt: true)
        PermissionsManager.openAccessibilitySettings()
    }

    @objc private func grantInputMonitoring() {
        PermissionsManager.requestInputMonitoring()
        PermissionsManager.openInputMonitoringSettings()
    }

    @objc private func togglePause() {
        state.isPaused.toggle()
        rebuild()
        onEngineSync()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Lexicon"
        alert.informativeText = """
        System-wide writing companion.

        Model cascade:
        • Tier 1  \(AppConfig.tier1Model)
        • Tier 2  \(AppConfig.tier2Model)
        • Tier 3  \(AppConfig.tier3Model)

        API key: \(AppConfig.apiKeyConfigured ? "configured" : "not configured")
        """
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
