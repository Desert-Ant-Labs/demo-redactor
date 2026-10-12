import Foundation
import NaturalLanguage
import Redact

/// Redact was trained on short strings and finds fewer names in long text,
/// so text is redacted in chunks of whole sentences and stitched back.
enum Chunking {
    /// What Redact found, before the allowlist and the email sweep.
    struct Detection: Sendable {
        struct Item: Sendable {
            let label: Label
            let original: String
            let placeholder: String
        }

        let items: [Item]
        let redactedText: String
    }

    static let chunkLength = 150
    /// A long export would take thousands of calls; past this many, chunks
    /// grow so the count stays put.
    static let maxChunks = 200

    static func detect(in text: String, using redact: Redact, options: Options) async throws -> Detection {
        var numbering = Numbering()
        var items: [Detection.Item] = []
        var redacted = ""
        for range in chunks(of: text) {
            let redaction = try await redact.redaction(of: String(text[range]), options: options)
            let renamed = numbering.rename(redaction.items)
            redacted += renamed.apply(to: redaction.redactedText)
            items += redaction.items.map {
                Detection.Item(label: $0.label, original: $0.original, placeholder: renamed.names[$0.placeholder] ?? $0.placeholder)
            }
        }
        return Detection(items: items, redactedText: redacted)
    }

    /// Ranges that cover `text` end to end, cut after a sentence where one
    /// ends within the length, and at a space where a sentence runs longer.
    static func chunks(of text: String) -> [Range<String.Index>] {
        let length = max(chunkLength, text.count / maxChunks)
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        let ends = tokenizer.tokens(for: text.startIndex..<text.endIndex).map(\.upperBound)

        var chunks: [Range<String.Index>] = []
        var start = text.startIndex
        while start < text.endIndex {
            let limit = text.index(start, offsetBy: length, limitedBy: text.endIndex) ?? text.endIndex
            let end = ends.last { $0 > start && $0 <= limit }
                ?? text[start..<limit].lastIndex(where: \.isWhitespace).map { text.index(after: $0) }
                ?? limit
            chunks.append(start..<end)
            start = end
        }
        return chunks
    }

    /// Gives each value one placeholder across chunks: Redact numbers from 1
    /// in every call, so two chunks would both say `[EMAIL_1]`.
    private struct Numbering {
        private var assigned: [String: String] = [:]
        private var counts: [Label: Int] = [:]

        mutating func rename(_ items: [Redaction.Item]) -> Renaming {
            var names: [String: String] = [:]
            for item in items {
                let key = "\(item.label.rawValue)\u{0}\(item.original)"
                if assigned[key] == nil {
                    counts[item.label, default: 0] += 1
                    assigned[key] = "[\(item.label.rawValue)_\(counts[item.label]!)]"
                }
                names[item.placeholder] = assigned[key]
            }
            return Renaming(names: names)
        }
    }

    private struct Renaming {
        let names: [String: String]

        /// One pass, so a new name is never renamed again.
        func apply(to text: String) -> String {
            text.replacing(/\[[A-Z_]+_\d+\]/) { match in
                names[String(match.output)] ?? String(match.output)
            }
        }
    }
}
