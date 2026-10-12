/// The apps where a paste can leave the Mac: agents and chat, browsers, team
/// chat, and email. A paste into anything else goes through unchecked.
///
/// Terminals and code editors stay off on purpose. Developers paste into them
/// all day, and agents that run in a terminal are better caught by a hook.
enum Watchlist {
    static let bundleIdentifiers: Set<String> = [
        // Agents and chat
        "com.anthropic.claudefordesktop",
        "com.openai.chat",
        "com.todesktop.230313mzl4w4u92", // Cursor

        // Browsers
        "com.apple.Safari",
        "com.google.Chrome",
        "org.mozilla.firefox",
        "company.thebrowser.Browser", // Arc
        "com.microsoft.edgemac",
        "com.brave.Browser",

        // Team chat and messages
        "com.tinyspeck.slackmacgap",
        "com.microsoft.teams2",
        "com.apple.MobileSMS",
        "net.whatsapp.WhatsApp",
        "ru.keepcoder.Telegram",
        "org.whispersystems.signal-desktop",
        "com.hnc.Discord",

        // Email
        "com.apple.mail",
        "com.microsoft.Outlook",
        "com.readdle.SparkDesktop.appstore",
    ]

    static func contains(_ bundleIdentifier: String?) -> Bool {
        bundleIdentifier.map(bundleIdentifiers.contains) ?? false
    }
}
