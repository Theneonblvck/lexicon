import AppKit
import ApplicationServices

private let kTabKeyCode: Int64 = 48

/// A CGEventTap that intercepts the Tab key ONLY while a suggestion is armed:
/// on Tab it accepts (insert + dismiss) and swallows the event; any other key
/// dismisses the ghost. When nothing is armed, Tab passes through untouched.
/// Requires Accessibility + Input Monitoring.
final class EventTapController {
    var isArmed: () -> Bool = { false }
    var onAcceptTab: () -> Void = {}
    var onOtherKey: () -> Void = {}

    fileprivate var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        let mask = (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: tabEventTapCallback,
            userInfo: refcon) else {
            NSLog("[Lexicon] event tap not created — Accessibility/Input Monitoring missing")
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        FileLog.write("event tap started")
        NSLog("[Lexicon] event tap started")
    }

    func stop() {
        guard isRunning, let tap = tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        self.tap = nil
        isRunning = false
        FileLog.write("event tap stopped")
    }

    fileprivate func reEnable() {
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }
}

/// C-compatible event tap callback. `refcon` carries the controller.
private func tabEventTapCallback(proxy: CGEventTapProxy,
                                 type: CGEventType,
                                 event: CGEvent,
                                 refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        controller.reEnable()
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown, controller.isArmed() else {
        return Unmanaged.passUnretained(event)
    }

    let keycode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    let plainTab = keycode == kTabKeyCode
        && !flags.contains(.maskCommand)
        && !flags.contains(.maskControl)
        && !flags.contains(.maskAlternate)

    if plainTab {
        DispatchQueue.main.async { controller.onAcceptTab() }
        return nil // swallow the Tab — it becomes the insertion
    } else if keycode != kTabKeyCode {
        DispatchQueue.main.async { controller.onOtherKey() }
    }
    return Unmanaged.passUnretained(event)
}
