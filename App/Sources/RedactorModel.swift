import AppKit
import Observation
import Redact
import ServiceManagement

@MainActor
@Observable
final class RedactorModel {
    enum ModelState: Equatable {
        case downloading(Double)
        case ready
        case failed(String)
    }

    /// Links are left out: people paste them all day, and few are personal.
    nonisolated static let options = Options(labels: Label.defaultEnabled.subtracting([.url]))

    /// Copying the same text again within this window flips the clipboard
    /// between the redacted text and the original.
    static let recopyWindow: TimeInterval = 5

    private(set) var modelState: ModelState = .downloading(0)
    private(set) var clipboard: ClipboardScan?
    private(set) var hasAccessibility = AXIsProcessTrusted()
    private(set) var clipboardAccess = NSPasteboard.general.accessBehavior
    var isChecking = UserDefaults.standard.object(forKey: "isChecking") as? Bool ?? true {
        didSet { UserDefaults.standard.set(isChecking, forKey: "isChecking") }
    }

    var checksImages = UserDefaults.standard.object(forKey: "checksImages") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(checksImages, forKey: "checksImages")
            watcher.checksImages = checksImages
        }
    }

    var checksFiles = UserDefaults.standard.object(forKey: "checksFiles") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(checksFiles, forKey: "checksFiles")
            watcher.checksFiles = checksFiles
        }
    }

    enum Mode: String, CaseIterable {
        /// Copies are redacted as they land; copying again keeps the original.
        case redact
        /// Copies stay as they are and the pill says what it found.
        case warn
        case off
    }

    var mode = UserDefaults.standard.string(forKey: "mode").flatMap(Mode.init) ?? .redact {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "mode")
            switch mode {
            case .off:
                pill.hide()
            case .redact:
                if case .found(let finding) = clipboard?.result, finding.files == nil, isCurrent(clipboard) {
                    writeRedacted(finding)
                    pill.show(finding, isRedacted: true)
                }
            case .warn:
                break
            }
        }
    }

    var watchedApps = AppList.watched.stored {
        didSet { AppList.watched.store(watchedApps) }
    }

    var ignoredApps = AppList.ignored.stored {
        didSet {
            AppList.ignored.store(ignoredApps)
            watcher.ignoredApps = ignoredApps
        }
    }

    /// Scans read it straight from UserDefaults.
    var skippedKinds = Finding.Kind.skipped {
        didSet { UserDefaults.standard.set(skippedKinds.map(\.rawValue).sorted(), forKey: Finding.Kind.skippedKey) }
    }

    /// Scans read it straight from UserDefaults.
    var allowlist = Allowlist.stored.values {
        didSet { UserDefaults.standard.set(allowlist, forKey: Allowlist.defaultsKey) }
    }

    @ObservationIgnored private let redact: Redact
    @ObservationIgnored private let watcher: ClipboardWatcher
    @ObservationIgnored private let tap = PasteTap()
    @ObservationIgnored private let warning = PasteWarning()
    @ObservationIgnored private let pill = ClipboardPill()
    @ObservationIgnored private let highlight = PasteHighlight()
    @ObservationIgnored private var original: KeptCopy?
    @ObservationIgnored private var held: Held?
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?

    /// The user's own copy, kept in memory while the pill can still put it back.
    private struct KeptCopy {
        let snapshot: PasteboardSnapshot
        let finding: Finding
        let text: String?
        let copiedAt: Date
    }

    /// A Command V the tap swallowed, waiting on the scan or on the user.
    private struct Held {
        let key: KeyPress
        let app: NSRunningApplication
        let changeCount: Int
    }

    init() {
        let redact = Redact()
        self.redact = redact
        watcher = ClipboardWatcher { text in
            Finding(try await Chunking.detect(in: text, using: redact, options: RedactorModel.options), allowing: .stored, skipping: Finding.Kind.skipped)
        }
        watcher.checksImages = checksImages
        watcher.checksFiles = checksFiles
        watcher.ignoredApps = ignoredApps
        watcher.onScan = { [weak self] in self?.didScan($0) }
        tap.handle = { [weak self] in self?.handle($0) ?? false }
        warning.onChoice = { [weak self] in self?.resolve($0) }
        pill.onChoose = { [weak self] in self?.choose(redacted: $0) }
        start()
    }

    /// The DA mark: amber while Warn leaves personal data on the clipboard,
    /// clay red while Redact mode has an unredacted copy out, faded when off.
    var menuImage: String {
        switch clipboard?.result {
        case .found, .approved: return mode == .warn ? "MenuBarMarkWarn" : "MenuBarMarkAlert"
        default: return mode != .off ? "MenuBarMark" : "MenuBarMarkPaused"
        }
    }

    func toggleRedaction() {
        switch clipboard?.result {
        case .redacted: choose(redacted: false)
        case .found, .approved: choose(redacted: true)
        default: break
        }
    }

    func requestAccessibility() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    func openClipboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard")!)
    }

    private func start() {
        watcher.start()
        Task { await loadModel() }
        Task { await watchPermissions() }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            MainActor.assumeIsolated { self?.appActivated(pid) }
        }
        // After launch finishes, so the alert can show.
        Task {
            if MoveToApplications.offer() { return }
            offerOpenAtLogin()
            if !hasAccessibility { requestAccessibility() }
        }
    }

    /// Asked once: Redactor only checks the clipboard while it runs.
    private func offerOpenAtLogin() {
        let key = "askedOpenAtLogin"
        guard !UserDefaults.standard.bool(forKey: key), SMAppService.mainApp.status != .enabled else { return }
        UserDefaults.standard.set(true, forKey: key)
        let alert = NSAlert()
        alert.messageText = "Open Redactor at login?"
        alert.informativeText = "Redactor only checks what you copy while it runs. You can change this in Settings."
        alert.addButton(withTitle: "Open at Login")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            try? SMAppService.mainApp.register()
        }
    }

    private func loadModel() async {
        do {
            // Downloads the weights on first launch, and loads them every launch.
            try await redact.download { fraction in
                Task { @MainActor in self.modelState = .downloading(fraction) }
            }
            modelState = .ready
        } catch {
            modelState = .failed(error.localizedDescription)
        }
    }

    /// Neither grant posts a notification, so check every couple of seconds
    /// and start the tap as soon as Accessibility comes through.
    private func watchPermissions() async {
        while !Task.isCancelled {
            let trusted = AXIsProcessTrusted()
            if trusted != hasAccessibility { hasAccessibility = trusted }
            let access = NSPasteboard.general.accessBehavior
            if access != clipboardAccess { clipboardAccess = access }
            if trusted, !tap.isRunning { tap.start() }
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

extension RedactorModel {
    /// Called from the event tap, so it has to answer at once.
    private func handle(_ key: KeyPress) -> Bool {
        if held != nil, let content = warning.content {
            if key.isEscape {
                resolve(.cancel)
                return true
            }
            if key.isReturn, case .found = content {
                resolve(.pasteRedacted)
                return true
            }
        }

        guard key.isPaste, mode != .off, isChecking,
              let app = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = app.bundleIdentifier, watchedApps.contains(bundleIdentifier)
        else { return false }

        watcher.checkNow()
        let count = NSPasteboard.general.changeCount
        let scan = watcher.latest?.changeCount == count ? watcher.latest : nil
        let paste = Held(key: key, app: app, changeCount: count)

        switch scan?.result {
        case .clean, .skipped, .redacted:
            return false
        case .approved(let finding):
            // The tap has to answer now, so the follow-up waits a turn.
            Task { afterPaste(of: finding, into: app, reminding: true) }
            return false
        case nil:
            hold(paste, showing: .checking)
        case .found(let finding):
            hold(paste, showing: .found(finding))
        case .failed(let message):
            hold(paste, showing: .failed(message))
        }
        return true
    }

    private func hold(_ paste: Held, showing content: PasteWarning.Content) {
        held = paste
        warning.show(content, pastingInto: paste.app.displayName)
    }

    private func didScan(_ scan: ClipboardScan) {
        let previous = clipboard
        clipboard = scan
        // A scan can finish after the user has already copied something
        // else; that copy gets its own scan.
        guard isCurrent(scan) else { return }
        if mode == .off {
            // Kept, so switching to Redact can still redact this copy.
            if case .found(let finding) = scan.result {
                original = KeptCopy(snapshot: PasteboardSnapshot(.general), finding: finding, text: nil, copiedAt: .now)
            }
            return
        }

        if case .found(let finding) = scan.result {
            let text = NSPasteboard.general.string(forType: .string)
            let isRecopy = isRecopy(of: text)
            // A copied file stays a file until the user asks for its text:
            // swapping it silently would paste text where they meant a file.
            let redact = isRecopy ? !Self.isRedacted(previous) : mode == .redact && finding.files == nil
            original = KeptCopy(snapshot: PasteboardSnapshot(.general), finding: finding, text: text, copiedAt: .now)
            if redact {
                writeRedacted(finding)
            } else if isRecopy {
                // Asked for by name, so a paste of it goes through unchecked.
                adopt(.approved(finding))
            }
            pill.show(finding, isRedacted: redact, isChosen: isRecopy && !redact)
        } else {
            original = nil
            pill.hide()
        }

        // A paste made before the scan finished goes on with what is on the
        // clipboard now, which auto-redact may just have changed.
        guard let held, held.changeCount == scan.changeCount, warning.content == .checking else { return }
        switch clipboard?.result {
        case .clean, .skipped, .redacted, .approved, nil:
            self.held = nil
            warning.hide()
            tap.replay(held.key)
        case .found(let finding):
            warning.show(.found(finding), pastingInto: held.app.displayName)
        case .failed(let message):
            warning.show(.failed(message), pastingInto: held.app.displayName)
        }
    }

    private func isRecopy(of text: String?) -> Bool {
        guard let original, let text, original.text == text else { return false }
        return Date.now.timeIntervalSince(original.copiedAt) < Self.recopyWindow
    }

    private static func isRedacted(_ scan: ClipboardScan?) -> Bool {
        if case .redacted = scan?.result { return true }
        return false
    }

    private func isCurrent(_ scan: ClipboardScan?) -> Bool {
        scan?.changeCount == NSPasteboard.general.changeCount
    }

    private func writeRedacted(_ finding: Finding) {
        PasteboardSnapshot.writeRedacted(finding, to: .general)
        adopt(.redacted(finding))
    }

    private func choose(redacted: Bool) {
        guard let original, isCurrent(clipboard) else { return }
        if redacted {
            writeRedacted(original.finding)
        } else {
            original.snapshot.restore(to: .general)
            adopt(.approved(original.finding))
        }
        pill.setRedacted(redacted)
    }

    private func adopt(_ result: ClipboardScan.Result) {
        let pasteboard = NSPasteboard.general
        let scan = ClipboardScan(changeCount: pasteboard.changeCount, result: result, contents: .init(pasteboard))
        watcher.adopt(scan)
        clipboard = scan
    }

    private func resolve(_ choice: PasteWarning.Choice) {
        let content = warning.content
        warning.hide()
        guard let held else { return }
        self.held = nil

        switch choice {
        case .cancel:
            break
        case .pasteAnyway:
            tap.replay(held.key)
            if case .found(let finding) = content {
                afterPaste(of: finding, into: held.app, reminding: false)
            }
        case .pasteRedacted:
            guard case .found(let finding) = content else { return }
            pasteRedacted(finding, key: held.key)
        }
    }

    /// Swaps the redacted text onto the clipboard, pastes it, and puts the
    /// user's own copy back, so the next paste somewhere safe still has it.
    private func pasteRedacted(_ finding: Finding, key: KeyPress) {
        let pasteboard = NSPasteboard.general
        let original = PasteboardSnapshot(pasteboard)
        PasteboardSnapshot.writeRedacted(finding, to: pasteboard, transient: true)
        adopt(.redacted(finding))
        tap.replay(key)

        Task {
            // The target app reads the pasteboard when it handles the
            // keystroke, a moment after the event is posted.
            try? await Task.sleep(for: .milliseconds(600))
            original.restore(to: pasteboard)
            adopt(.found(finding))
        }
    }

    /// A paste with personal data went through. The pill says so when the
    /// user might have forgotten, and the values get a brief underline where
    /// the app shows them.
    private func afterPaste(of finding: Finding, into app: NSRunningApplication, reminding: Bool) {
        if reminding {
            pill.remind(finding, pastedInto: app.displayName)
        }
        let pasted = NSPasteboard.general.string(forType: .string) ?? ""
        let pid = app.processIdentifier
        TextLocator.prepare(pid)
        Task {
            // The app inserts the text a moment after it handles the keystroke.
            try? await Task.sleep(for: .milliseconds(350))
            highlight.flash(TextLocator.rects(of: finding.values, pasted: pasted, in: pid))
        }
    }

    /// The user went somewhere else, so the paste they were deciding on is moot.
    private func appActivated(_ pid: pid_t?) {
        guard let held, pid != held.app.processIdentifier,
              pid != ProcessInfo.processInfo.processIdentifier
        else { return }
        resolve(.cancel)
    }
}

private extension NSRunningApplication {
    var displayName: String { localizedName ?? "this app" }
}
