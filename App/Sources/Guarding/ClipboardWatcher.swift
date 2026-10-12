import AppKit

/// What Redactor knows about one state of the clipboard, identified by the
/// pasteboard's change count.
struct ClipboardScan: Equatable, Sendable {
    enum Result: Equatable, Sendable {
        /// Text with no personal data, or nothing textual at all.
        case clean
        /// Marked by a password manager or as transient, or an image with
        /// screenshot checks off, so never read.
        case skipped
        case found(Finding)
        /// Redactor swapped the copy for its redacted text.
        case redacted(Finding)
        /// The user put the unredacted copy back, so pasting it is their call.
        case approved(Finding)
        case failed(String)
    }

    /// What kind of thing is on the clipboard, for the menu: never the
    /// content itself.
    enum Contents: Equatable, Sendable {
        case empty
        case text(characters: Int)
        case files(Int)
        case image
        case other

        @MainActor
        init(_ pasteboard: NSPasteboard) {
            if ClipboardWatcher.copiedImage(on: pasteboard) != nil {
                self = .image
            } else if let files = ClipboardWatcher.copiedFiles(on: pasteboard) {
                self = .files(files.count)
            } else if let text = pasteboard.string(forType: .string) {
                self = .text(characters: text.count)
            } else {
                self = pasteboard.types?.isEmpty ?? true ? .empty : .other
            }
        }
    }

    let changeCount: Int
    let result: Result
    let contents: Contents
    /// The app a copy came from, when it is on the ignore list.
    var ignoredSource: String?
}

/// Polls the general pasteboard and scans each new text copy as soon as it
/// lands, so the result is ready before the user pastes.
@MainActor
final class ClipboardWatcher {
    var onScan: (ClipboardScan) -> Void = { _ in }
    var checksImages = true
    var checksFiles = true
    var ignoredApps: Set<String> = []
    private(set) var latest: ClipboardScan?

    private let pasteboard: NSPasteboard
    private let detect: @Sendable (String) async throws -> Finding
    private var lastSeen = -1
    private var polling: Task<Void, Never>?
    private var scanning: Task<Void, Never>?

    init(pasteboard: NSPasteboard = .general, detect: @escaping @Sendable (String) async throws -> Finding) {
        self.pasteboard = pasteboard
        self.detect = detect
    }

    func start() {
        polling = Task { [weak self] in
            while !Task.isCancelled {
                self?.checkNow()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Reading `changeCount` is cheap and never triggers the system's
    /// clipboard access alert, so it is safe to call on every keystroke.
    func checkNow() {
        let count = pasteboard.changeCount
        guard count != lastSeen else { return }
        lastSeen = count
        scanning?.cancel()

        if Self.isMarkedPrivate(pasteboard) {
            publish(ClipboardScan(changeCount: count, result: .skipped, contents: .other))
            return
        }
        // The app in front a moment after the copy is the one it came from.
        if let source = NSWorkspace.shared.frontmostApplication,
           let id = source.bundleIdentifier, ignoredApps.contains(id) {
            publish(ClipboardScan(changeCount: count, result: .skipped, contents: .other, ignoredSource: source.localizedName ?? id))
            return
        }
        let contents = ClipboardScan.Contents(pasteboard)
        if let image = Self.copiedImage(on: pasteboard) {
            if checksImages {
                startImageScan(count, image)
            } else {
                publish(ClipboardScan(changeCount: count, result: .skipped, contents: .image))
            }
            return
        }
        if let files = Self.copiedFiles(on: pasteboard) {
            guard checksFiles else {
                publish(ClipboardScan(changeCount: count, result: .skipped, contents: contents))
                return
            }
            startScan(count, contents) {
                let text = await TextExtraction.text(of: files)
                return (text, files.map(\.lastPathComponent))
            }
            return
        }
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            publish(ClipboardScan(changeCount: count, result: .clean, contents: contents))
            return
        }
        startScan(count, contents) { (text, nil) }
    }

    private func startImageScan(_ count: Int, _ image: Data) {
        scanning = Task { [detect] in
            let result: ClipboardScan.Result
            do {
                let finding = try await ImageRedaction.redact(image, detect: detect)
                result = finding.map { $0.isEmpty ? .clean : .found($0) } ?? .clean
            } catch {
                result = .failed(error.localizedDescription)
            }
            guard !Task.isCancelled else { return }
            publish(ClipboardScan(changeCount: count, result: result, contents: .image))
        }
    }

    /// A screenshot or a copied image. Screenshot tools and Finder put an
    /// image on the clipboard as a file, so a single image file counts too,
    /// read from the file rather than from the icon that comes with it.
    static func copiedImage(on pasteboard: NSPasteboard) -> Data? {
        if let files = copiedFiles(on: pasteboard) {
            guard files.count == 1, TextExtraction.isImage(files[0]) else { return nil }
            return try? Data(contentsOf: files[0])
        }
        guard pasteboard.string(forType: .string) == nil else { return nil }
        return pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
    }

    private func startScan(
        _ count: Int,
        _ contents: ClipboardScan.Contents,
        reading content: @escaping @Sendable () async -> (text: String, files: [String]?)
    ) {
        scanning = Task { [detect] in
            let content = await content()
            let result: ClipboardScan.Result
            do {
                var finding = try await detect(content.text)
                if let files = content.files { finding = finding.copied(from: files) }
                result = finding.isEmpty ? .clean : .found(finding)
            } catch {
                result = .failed(error.localizedDescription)
            }
            guard !Task.isCancelled else { return }
            publish(ClipboardScan(changeCount: count, result: result, contents: contents))
        }
    }

    /// Files copied in Finder, which also put their names on the clipboard
    /// as text. The files are what gets pasted, so they are what gets read.
    static func copiedFiles(on pasteboard: NSPasteboard) -> [URL]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        return urls.isEmpty ? nil : urls
    }

    /// Records a result without scanning or calling `onScan`, for contents
    /// Redactor wrote to the clipboard itself and already knows.
    func adopt(_ scan: ClipboardScan) {
        lastSeen = scan.changeCount
        scanning?.cancel()
        latest = scan
    }

    private func publish(_ scan: ClipboardScan) {
        latest = scan
        onScan(scan)
    }

    /// The nspasteboard.org markers that password managers and clipboard
    /// tools set on items nobody else should keep or read.
    private static let privateTypes: [NSPasteboard.PasteboardType] = [
        .init("org.nspasteboard.ConcealedType"),
        .init("org.nspasteboard.TransientType"),
    ]

    private static func isMarkedPrivate(_ pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.types ?? []
        return privateTypes.contains(where: types.contains)
    }
}
