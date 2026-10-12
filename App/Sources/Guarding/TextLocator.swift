import AppKit
import ApplicationServices

/// Finds where pasted values sit on screen, by asking the focused text field
/// of the app for its text and for the bounds of each range.
///
/// Native text views answer reliably. Chrome and Electron apps answer only
/// once a client turns on their accessibility tree, and may answer nothing.
enum TextLocator {
    /// Chrome and Electron build their accessibility tree only when asked.
    static func prepare(_ pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Rects in screen coordinates, bottom-left origin like `NSWindow` frames,
    /// for each value inside the text that was just pasted.
    static func rects(of values: [String], pasted: String, in pid: pid_t) -> [CGRect] {
        let app = AXUIElementCreateApplication(pid)
        // A busy app would otherwise hold the main thread for seconds.
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let field = element(app, kAXFocusedUIElementAttribute),
              let text = attribute(field, kAXValueAttribute) as? String
        else { return [] }

        let content = text as NSString
        let scope = pastedRange(in: field, length: (pasted as NSString).length, of: content.length)
        return Set(values).flatMap { value in
            ranges(of: value, in: content, within: scope).compactMap { bounds(of: $0, in: field) }
        }
    }

    /// The paste ends at the caret, so only text just before it is searched,
    /// and an earlier mention of the same value is left alone.
    private static func pastedRange(in field: AXUIElement, length: Int, of total: Int) -> NSRange {
        guard let selection = attribute(field, kAXSelectedTextRangeAttribute),
              CFGetTypeID(selection) == AXValueGetTypeID()
        else { return NSRange(location: 0, length: total) }
        var caret = CFRange()
        AXValueGetValue(selection as! AXValue, .cfRange, &caret)
        // Line endings can change on paste, so allow some slack.
        let end = min(caret.location, total)
        let start = max(0, end - length - 16)
        return NSRange(location: start, length: end - start)
    }

    private static func ranges(of value: String, in text: NSString, within scope: NSRange) -> [NSRange] {
        var found: [NSRange] = []
        var range = text.range(of: value, range: scope)
        while range.location != NSNotFound {
            found.append(range)
            let rest = NSRange(location: range.upperBound, length: scope.upperBound - range.upperBound)
            range = text.range(of: value, range: rest)
        }
        return found
    }

    private static func bounds(of range: NSRange, in field: AXUIElement) -> CGRect? {
        var span = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &span) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            field, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &value
        ) == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        AXValueGetValue(value as! AXValue, .cgRect, &rect)
        // A value that wraps comes back as one tall rect; skip it rather than
        // underline a whole paragraph.
        guard rect.width > 0, rect.height > 0, rect.height < 60 else { return nil }
        return flipped(rect)
    }

    /// Accessibility measures from the top of the main screen, AppKit from
    /// the bottom.
    private static func flipped(_ rect: CGRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
