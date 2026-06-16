import AppKit
import ApplicationServices
import IOKit.hid

/// Wraps the two macOS privacy gates Lexicon needs to operate system-wide:
///   • Accessibility   — to read the focused text element of other apps (Step 2)
///   • Input Monitoring — to intercept the Tab key via a CGEventTap (Step 5)
///
/// We NEVER attempt to bypass TCC. The app requests grants explicitly and stays
/// inert until the user approves them in System Settings.
enum PermissionsManager {

    // MARK: Accessibility

    /// Returns whether the process is trusted for the Accessibility API.
    /// Pass `prompt: true` to surface the system "open System Settings" dialog.
    static func accessibilityGranted(prompt: Bool) -> Bool {
        // Key constant value is "AXTrustedCheckOptionPrompt"; using the literal
        // avoids CFString/Unmanaged bridging differences across SDKs.
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: Input Monitoring

    static func inputMonitoringGranted() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Triggers the system Input Monitoring permission prompt (first call only).
    @discardableResult
    static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    // MARK: Deep links into System Settings

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
