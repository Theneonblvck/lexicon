import Foundation

/// Live application state. The single source of truth the menu renders from.
final class AppState {
    private(set) var accessibilityGranted = false
    private(set) var inputMonitoringGranted = false
    var isPaused = false

    /// Last app (other than Lexicon itself) to come to the foreground. Used by
    /// the menu to offer "Capture in <app>" allowlisting for the app you were
    /// just typing in.
    var lastForegroundName: String?
    var lastForegroundBundleId: String?

    /// Full readiness: both grants present. Input Monitoring is only strictly
    /// needed for Tab interception (Step 5), but the product is "fully active"
    /// only when both are granted.
    var permissionsGranted: Bool { accessibilityGranted && inputMonitoringGranted }

    /// Capture's real dependency is Accessibility alone. It must also not be paused.
    var captureAllowed: Bool { accessibilityGranted && !isPaused }

    func refreshPermissions() {
        accessibilityGranted = PermissionsManager.accessibilityGranted(prompt: false)
        inputMonitoringGranted = PermissionsManager.inputMonitoringGranted()
    }
}
