import Foundation
import FoundationModels
import PDFKit
import UniformTypeIdentifiers

/// Structured answer from the on-device model.
@Generable(description: "A file name suggestion for a downloaded file")
nonisolated struct SmartFileName {
    @Guide(description: "true if the original file name is unclear: random IDs, hashes, timestamps only, or generic words like 'download', 'file', 'document', 'image'. false if it already clearly says what the file is.")
    var shouldRename: Bool

    @Guide(description: "A concise, descriptive file name without the extension. 2 to 8 words separated by spaces. Keep meaningful identifiers such as invoice numbers, versions or dates (YYYY-MM-DD). No slashes, colons or emoji.")
    var name: String
}

/// What we know about a finished download.
nonisolated struct DownloadContext: Sendable {
    var originalName: String
    var mimeType: String?
    var sourceURL: URL?
    var pageTitle: String?
    var pageURL: URL?
    var contentSnippet: String?
}

/// Renames downloads with Apple Intelligence's on-device model (Foundation Models).
/// Nothing leaves the Mac.
enum SmartRenamer {
    nonisolated enum Status: Equatable, Sendable {
        case available
        case unavailable(String)
    }

    nonisolated static var status: Status {
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Turn on Apple Intelligence in System Settings to use smart renaming.")
        case .unavailable(.deviceNotEligible):
            return .unavailable("This Mac doesn’t support Apple Intelligence.")
        case .unavailable(.modelNotReady):
            return .unavailable("The Apple Intelligence model is still downloading.")
        case .unavailable:
            return .unavailable("Apple Intelligence is unavailable.")
        }
    }

    static let instructions = """
    You name files that a person just downloaded in their web browser. \
    Good names are short, specific and human-readable, like "Acme Invoice 8823 2026-10" or \
    "Swift Concurrency Cheat Sheet". Keep meaningful identifiers from the original name. \
    Only use facts present in the input; never invent dates, companies or numbers.
    """

    static func prompt(for c: DownloadContext) -> String {
        var lines = ["Suggest a better file name for this download.",
                     "Original file name: \(c.originalName)"]
        if let m = c.mimeType { lines.append("File type: \(m)") }
        if let u = c.sourceURL { lines.append("Downloaded from: \(u.absoluteString.prefix(300))") }
        if let t = c.pageTitle, !t.isEmpty { lines.append("Web page title: \(t.prefix(200))") }
        if let p = c.pageURL { lines.append("Web page address: \(p.absoluteString.prefix(300))") }
        if let s = c.contentSnippet, !s.isEmpty { lines.append("Beginning of the file's text:\n\(s)") }
        return lines.joined(separator: "\n")
    }

    /// Returns a new file name (with the original extension) or nil to keep the original.
    static func suggestFileName(for context: DownloadContext) async -> String? {
        guard status == .available else { return nil }
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: prompt(for: context), generating: SmartFileName.self,
                                                      options: GenerationOptions(temperature: 0.2))
            let answer = response.content
            guard answer.shouldRename else { return nil }
            return finalName(suggested: answer.name, original: context.originalName)
        } catch {
            debugLog("smart rename failed: \(error)")
            return nil
        }
    }

    // MARK: Pure helpers (unit tested)

    /// Cleans a model suggestion into a safe file-name stem.
    nonisolated static func sanitize(_ raw: String, maxLength: Int = 80) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’`."))
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\0").union(.controlCharacters).union(.newlines)
        s = s.components(separatedBy: illegal).joined(separator: " ")
        s = String(s.unicodeScalars.filter { !($0.properties.isEmojiPresentation) })
        s = s.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        if s.count > maxLength {
            s = String(s.prefix(maxLength))
            if let lastSpace = s.lastIndex(of: " ") { s = String(s[..<lastSpace]) }
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))
        return s.isEmpty ? nil : s
    }

    /// Applies the original extension; drops an extension the model may have added itself.
    nonisolated static func finalName(suggested: String, original: String) -> String? {
        let ext = (original as NSString).pathExtension
        var stem = suggested
        if !ext.isEmpty, stem.lowercased().hasSuffix("." + ext.lowercased()) {
            stem = String(stem.dropLast(ext.count + 1))
        }
        guard let clean = sanitize(stem) else { return nil }
        let result = ext.isEmpty ? clean : "\(clean).\(ext)"
        return result == original ? nil : result
    }

    /// First ~1200 characters of text for PDFs and text files (off the main thread).
    static func contentSnippet(of url: URL, mimeType: String?) async -> String? {
        await Task.detached(priority: .utility) { () -> String? in
            let type = UTType(filenameExtension: url.pathExtension) ?? mimeType.flatMap { UTType(mimeType: $0) }
            var text: String?
            if type?.conforms(to: .pdf) == true, let doc = PDFDocument(url: url) {
                text = (0..<min(2, doc.pageCount)).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
            } else if type?.conforms(to: .text) == true || type?.conforms(to: .sourceCode) == true {
                let handle = try? FileHandle(forReadingFrom: url)
                let data = try? handle?.read(upToCount: 4096)
                try? handle?.close()
                text = data.map { String(decoding: $0, as: UTF8.self) }
            }
            guard let t = text?.split(whereSeparator: \.isWhitespace).joined(separator: " "), !t.isEmpty else { return nil }
            return String(t.prefix(1200))
        }.value
    }
}
