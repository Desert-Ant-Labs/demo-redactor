import SwiftUI

/// A row in Settings: how many kinds of personal data Redactor looks for,
/// and the sheet to turn kinds off.
struct KindsRow: View {
    @Binding var skipped: Set<Finding.Kind>
    @State private var isEditing = false

    var body: some View {
        LabeledContent("Personal data") {
            HStack(spacing: 10) {
                Text(summary)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Edit…") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            KindsSheet(skipped: $skipped)
        }
    }

    private var summary: String {
        let all = Finding.Kind.allCases.count
        return skipped.isEmpty ? "All" : "\(all - skipped.count) of \(all)"
    }
}

private struct KindsSheet: View {
    @Binding var skipped: Set<Finding.Kind>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Personal data")
                    .font(.headline)
                Text("Redactor redacts and warns about the kinds that are on.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Form {
                ForEach(Finding.Kind.allCases, id: \.self) { kind in
                    Toggle(kind.title, isOn: Binding(
                        get: { !skipped.contains(kind) },
                        set: { isOn in
                            if isOn { skipped.remove(kind) } else { skipped.insert(kind) }
                        }
                    ))
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .padding(.horizontal, -20)

            HStack {
                Button("Turn All On") { skipped = [] }
                    .disabled(skipped.isEmpty)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400, height: 560)
    }
}
