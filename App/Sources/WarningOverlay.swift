import SwiftUI

struct WarningOverlay: View {
    let state: WarningState
    let showsCard: Bool
    let choose: (PasteWarning.Choice) -> Void

    private var isAlarm: Bool { state.content != .checking }

    var body: some View {
        ZStack {
            Wash(isAlarm: isAlarm)
                .contentShape(.rect)
                .onTapGesture { choose(.cancel) }

            GlowingEdges(isAlarm: isAlarm)
                .allowsHitTesting(false)

            if showsCard {
                WarningCard(state: state, choose: choose)
                    .scaleEffect(state.isShown ? 1 : 0.92)
                    .offset(y: state.isShown ? 0 : 24)
            }
        }
        .opacity(state.isShown ? 1 : 0)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }
}

/// A red tint over the whole screen, deepest at the edges, so whatever is
/// behind stays readable in the middle.
private struct Wash: View {
    let isAlarm: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                (isAlarm ? Color.danger : Color.white).opacity(isAlarm ? 0.16 : 0.04)
                RadialGradient(
                    colors: [.clear, (isAlarm ? Color.danger : Color.black).opacity(0.45)],
                    center: .center,
                    startRadius: min(size.width, size.height) * 0.25,
                    endRadius: max(size.width, size.height) * 0.75
                )
            }
        }
    }
}

/// Three strokes of a turning gradient along the screen's edges: a sharp
/// line, a soft glow, and a wide haze, the outer two breathing.
private struct GlowingEdges: View {
    let isAlarm: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var colors: [Color] {
        isAlarm
            ? [.danger, .clayRed, .ember, .clayRed, .danger]
            : [.white.opacity(0.5), .white.opacity(0.2), .white.opacity(0.5)]
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let gradient = AngularGradient(
                colors: colors,
                center: .center,
                angle: .degrees((t * 36).truncatingRemainder(dividingBy: 360))
            )
            let breath = 0.8 + 0.2 * sin(t * 3.2)

            ZStack {
                Rectangle().strokeBorder(gradient, lineWidth: 3)
                Rectangle().strokeBorder(gradient, lineWidth: 16)
                    .blur(radius: 14)
                    .opacity(breath)
                Rectangle().strokeBorder(gradient, lineWidth: 56)
                    .blur(radius: 56)
                    .opacity(0.75 * breath)
            }
            .blendMode(.plusLighter)
        }
    }
}

private struct WarningCard: View {
    let state: WarningState
    let choose: (PasteWarning.Choice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch state.content {
            case .checking:
                Heading(symbol: "eye", tint: .white, title: "Checking the clipboard", detail: "Before it goes into \(state.app).")
                HStack {
                    Spacer()
                    Button("Cancel") { choose(.cancel) }
                }
            case .found(let finding):
                Heading(
                    symbol: "eye.trianglebadge.exclamationmark.fill",
                    tint: .clayRed,
                    title: finding.foundTitle,
                    detail: "You're pasting into \(state.app)."
                )
                Findings(finding: finding)
                HStack(spacing: 10) {
                    Button("Cancel") { choose(.cancel) }
                    Spacer()
                    Button("Paste Anyway") { choose(.pasteAnyway) }
                    Button("Paste Redacted") { choose(.pasteRedacted) }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(.black)
                }
                Text("Return pastes redacted. Escape cancels.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            case .failed(let message):
                Heading(symbol: "exclamationmark.triangle.fill", tint: .ember, title: "Redactor couldn't check the clipboard", detail: message)
                HStack {
                    Button("Cancel") { choose(.cancel) }
                    Spacer()
                    Button("Paste Anyway") { choose(.pasteAnyway) }
                }
            }
        }
        .controlSize(.large)
        .padding(28)
        .frame(width: 460, alignment: .leading)
        .glassEffect(.regular.tint(.black.opacity(0.35)), in: .rect(cornerRadius: 28))
        .shadow(color: .danger.opacity(0.5), radius: 40)
        // Swallow taps on the card, so only a tap on the wash cancels.
        .contentShape(.rect(cornerRadius: 28))
        .onTapGesture {}
    }
}

private struct Heading: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.pulse, options: .repeat(.continuous))
            Text(title)
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.6)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

private struct Findings: View {
    let finding: Finding

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            ForEach(finding.groups) { group in
                GridRow {
                    Text(group.phrase)
                    Text(group.example)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.body)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 14))
    }
}

private struct WarningPreview: View {
    @State private var state = WarningState()
    let content: PasteWarning.Content

    var body: some View {
        WarningOverlay(state: state, showsCard: true) { _ in }
            .onAppear {
                state.content = content
                state.app = "Claude"
                state.isShown = true
            }
            .frame(width: 900, height: 600)
            .background(Color.cream)
    }
}

#Preview("Paste warning") {
    WarningPreview(content: .found(.preview))
}

#Preview("Checking") {
    WarningPreview(content: .checking)
}

#Preview("Couldn't check") {
    WarningPreview(content: .failed("The model didn't load."))
}
