import AppKit
import PDFKit
import Vision

/// Pulls the text out of the files people most often copy into a chat:
/// text and data exports, Word and RTF documents, PDFs with a text layer, and
/// images, read with Vision.
enum TextExtraction {
    /// A scan reads the start of what was copied, so a large export is
    /// judged on its first rows.
    static let maxCharacters = 200_000
    static let maxFileBytes = 50_000_000
    static let maxFiles = 20

    private static let plainExtensions: Set<String> = [
        "txt", "text", "md", "markdown", "csv", "tsv", "json", "jsonl", "xml",
        "yaml", "yml", "log", "html", "htm", "eml", "vcf", "ics",
    ]
    private static let documentExtensions: Set<String> = ["rtf", "doc", "docx", "odt"]
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "gif", "webp"]

    static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    static func canRead(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "pdf" || [plainExtensions, documentExtensions, imageExtensions].contains { $0.contains(ext) }
    }

    static func text(of files: [URL]) async -> String {
        var text = ""
        for file in files.prefix(maxFiles) where canRead(file) && isSmallEnough(file) {
            guard text.count < maxCharacters else { break }
            if let part = await self.text(at: file) {
                text += part + "\n\n"
            }
        }
        return String(text.prefix(maxCharacters))
    }

    private static func text(at url: URL) async -> String? {
        let ext = url.pathExtension.lowercased()
        if plainExtensions.contains(ext) {
            return (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1))
        }
        if documentExtensions.contains(ext) {
            return (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string
        }
        if ext == "pdf" {
            return PDFDocument(url: url)?.string
        }
        if imageExtensions.contains(ext) {
            let lines = try? await RecognizeTextRequest().perform(on: url)
            return lines?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }
        return nil
    }

    private static func isSmallEnough(_ url: URL) -> Bool {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return size <= maxFileBytes
    }
}
