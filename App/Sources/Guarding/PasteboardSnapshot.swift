import AppKit

/// Every item and type on a pasteboard, so Redactor can put the user's own
/// copy back after it pastes a redacted one.
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.writeObjects(items.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types {
                item.setData(data, forType: type)
            }
            return item
        })
    }

    /// The blurred image for an image, the text with placeholders for
    /// anything else. Transient keeps clipboard history apps, and Redactor's
    /// own watcher, away from it.
    static func writeRedacted(_ finding: Finding, to pasteboard: NSPasteboard, transient: Bool = false) {
        let item = NSPasteboardItem()
        if let image = finding.redactedImage {
            item.setData(image, forType: .png)
        } else {
            item.setString(finding.redactedText, forType: .string)
        }
        if transient {
            item.setData(Data(), forType: .init("org.nspasteboard.TransientType"))
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }
}
