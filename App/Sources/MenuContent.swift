import SwiftUI

struct MenuContent: View {
    @Bindable var model: RedactorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header(mode: $model.mode)
            ClipboardCard(scan: model.clipboard, toggle: model.toggleRedaction)
            if let problem = model.problem {
                ProblemRow(problem: problem, model: model)
            }
            Divider()
            Footer()
        }
        .padding(16)
        .frame(width: 320)
        .foregroundStyle(Color.cream)
        // The system menu material is grey under any text; forest matches the pill.
        .background(Color.forest.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }
}

extension RedactorModel {
    var problem: MenuProblem? {
        switch modelState {
        case .downloading(let fraction) where fraction > 0 && fraction < 1:
            return .loading("Downloading Redact: \(Int(fraction * 100))%")
        case .downloading:
            return .loading("Loading Redact")
        case .failed(let message):
            return .failed("Redact didn't load: \(message)")
        case .ready:
            return hasAccessibility ? nil : .needsAccessibility
        }
    }
}

enum MenuProblem: Equatable {
    case loading(String)
    case failed(String)
    case needsAccessibility
}

/// Redact, Warn, or Off, as a glass thumb on a soft track.
struct ModePicker: View {
    @Binding var mode: RedactorModel.Mode
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RedactorModel.Mode.allCases, id: \.self) { segment($0) }
        }
        .padding(3)
        .background(Color.cream.opacity(0.08), in: .capsule)
        .animation(.smooth(duration: 0.25), value: mode)
        .accessibilityRepresentation {
            Picker("Redactor", selection: $mode) {
                ForEach(RedactorModel.Mode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        }
    }

    private func segment(_ value: RedactorModel.Mode) -> some View {
        Button {
            mode = value
        } label: {
            Text(value.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.cream.opacity(mode == value ? 1 : 0.55))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    if mode == value {
                        Capsule()
                            .fill(Color.cream.opacity(0.14))
                            .glassEffect(.regular, in: .capsule)
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

extension RedactorModel.Mode {
    var title: String {
        switch self {
        case .redact: "Redact"
        case .warn: "Warn"
        case .off: "Off"
        }
    }

    var light: Color {
        switch self {
        case .redact: .green
        case .warn: .ember
        case .off: .clayRed
        }
    }
}

private struct Header: View {
    @Binding var mode: RedactorModel.Mode

    var body: some View {
        HStack(spacing: 8) {
            Image("MenuBarMark")
            Text("Redactor")
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.4)
            Spacer()
            LED(color: mode.light, blinks: mode != .off)
            ModePicker(mode: $mode)
                .fixedSize()
        }
    }
}

private struct LED: View {
    let color: Color
    let blinks: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period = 1.8

    var body: some View {
        // A clock drives the blink, so it keeps going after the menu window
        // has been hidden and shown again.
        TimelineView(.animation(paused: !blinks || reduceMotion)) { context in
            let level = blinks && !reduceMotion ? Self.level(at: context.date) : 1
            Circle()
                .fill(color.gradient)
                .frame(width: 5, height: 5)
                .opacity(0.35 + 0.65 * level)
                .shadow(color: color.opacity(0.8 * level), radius: 2.5 * level)
        }
    }

    private static func level(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return (1 + cos(phase * 2 * .pi)) / 2
    }
}

struct ClipboardCard: View {
    let scan: ClipboardScan?
    let toggle: () -> Void

    private var result: ClipboardScan.Result? { scan?.result }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(symbolColor)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 34, height: 34)
                .background(discColor, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.2)
                if let detail {
                    // The full summary when it fits, a count when it doesn't.
                    ViewThatFits(in: .horizontal) {
                        Text(detail)
                        if let short { Text(short) }
                    }
                    .font(.caption)
                    .foregroundStyle(Color.cream.opacity(0.65))
                }
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            if let action {
                Button(action, action: toggle)
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(GlassCapsuleButtonStyle(tint: action == "Redact" ? .clayRed : .cream.opacity(0.14)))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cream.opacity(0.07), in: .rect(cornerRadius: 14))
    }

    private var symbol: String {
        switch result {
        case .redacted: "eye.slash.fill"
        case .found, .approved: "eye.fill"
        case .failed: "exclamationmark"
        case .skipped: "key.fill"
        case .clean, nil: "checkmark"
        }
    }

    private var discColor: Color {
        switch result {
        case .redacted: .cream
        case .found, .approved: .clayRed
        case .failed: .ember
        case .clean, .skipped, nil: .sage
        }
    }

    private var symbolColor: Color {
        switch result {
        case .clean, .skipped, .redacted, nil: .forest
        default: .cream
        }
    }

    private var title: String {
        switch result {
        case .redacted: "Redacted"
        case .found, .approved: "Not redacted"
        case .failed: "Couldn't check"
        case .skipped:
            if let source = scan?.ignoredSource { "Copied from \(source)" }
            else if scan?.contents == .image { "Image not checked" }
            else if case .files(let count) = scan?.contents { count == 1 ? "File not checked" : "Files not checked" }
            else { "Password, not read" }
        case .clean: scan?.contents == .empty ? "Clipboard is empty" : "No personal data found"
        case nil: "Nothing copied yet"
        }
    }

    /// What was found, then what is on the clipboard: "1 email, 52 characters".
    private var detail: String? {
        switch result {
        case .failed(let message): return message
        case .redacted(let finding), .found(let finding), .approved(let finding):
            return finding.files?.count == 1 ? finding.files?.first : finding.summary
        case .skipped: return scan?.ignoredSource == nil ? nil : "Not checked"
        default: return contents(nil)
        }
    }

    private var short: String? {
        switch result {
        case .redacted(let finding), .found(let finding), .approved(let finding):
            finding.itemCount == 1 ? "1 item" : "\(finding.itemCount) items"
        default: nil
        }
    }

    private func contents(_ finding: Finding?) -> String? {
        switch scan?.contents {
        case .text(let characters): return characters == 1 ? "1 character" : "\(characters.formatted()) characters"
        case .files(let count):
            if count == 1, let name = finding?.files?.first { return name }
            return count == 1 ? "1 file" : "\(count) files"
        case .image: return "Image"
        case .other: return result == .skipped ? nil : "Not text"
        case .empty, nil: return nil
        }
    }

    private var action: String? {
        switch result {
        case .redacted: "Unredact"
        case .found, .approved: "Redact"
        default: nil
        }
    }
}

private struct ProblemRow: View {
    let problem: MenuProblem
    let model: RedactorModel

    var body: some View {
        HStack(spacing: 8) {
            switch problem {
            case .loading(let text):
                ProgressView().controlSize(.small)
                Text(text)
            case .failed(let text):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.ember)
                Text(text)
            case .needsAccessibility:
                Image(systemName: "hand.raised.fill").foregroundStyle(Color.ember)
                Text("Allow Accessibility to check pastes")
                Spacer()
                Button("Allow…", action: model.requestAccessibility)
                    .controlSize(.small)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A menu bar app is never active on its own, so the Settings window would
/// open behind the frontmost app without the activate.
private struct Footer: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack {
            Button("Settings…") {
                NSApp.activate()
                openSettings()
            }
            .keyboardShortcut(",")
            Button("Check for Updates…") { Updates.shared.check() }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color.cream.opacity(0.7))
        .font(.callout)
    }
}

#Preview("Clipboard states") {
    VStack(spacing: 10) {
        ClipboardCard(scan: ClipboardScan(changeCount: 0, result: .redacted(.preview), contents: .text(characters: 52))) {}
        ClipboardCard(scan: ClipboardScan(changeCount: 0, result: .found(.preview), contents: .files(1))) {}
        ClipboardCard(scan: ClipboardScan(changeCount: 0, result: .clean, contents: .text(characters: 214))) {}
        ClipboardCard(scan: ClipboardScan(changeCount: 0, result: .clean, contents: .empty)) {}
    }
    .padding(16)
    .frame(width: 320)
    .foregroundStyle(Color.cream)
    .background(Color.forest)
    .environment(\.colorScheme, .dark)
}
