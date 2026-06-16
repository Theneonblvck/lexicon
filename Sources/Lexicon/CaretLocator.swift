import AppKit
import ApplicationServices

/// Resolves the on-screen rectangle of the caret/selection in an arbitrary app's
/// focused text element, converting the Accessibility API's top-left global
/// coordinates into Cocoa bottom-left coordinates for window placement.
enum CaretLocator {

    static func caretCocoaRect(element: AXUIElement, range: NSRange) -> NSRect? {
        var cfRange = CFRange(location: range.location, length: max(range.length, 1))
        guard let axRange = AXValueCreate(.cfRange, &cfRange) else { return nil }

        var boundsRef: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            axRange,
            &boundsRef)
        guard err == .success, let value = boundsRef,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }

        // AX returns global coords with a top-left origin; flip to Cocoa's
        // bottom-left using the primary screen's height.
        guard let primary = NSScreen.screens.first else { return nil }
        let cocoaY = primary.frame.height - rect.origin.y - rect.height
        return NSRect(x: rect.origin.x,
                      y: cocoaY,
                      width: max(rect.width, 1),
                      height: max(rect.height, 16))
    }
}
