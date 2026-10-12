import Foundation
import Redact

/// The personal data Redact found in one piece of text, grouped the way a
/// person reads it: "2 emails and 1 phone number", not eleven spans.
struct Finding: Equatable, Sendable {
    struct Group: Equatable, Sendable, Identifiable {
        let kind: Kind
        let count: Int
        /// The first value of this kind, masked so the pill never shows the
        /// data it warns about.
        let example: String

        var id: Kind { kind }
        var phrase: String { count == 1 ? "1 \(kind.singular)" : "\(count) \(kind.plural)" }
    }

    /// What a person calls each kind of data. Redact reports an address as
    /// several spans; a person sees one address.
    enum Kind: String, CaseIterable, Sendable {
        case name, address, email, phone, card, bankAccount, id, ipAddress, imei

        init?(_ label: Label) {
            switch label {
            case .givenName, .surname: self = .name
            case .streetName, .buildingNumber, .secondaryAddress, .city, .state, .zipCode: self = .address
            case .email: self = .email
            case .phone: self = .phone
            case .creditCard: self = .card
            case .bankAccount, .routingNumber: self = .bankAccount
            case .governmentID, .passport, .driversLicense, .taxID, .ssn: self = .id
            case .ipAddress: self = .ipAddress
            case .imei: self = .imei
            // A link is rarely personal and pasted all day. A company is not a person.
            case .url, .org: return nil
            }
        }

        var singular: String {
            switch self {
            case .name: "name"
            case .address: "address"
            case .email: "email"
            case .phone: "phone number"
            case .card: "card number"
            case .bankAccount: "bank account"
            case .id: "ID number"
            case .ipAddress: "IP address"
            case .imei: "IMEI"
            }
        }

        var plural: String {
            switch self {
            case .address: "addresses"
            case .ipAddress: "IP addresses"
            default: singular + "s"
            }
        }

        /// "Phone numbers", as a setting.
        var title: String { plural.prefix(1).uppercased() + plural.dropFirst() }

        /// The kinds the user turned off in Settings. Read on every scan, off
        /// the main actor; UserDefaults is thread-safe.
        static let skippedKey = "skippedKinds"
        static var skipped: Set<Kind> {
            Set((UserDefaults.standard.stringArray(forKey: skippedKey) ?? []).compactMap(Kind.init(rawValue:)))
        }
    }

    let groups: [Group]
    /// The text with every finding swapped for a placeholder like `[EMAIL_1]`.
    let redactedText: String
    /// The personal data itself, so a paste of it can be found on screen.
    let values: [String]
    /// The names of the files it came from, when files were copied.
    private(set) var files: [String]?
    /// Set when the copy was an image: true, and the image with each value
    /// blurred once there is something to blur.
    private(set) var isImage = false
    private(set) var redactedImage: Data?

    /// "1 email on the clipboard", or "customers.csv has 1 email".
    var foundTitle: String {
        if isImage { return "Image with \(summary)" }
        guard let files else { return "\(summary) on the clipboard" }
        return files.count == 1 ? "\(files[0]) has \(summary)" : "\(files.count) files have \(summary)"
    }

    /// "Redacted 1 email", or "Redacted text of customers.csv".
    var redactedTitle: String {
        if isImage { return "Blurred \(summary)" }
        guard let files else { return "Redacted \(summary)" }
        return files.count == 1 ? "Redacted text of \(files[0])" : "Redacted text of \(files.count) files"
    }

    /// "Pasted 1 email into Claude", or "Pasted customers.csv into Claude".
    func pastedTitle(into app: String) -> String {
        if isImage { return "Pasted an image with \(summary) into \(app)" }
        guard let files else { return "Pasted \(summary) into \(app)" }
        return files.count == 1 ? "Pasted \(files[0]) into \(app)" : "Pasted \(files.count) files into \(app)"
    }

    func copied(from files: [String]) -> Finding {
        var finding = self
        finding.files = files
        return finding
    }

    func read(fromImage redactedImage: Data?) -> Finding {
        var finding = self
        finding.isImage = true
        finding.redactedImage = redactedImage
        return finding
    }

    var isEmpty: Bool { groups.isEmpty }
    var itemCount: Int { groups.reduce(0) { $0 + $1.count } }

