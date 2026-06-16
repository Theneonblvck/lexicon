import AppKit
import ApplicationServices

/// Observes the focused text element of the FRONTMOST app via the Accessibility
/// API and emits debounced `CaptureEvent`s. Enforces three privacy rules before
/// any text leaves this class:
///   1. default-deny allowlist (capture only in user-approved apps),
///   2. secure-field exclusion (never read password fields),
///   3. global pause / Accessibility-granted gate.
final class CaptureEngine {

    /// Called on the main thread with each debounced capture.
    var onEvent: ((CaptureEvent) -> Void)?

    private let state: AppState
    private let allowlist: AllowlistStore

    private var appElement: AXUIElement?
    private var observer: AXObserver?
    private var focusedElement: AXUIElement?

    private var debounceItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.35

    private(set) var isRunning = false

    init(state: AppState, allowlist: AllowlistStore) {
        self.state = state
        self.allowlist = allowlist
    }

    // MARK: Lifecycle

    func start() {
        guard !isRunning else { return }
        guard PermissionsManager.accessibilityGranted(prompt: false) else {
            NSLog("[Lexicon] capture not started — Accessibility not granted")
            return
        }
        isRunning = true
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostAppChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil)
        if let app = NSWorkspace.shared.frontmostApplication {
            attach(to: app)
        }
        FileLog.write("engine started — AXIsProcessTrusted=\(AXIsProcessTrusted())")
        NSLog("[Lexicon] capture engine started")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil)
        detach()
        debounceItem?.cancel()
        NSLog("[Lexicon] capture engine stopped")
    }

    // MARK: Frontmost-app tracking

    @objc private func frontmostAppChanged(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
        attach(to: app)
    }

    private func attach(to app: NSRunningApplication) {
        detach()
        let pid = app.processIdentifier
        guard pid > 0 else { return }

        let appEl = AXUIElementCreateApplication(pid)
        appElement = appEl

        var obs: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &obs) == .success,
              let observer = obs else {
            NSLog("[Lexicon] AXObserverCreate failed for pid \(pid)")
            return
        }
        self.observer = observer

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, appEl,
                                  kAXFocusedUIElementChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(),
                           AXObserverGetRunLoopSource(observer), .defaultMode)
        refreshFocusedElement()
    }

    private func detach() {
        if let observer = observer {
            if let appEl = appElement {
                AXObserverRemoveNotification(observer, appEl,
                    kAXFocusedUIElementChangedNotification as CFString)
            }
            if let focused = focusedElement {
                AXObserverRemoveNotification(observer, focused,
                    kAXValueChangedNotification as CFString)
                AXObserverRemoveNotification(observer, focused,
                    kAXSelectedTextChangedNotification as CFString)
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(),
                                  AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        appElement = nil
        focusedElement = nil
    }

    /// Re-points value/caret notifications at the newly focused element.
    fileprivate func refreshFocusedElement() {
        guard let appEl = appElement, let observer = observer else { return }

        if let prev = focusedElement {
            AXObserverRemoveNotification(observer, prev, kAXValueChangedNotification as CFString)
            AXObserverRemoveNotification(observer, prev, kAXSelectedTextChangedNotification as CFString)
        }

        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl,
                kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let focused = ref else {
            focusedElement = nil
            return
        }
        let element = focused as! AXUIElement
        focusedElement = element

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, element, kAXValueChangedNotification as CFString, refcon)
        AXObserverAddNotification(observer, element, kAXSelectedTextChangedNotification as CFString, refcon)
        scheduleCapture()
    }

    fileprivate func handleValueChanged() {
        scheduleCapture()
    }

    // MARK: Debounce + capture

    private func scheduleCapture() {
        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.captureNow() }
        debounceItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }

    private func captureNow() {
        guard state.captureAllowed else { return }           // pause / Accessibility gate
        guard let element = focusedElement else { return }
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleId = app.bundleIdentifier else { return }

        guard allowlist.isAllowed(bundleId) else { return }   // default-deny allowlist
        if isSecureField(element) {                           // never read password fields
            FileLog.write("skip secure field  app=\(app.localizedName ?? bundleId)")
            return
        }

        guard let text = stringAttribute(element, kAXValueAttribute as String) else { return }
        let caret = selectedRange(element) ?? NSRange(location: text.utf16.count, length: 0)

        let event = CaptureEvent(
            text: text,
            caretRange: caret,
            appBundleId: bundleId,
            appName: app.localizedName ?? bundleId,
            elementRef: element)
        let preview = text.replacingOccurrences(of: "\n", with: "\u{23CE}").prefix(80)
        FileLog.write("capture  app=\(event.appName)  len=\(text.utf16.count)  caret=\(caret.location)  text=\"\(preview)\"")
        onEvent?(event)
    }

    /// The currently focused text element, for insertion (Step 5).
    func focusedElementRef() -> AXUIElement? { focusedElement }

    /// Current caret rectangle in Cocoa screen coordinates, if the focused
    /// element exposes bounds. Used to anchor the ghost text (Step 4).
    func caretCocoaRect() -> NSRect? {
        guard let element = focusedElement else { return nil }
        let range = selectedRange(element) ?? NSRange(location: 0, length: 0)
        return CaretLocator.caretCocoaRect(element: element, range: range)
    }

    // MARK: AX helpers

    private func isSecureField(_ element: AXUIElement) -> Bool {
        guard let subrole = stringAttribute(element, kAXSubroleAttribute as String) else { return false }
        return subrole == (kAXSecureTextFieldSubrole as String)
    }

    private func stringAttribute(_ element: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private func selectedRange(_ element: AXUIElement) -> NSRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,
                kAXSelectedTextRangeAttribute as CFString, &ref) == .success,
              let value = ref, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
}

/// C-compatible AXObserver callback. `refcon` carries the engine instance.
private func axObserverCallback(_ observer: AXObserver,
                                _ element: AXUIElement,
                                _ notification: CFString,
                                _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon = refcon else { return }
    let engine = Unmanaged<CaptureEngine>.fromOpaque(refcon).takeUnretainedValue()
    if (notification as String) == (kAXFocusedUIElementChangedNotification as String) {
        engine.refreshFocusedElement()
    } else {
        engine.handleValueChanged()
    }
}
