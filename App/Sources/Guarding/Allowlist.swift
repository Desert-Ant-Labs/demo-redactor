import Foundation
import Redact

/// The user's own details, which Redactor never flags: their email address,
/// phone number, name.
struct Allowlist: Sendable, Equatable {
    static let defaultsKey = "allowlist"

    let values: [String]

    init(_ values: [String]) {
        self.values = values
    }

    /// Read on every scan, off the main actor; UserDefaults is thread-safe.
    static var stored: Allowlist {
        Allowlist(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
    }

    func allows(_ value: String, as label: Label) -> Bool {
        values.contains { Self.matches(value, $0, as: label) }
    }

    /// Phone numbers match on their last 9 digits, so a number with a country
    /// code matches the same number without one. Names match any word of an
    /// entry, because Redact reports a given name and a surname as two spans.
    private static func matches(_ value: String, _ allowed: String, as label: Label) -> Bool {
        if isPhoneLike(value), isPhoneLike(allowed) {
            return digits(value).suffix(9) == digits(allowed).suffix(9)
        }
        let value = normalized(value)
        let allowed = normalized(allowed)
        if value == allowed { return true }
        if label == .givenName || label == .surname {
            return allowed.split(whereSeparator: \.isWhitespace).contains { $0 == value }
        }
        return false
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func digits(_ text: String) -> String {
        text.filter(\.isNumber)
    }

    private static func isPhoneLike(_ text: String) -> Bool {
        let digits = digits(text).count
        return digits >= 6 && text.allSatisfy { $0.isNumber || " +-().".contains($0) }
    }
}