    /// "2 emails and 1 phone number"
    var summary: String {
        groups.map(\.phrase).formatted(.list(type: .and))
    }

    init(items: [(label: Label, original: String)], redactedText: String) {
        let kept = items.compactMap { item in Kind(item.label).map { (kind: $0, item: item) } }
        let byKind = Dictionary(grouping: kept, by: \.kind).mapValues { $0.map(\.item) }
        groups = Kind.allCases.compactMap { kind in
            guard let items = byKind[kind], let first = items.first else { return nil }
            return Group(kind: kind, count: Self.count(items, as: kind), example: Self.mask(first.original))
        }
        self.redactedText = redactedText
        values = kept.map(\.item.original)
    }

    /// Builds the finding from Redact's result, minus the user's own details
    /// and the kinds they turned off.
    ///
    /// Redact reports an email inside a link as part of one URL span, and
    /// links are left alone, so the email would go through. Sweeping the
    /// redacted text for emails afterwards catches those and leaves the rest
    /// of the link working.
    init(_ redaction: Chunking.Detection, allowing allowlist: Allowlist = Allowlist([]), skipping skipped: Set<Kind> = []) {
        var text = redaction.redactedText
        var items: [(label: Label, original: String)] = []
        let hasAddress = redaction.items.contains { [.streetName, .city].contains($0.label) }
        for item in redaction.items {
            if allowlist.allows(item.original, as: item.label) || Self.isCode(item, hasAddress: hasAddress)
                || Kind(item.label).map(skipped.contains) == true {
                text = text.replacingOccurrences(of: item.placeholder, with: item.original)
            } else {
                items.append((item.label, item.original))
            }
        }
        // Numbered past every email Redact found, allowed ones included, so a
        // swept email never reuses a placeholder already in the text.
        let emails = redaction.items.count { $0.label == .email }
        let swept = skipped.contains(.email)
            ? (text: text, emails: [])
            : Self.sweepEmails(in: text, numberingFrom: emails + 1, allowing: allowlist)
        items += swept.emails.map { (.email, $0) }
        self.init(items: items, redactedText: swept.text)
    }

    /// A short number Redact reads as a postal code or phone number, which is
    /// far more often a one-time code, an order, or a build number. Pasting a
    /// placeholder in place of a 2FA code breaks the login.
    private static func isCode(_ item: Chunking.Detection.Item, hasAddress: Bool) -> Bool {
        switch item.label {
        case .zipCode: !hasAddress
        case .phone: item.original.count(where: \.isNumber) < 8
        default: false
        }
    }

    /// Replaces each email left in `text`, written with `@` or as `%40` the
    /// way URLs carry it, with the next `[EMAIL_n]` placeholder.
    static func sweepEmails(
        in text: String,
        numberingFrom first: Int,
        allowing allowlist: Allowlist = Allowlist([])
    ) -> (text: String, emails: [String]) {
        let pattern = /[A-Za-z0-9._%+\-]+(?:@|%40)[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}/
        var emails: [String] = []
        let swept = text.replacing(pattern) { match in
            let raw = String(match.output)
            let email = raw.replacingOccurrences(of: "%40", with: "@")
            guard !allowlist.allows(email, as: .email) else { return raw }
            emails.append(email)
            return "[EMAIL_\(first + emails.count - 1)]"
        }
        return (swept, emails)
    }

    /// A name or an address arrives as several spans. Counting the most
    /// frequent part gets close to the number a person would count: two
    /// people are two surnames, even when only one has a given name.
    private static func count(_ items: [(label: Label, original: String)], as kind: Kind) -> Int {
        switch kind {
        case .name, .address:
            Dictionary(grouping: items, by: \.label).values.map(\.count).max() ?? 0
        default:
            items.count
        }
    }

    /// `anna@example.hu` becomes `a•••@example.hu`, a card number keeps its
    /// last four digits, anything else keeps its first character.
    static func mask(_ value: String) -> String {
        if let at = value.firstIndex(of: "@"), at != value.startIndex {
            return "\(value[value.startIndex])•••\(value[at...])"
        }
        let digits = value.filter(\.isNumber)
        if digits.count >= 8 {
            return "•••• \(digits.suffix(4))"
        }
        guard let first = value.first else { return value }
        return "\(first)•••"
    }
}
