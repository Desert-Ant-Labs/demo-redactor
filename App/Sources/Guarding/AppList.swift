import Foundation

/// A list of apps by bundle ID, with its defaults in a JSON file in
/// `App/Resources`: kinds of app, each a map from an app's name to its
/// bundle ID. The user edits the list in Settings.
enum AppList: String, CaseIterable {
    /// Where a paste gets checked: chat, AI, email, and browsers. Terminals
    /// and code editors stay off; agents in a terminal are better caught by
    /// a hook.
    case watched = "app-watchlist"
    /// Where a copy is never read: password managers, terminals, and editors.
    case ignored = "app-whitelist"

    var defaults: Set<String> {
        Bundle.main.url(forResource: rawValue, withExtension: "json").flatMap(Self.load) ?? []
    }

    var stored: Set<String> {
        UserDefaults.standard.stringArray(forKey: rawValue).map(Set.init) ?? defaults
    }

    func store(_ ids: Set<String>) {
        UserDefaults.standard.set(ids.sorted(), forKey: rawValue)
    }

    static func load(_ url: URL) -> Set<String>? {
        guard let data = try? Data(contentsOf: url),
              let kinds = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else { return nil }
        return Set(kinds.values.flatMap(\.values))
    }
}
