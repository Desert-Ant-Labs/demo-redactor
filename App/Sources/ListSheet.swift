import AppKit
import SwiftUI

extension AppList {
    var title: String {
        switch self {
        case .watched: "Watchlist"
        case .ignored: "Whitelist"
        }
    }

    var explanation: String {
        switch self {
        case .watched: "Redactor checks what you paste into these apps."
        case .ignored: "Redactor never reads what you copy from these apps, and never flags your own details."
        }
    }
}

/// A row in Settings: the list's name, what is on it, and the sheet to edit
/// it. Only the whitelist has values.
struct ListRow: View {
    let list: AppList
    @Binding var apps: Set<String>
    var values: Binding<[String]>?
    @State private var isEditing = false

    var body: some View {
        LabeledContent(list.title) {
            HStack(spacing: 10) {
                Text(summary)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Edit…") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            ListSheet(list: list, apps: $apps, values: values)
        }
    }

    private var summary: String {
        let apps = InstalledApp.count(of: apps)
        guard let count = values?.wrappedValue.count, count > 0 else { return apps }
        return "\(apps), \(count == 1 ? "1 detail" : "\(count) details")"
    }
}

private struct ListSheet: View {
    let list: AppList
    @Binding var apps: Set<String>
    let values: Binding<[String]>?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(list.title)
                    .font(.headline)
                Text(list.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let values {
                Text("Apps").font(.subheadline.weight(.semibold))
                AppListEditor(apps: $apps)
                Text("Your details").font(.subheadline.weight(.semibold))
                DetailsField(values: values)
                Text("Separate values with a comma. Phone numbers match with or without the country code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                AppListEditor(apps: $apps)
            }

            HStack {
                Button("Restore Default Apps") { apps = list.defaults }
                    .disabled(apps == list.defaults)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440, height: values == nil ? 480 : 600)
    }
}

/// Apps on a list, added with + or dropped in from Finder.
private struct AppListEditor: View {
    @Binding var apps: Set<String>
    @State private var selection: Set<String> = []

    private var installed: [InstalledApp] { InstalledApp.all(in: apps) }

    var body: some View {
        EditableList {
            List(selection: $selection) {
                ForEach(installed) { app in
                    Label {
                        Text(app.name)
                    } icon: {
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                    }
                    .tag(app.id)
                }
            }
            .onDeleteCommand(perform: removeSelection)
            .dropDestination(for: URL.self) { urls, _ in
                add(urls)
                return true
            }
            .overlay {
                if installed.isEmpty {
                    ContentUnavailableView("No Apps", systemImage: "app.dashed", description: Text("Click + or drop an app here."))
                }
            }
        } bar: {
            Button(action: choose) {
                Image(systemName: "plus").frame(width: 24, height: 20)
            }
            .help("Add an app")
            Divider().frame(height: 14)
            Button(action: removeSelection) {
                Image(systemName: "minus").frame(width: 24, height: 20)
            }
            .disabled(selection.isEmpty)
            .help("Remove the selected apps")
            Spacer()
        }
    }

    private func removeSelection() {
        apps.subtract(selection)
        selection = []
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(filePath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    private func add(_ urls: [URL]) {
        for url in urls {
            if let id = Bundle(url: url)?.bundleIdentifier { apps.insert(id) }
        }
    }
}

/// The user's own details, comma separated in one field.
private struct DetailsField: View {
    @Binding var values: [String]
    @State private var text = ""

    var body: some View {
        TextField("Your details", text: $text, prompt: Text("Email, phone number, or name"), axis: .vertical)
            .labelsHidden()
            .lineLimit(2...4)
            .onAppear { text = values.joined(separator: ", ") }
            .onChange(of: text) {
                values = text.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
    }
}

/// The macOS list editor: a bordered list with its buttons in a bar under it.
private struct EditableList<Content: View, Bar: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var bar: Bar

    var body: some View {
        VStack(spacing: 0) {
            content
                .listStyle(.bordered)
                .alternatingRowBackgrounds()
            HStack(spacing: 0) { bar }
                .buttonStyle(.borderless)
                .padding(4)
                .background(.background.secondary)
                .overlay(alignment: .top) { Divider() }
        }
        .clipShape(.rect(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
    }
}

/// An app on a list that is installed on this Mac. Apps on a list but not
/// installed stay on it, unlisted, until they are.
private struct InstalledApp: Identifiable {
    let id: String
    let name: String
    let icon: NSImage

    static func all(in ids: Set<String>) -> [InstalledApp] {
        ids.compactMap { id in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { url in
                InstalledApp(
                    id: id,
                    // The bundle's name, not the file's: "Xcode", not "Xcode-27.1.0-beta".
                    name: Bundle(url: url).flatMap { $0.object(forInfoDictionaryKey: "CFBundleDisplayName") ?? $0.object(forInfoDictionaryKey: "CFBundleName") } as? String
                        ?? url.deletingPathExtension().lastPathComponent,
                    icon: NSWorkspace.shared.icon(forFile: url.path)
                )
            }
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func count(of ids: Set<String>) -> String {
        let count = ids.count { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        return count == 1 ? "1 app" : "\(count) apps"
    }
}
