import AppKit
import ApplicationServices

/// Inserts an accepted suggestion into the focused element.
///
/// Strategy, best-first:
///   1. **Span replacement** — if the suggestion names an `original` span, locate
///      it near the caret, select it, and replace it (so "went good" → "went well"
///      edits in place rather than appending).
///   2. **Smart additive insert** — otherwise insert at the caret, adding a leading
///      space when the preceding char isn't whitespace and the text doesn't already
///      start with a space/punctuation (fixes "objectiveswithout").
///   3. **Clipboard-preserving ⌘V** — when AX writes aren't supported at all.
enum Inserter {

    /// Test seam: disable the synthesized ⌘V so the clipboard save/restore logic
    /// can be exercised headlessly without pasting into a live app.
    static var postKeystrokes = true

    @discardableResult
    static func insert(_ suggestion: Suggestion, into element: AXUIElement?) -> String {
        guard suggestion.kind.isInsertable else { return "skipped-cadence" }
        let target = element ?? freshFocusedElement()
        if let element = target, let method = applyAX(suggestion, to: element) {
            return method
        }
        // No usable AX element: paste the replacement (can't compute spacing without context).
        pasteFallback(suggestion.replacement)
        return "paste"
    }

    // MARK: AX insertion

    private static func applyAX(_ suggestion: Suggestion, to element: AXUIElement) -> String? {
        guard let value = readString(element, kAXValueAttribute),
              let caret = readCaret(element) else { return nil }

        if let original = suggestion.original, !original.isEmpty,
           let span = findSpan(original, in: value, near: caret) {
            guard setSelectedRange(element, span),
                  setSelectedText(element, suggestion.replacement) else { return nil }
            return "ax-span"
        }

        let spaced = smartSpaced(suggestion.replacement, value: value, caret: caret)
        guard setSelectedText(element, spaced) else { return nil }
        return "ax-insert"
    }

    /// Locate `needle`, preferring the occurrence ending at or before the caret
    /// (what the user is most likely editing), else the first occurrence.
    private static func findSpan(_ needle: String, in haystack: String, near caret: Int) -> NSRange? {
        let ns = haystack as NSString
        let upto = NSRange(location: 0, length: min(max(caret, 0), ns.length))
        let backward = ns.range(of: needle, options: .backwards, range: upto)
        if backward.location != NSNotFound { return backward }
        let forward = ns.range(of: needle)
        return forward.location != NSNotFound ? forward : nil
    }

    /// Adds a leading space when joining to a non-space char and the text doesn't
    /// already begin with a space or closing punctuation.
    private static func smartSpaced(_ text: String, value: String, caret: Int) -> String {
        let ns = value as NSString
        let idx = min(max(caret, 0), ns.length)
        guard idx > 0, let prev = ns.substring(with: NSRange(location: idx - 1, length: 1)).first else {
            return text
        }
        let startsSpaceOrPunct = text.first.map { $0 == " " || ",.;:!?)]}".contains($0) } ?? true
        return (!prev.isWhitespace && !startsSpaceOrPunct) ? " " + text : text
    }

    // MARK: AX primitives

    private static func setSelectedText(_ element: AXUIElement, _ text: String) -> Bool {
        let err = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFString)
        if err != .success {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
            FileLog.write("insert AX setSelectedText failed role=\(roleRef as? String ?? "?") err=\(err.rawValue)")
        }
        return err == .success
    }

    private static func setSelectedRange(_ element: AXUIElement, _ range: NSRange) -> Bool {
        var cf = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cf) else { return false }
        return AXUIElementSetAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    private static func readString(_ element: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func readCaret(_ element: AXUIElement) -> Int? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, &ref) == .success,
              let value = ref, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range.location
    }

    private static func freshFocusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                system, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let value = ref else { return nil }
        return (value as! AXUIElement)
    }

    // MARK: Clipboard-preserving paste fallback

    static func pasteFallback(_ text: String) {
        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)

        pb.clearContents()
        pb.setString(text, forType: .string)

        let src = CGEventSource(stateID: .combinedSessionState)
        let v: CGKeyCode = 9 // 'v'
        let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        up?.flags = .maskCommand
        if postKeystrokes {
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            pb.clearContents()
            if let saved { pb.setString(saved, forType: .string) }
        }
    }
}
