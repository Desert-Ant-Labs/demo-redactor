import SwiftUI

struct PillView: View {
    let state: PillState
    let actions: PillActions

    var body: some View {
        if let finding = state.finding {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    StatusIcon(isRedacted: state.isRedacted)
                    // Both titles are laid out, one hidden, so the pill is as
                    // wide as the longer one and never resizes on a switch.
                    Steady(isFirst: state.isRedacted) {
                        Text(finding.redactedTitle)
                    } second: {
                        Text(originalTitle(finding))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.cream)
                    .lineLimit(1)
                    Spacer(minLength: 16)
                    SwitchButton(isRedacted: state.isRedacted, choose: actions.choose)
                    HStack(spacing: 0) {
                        IconButton(symbol: "chevron.down", help: state.isExpanded ? "Hide details" : "Show what was found") {
                            actions.toggleDetails()
                        }
                        .rotationEffect(.degrees(state.isExpanded ? 180 : 0))
                        IconButton(symbol: "xmark", help: "Dismiss", action: actions.close)
                    }
                }

                if state.isExpanded {
                    Details(finding: finding)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .fixedSize()
            .glassEffect(.regular.tint(Color.forest.opacity(0.85)), in: .rect(cornerRadius: 24))
            .shadow(color: Color.ink.opacity(0.25), radius: 12, y: 6)
            .animation(.smooth(duration: 0.3), value: state.isRedacted)
            .onHover(perform: actions.hover)
            // Room for the shadow, and the pill sits a little below the menu bar.
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 22)
            .offset(y: state.isShown ? 0 : -60)
            .opacity(state.isShown ? 1 : 0)
            .environment(\.colorScheme, .dark)
        }
    }
}

extension PillView {
    private func originalTitle(_ finding: Finding) -> String {
        guard let app = state.pastedInto else { return finding.foundTitle }
        return finding.pastedTitle(into: app)
    }
}

private struct StatusIcon: View {
    let isRedacted: Bool

    var body: some View {
        Image(systemName: isRedacted ? "eye.slash.fill" : "eye.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isRedacted ? Color.forest : Color.cream)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 30, height: 30)
            .background(isRedacted ? Color.cream : Color.clayRed, in: .circle)
    }
}

private struct SwitchButton: View {
    let isRedacted: Bool
    let choose: (Bool) -> Void

    var body: some View {
        Button {
            choose(!isRedacted)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Steady(isFirst: isRedacted, alignment: .center) {
                    Text("Unredact")
                } second: {
                    Text("Redact")
                }
                .font(.system(size: 12, weight: .semibold))
                .tracking(-0.2)
                Keycap("⌘C")
            }
        }
        .buttonStyle(GlassCapsuleButtonStyle(tint: isRedacted ? Color.cream.opacity(0.14) : Color.clayRed))
        .help("Or copy the same text again within 5s")
        .accessibilityLabel(isRedacted ? "Unredact" : "Redact")
    }
}

private struct Keycap: View {
    let keys: String

    init(_ keys: String) {
        self.keys = keys
    }

    var body: some View {
        Text(keys)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.cream.opacity(0.75))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Color.cream.opacity(0.14), in: .rect(cornerRadius: 4))
            .accessibilityHidden(true)
    }
}

/// Lays out both views and shows one, so whatever holds it keeps the size
/// of the larger.
private struct Steady<First: View, Second: View>: View {
    let isFirst: Bool
    var alignment: Alignment = .leading
    let first: First
    let second: Second

    init(
        isFirst: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder first: () -> First,
        @ViewBuilder second: () -> Second
    ) {
        self.isFirst = isFirst
        self.alignment = alignment
        self.first = first()
        self.second = second()
    }

    var body: some View {
        ZStack(alignment: alignment) {
            first
                .opacity(isFirst ? 1 : 0)
                .accessibilityHidden(!isFirst)
            second
                .opacity(isFirst ? 0 : 1)
                .accessibilityHidden(isFirst)
        }
    }
}

private struct Details: View {
    let finding: Finding

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            ForEach(finding.groups) { group in
                GridRow {
                    Text(group.phrase)
                        .foregroundStyle(Color.cream)
                    Text(group.example)
                        .monospaced()
                        .foregroundStyle(Color.cream.opacity(0.6))
                }
            }
        }
        .font(.callout)
        .padding(.leading, 42)
        .padding(.bottom, 8)
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.cream.opacity(isHovering ? 0.95 : 0.55))
                .frame(width: 28, height: 28)
                .background(Color.cream.opacity(isHovering ? 0.1 : 0), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
    }
}

extension Finding {
    static let preview = Finding(
        items: [(.email, "j.devries@example.nl"), (.bankAccount, "NL91 ABNA 0417 1643 00")],
        redactedText: "Send the invoice to [EMAIL_1], IBAN [BANK_ACCOUNT_1]"
    )
}

private struct PillPreview: View {
    @State private var state = PillState()
    let finding: Finding
    var isRedacted = true
    var pastedInto: String?
    var isExpanded = false

    var body: some View {
        PillView(
            state: state,
            actions: PillActions(
                choose: { state.isRedacted = $0 },
                toggleDetails: { withAnimation(.smooth) { state.isExpanded.toggle() } },
                close: {},
                hover: { _ in }
            )
        )
        .onAppear {
            state.finding = finding
            state.isRedacted = isRedacted
            state.pastedInto = pastedInto
            state.isExpanded = isExpanded
            state.isShown = true
        }
        .padding(40)
        .background(Color.cream)
    }
}

#Preview("Redacted") {
    PillPreview(finding: .preview)
}

#Preview("Original") {
    PillPreview(finding: .preview, isRedacted: false)
}

#Preview("Details") {
    PillPreview(finding: .preview, isExpanded: true)
}

#Preview("After a paste") {
    PillPreview(finding: .preview, isRedacted: false, pastedInto: "Claude")
}

#Preview("Short title") {
    PillPreview(finding: Finding(items: [(.givenName, "Anna")], redactedText: "Call [GIVEN_NAME_1]"))
}
