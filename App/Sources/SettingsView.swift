import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: RedactorModel

    var body: some View {
        settings
            .frame(width: 480, height: 760)
    }

    private var settings: some View {
        Form {
            Section {
                Picker("Mode", selection: $model.mode) {
                    ForEach(RedactorModel.Mode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                Toggle("Check images", isOn: $model.checksImages)
                Toggle("Check files", isOn: $model.checksFiles)
                KindsRow(skipped: $model.skippedKinds)
                ListRow(list: .ignored, apps: $model.ignoredApps, values: $model.allowlist)
            } header: {
                // In the header, so the card scrolls away with the settings.
                VStack(alignment: .leading, spacing: 20) {
                    ModelCard()
                    Text("Copy")
                }
            } footer: {
                Text("Redact replaces personal data with placeholders like [EMAIL_1]. Warn only tells you.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Warn before pasting", isOn: $model.isChecking)
                ListRow(list: .watched, apps: $model.watchedApps)
                    .disabled(!model.isChecking)
            } header: {
                Text("Paste")
            } footer: {
                Text("Redactor stops a paste of personal data into an app on the watchlist until you choose what to paste.")
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                PermissionRow(
                    title: "Accessibility",
                    detail: "Needed to warn you before a paste.",
                    isGranted: model.hasAccessibility,
                    action: model.requestAccessibility
                )
                PermissionRow(
                    title: "Clipboard access",
                    detail: "Needed to check what you copy.",
                    isGranted: model.clipboardAccess == .alwaysAllow,
                    action: model.openClipboardSettings
                )
            }

            Section {
                LabeledContent("Version", value: Bundle.main.version)
                LabeledContent("Source") {
                    Link("github.com/Desert-Ant-Labs/demo-redactor", destination: URL(string: "https://github.com/Desert-Ant-Labs/demo-redactor")!)
                }
            } footer: {
                Text("Nothing you copy leaves your Mac.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview("Model card") {
    ModelCard()
        .padding(20)
        .frame(width: 480)
}

/// The Redact model card from the brand.
private struct ModelCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Redact.")
                .font(.system(size: 40, weight: .semibold))
                .tracking(-2)
            Text("On-device PII redaction")
                .font(.title3)
            HStack(spacing: 24) {
                if let size = Self.sizeOnDisk() {
                    Spec(value: size, label: "local model")
                }
                Spec(value: "27", label: "languages")
            }
            Link(destination: URL(string: "https://desertant.com/models/redact/")!) {
                Label("desertant.com/models/redact", systemImage: "arrow.up.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .font(.callout)
                    .underline()
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
        }
        .foregroundStyle(Color.cream)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .trailing) { Photo() }
        .background(Color.forest)
        .clipShape(.rect(cornerRadius: 24))
    }
}

/// The photo from the Redact model page, fading into the card on its left.
private struct Photo: View {
    var body: some View {
        Image("RedactPhoto")
            .resizable()
            .scaledToFill()
            .frame(width: 220)
            .clipped()
            .overlay {
                LinearGradient(colors: [.forest, .forest.opacity(0)], startPoint: .leading, endPoint: .init(x: 0.45, y: 0.5))
            }
            .accessibilityHidden(true)
    }
}

extension ModelCard {
    /// What Redact takes in the shared Desert Ant model cache, every version
    /// included. Nothing before the first download.
    static func sizeOnDisk() -> String? {
        let folder = URL.cachesDirectory.appending(path: "desert-ant-models/desert-ant-labs/redact")
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
        let bytes = (files?.allObjects as? [URL] ?? []).reduce(0) { total, file in
            total + ((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        guard bytes > 0 else { return nil }
        // The brand writes units against the number: 11.6MB.
        return Int64(bytes).formatted(.byteCount(style: .file)).replacingOccurrences(of: " ", with: "")
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}

private struct Spec: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.cream.opacity(0.65))
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        LabeledContent {
            if isGranted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow…", action: action)
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}

private extension Bundle {
    var version: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
