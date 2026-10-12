import AppKit

/// One keystroke as the event tap saw it, copied out of the `CGEvent` so it
/// can cross onto the main actor.
struct KeyPress: Sendable {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
    let character: String
    let isReplay: Bool

    init(_ event: CGEvent) {
        keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        flags = event.flags
        var length = 0
        var units = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &units)
        character = String(utf16CodeUnits: units, count: length).lowercased()
        isReplay = event.getIntegerValueField(.eventSourceUserData) == PasteTap.replayMarker
    }

    var isEscape: Bool { keyCode == 53 }
    /// Return, or Enter on the keypad.
    var isReturn: Bool { keyCode == 36 || keyCode == 76 }

    /// Command V, with or without Shift for "paste and match style". The
    /// character, not the key code, so it holds on AZERTY and Dvorak too.
    var isPaste: Bool {
        character == "v" && flags.contains(.maskCommand)
            && !flags.contains(.maskControl) && !flags.contains(.maskAlternate)
    }
}

/// A session event tap on key down. Command V into another app can be held
/// back and replayed later; nothing else is touched.
///
/// The tap runs on the main run loop and must answer at once: macOS disables
/// a tap that stalls. So the handler only compares change counts. It never
/// reads the pasteboard and never waits on the model.
@MainActor
final class PasteTap {
    /// Return true to swallow the keystroke.
    var handle: (KeyPress) -> Bool = { _ in false }

    /// Set on the events `replay` posts, so the tap lets its own paste through.
    nonisolated static let replayMarker: Int64 = 0x5264_6374 // "Rdct"

    private var port: CFMachPort?

    var isRunning: Bool { port != nil }

    /// Fails until the user grants Accessibility.
    @discardableResult
    func start() -> Bool {
        guard port == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: pasteTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        return true
    }

    func replay(_ key: KeyPress) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: isDown) else { continue }
            event.flags = key.flags.intersection([.maskCommand, .maskShift])
            event.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    fileprivate func receive(_ type: CGEventType, _ key: KeyPress?) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        case .keyDown:
            guard let key, !key.isReplay else { return false }
            return handle(key)
        default:
            return false
        }
    }
}

private func pasteTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<PasteTap>.fromOpaque(userInfo).takeUnretainedValue()
    let key = type == .keyDown ? KeyPress(event) : nil
    let swallow = MainActor.assumeIsolated { tap.receive(type, key) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
