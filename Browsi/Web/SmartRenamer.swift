import Foundation
import FoundationModels
import PDFKit
import UniformTypeIdentifiers

/// Structured answer from the on-device model.
@Generable(description: "A file name suggestion for a downloaded file")
nonisolated struct SmartFileName {
    @Guide(description: "true unless the original name is already friendly, human-readable text (words separated by spaces, normal capitalisation, no technical noise). Rename when it is unclear (random IDs, hashes, bare timestamps, generic words like 'download' or 'file') OR technical/unfriendly: underscores or dashes as word separators, all lowercase, build numbers, architecture or platform tags (x64, arm64, universal, darwin, mac), URL encoding like %20, or 'copy'/'(1)' suffixes.")
    var shouldRename: Bool

    @Guide(description: "A friendly, human-readable file name without the extension, like a person would name it: words separated by spaces, Title Case for names and products. 1 to 8 words. Keep meaningful identifiers such as product names, the main version number (e.g. 0.1.105), invoice numbers or dates (YYYY-MM-DD); drop build numbers, architecture/platform tags, hashes and noise. No slashes, colons, underscores or emoji.")
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
    "Swift Concurrency Cheat Sheet". Turn technical names into friendly ones, for example \
    "winfer_0.1.105-75_x64.dmg" → "Winfer 0.1.105", "annual-report-final_v2 (1).pdf" → "Annual Report Final v2", \
    "IMG_20261003_141522.jpg" → "Photo 2026-10-03". Keep meaningful identifiers from the original name and copy product and \
    company names exactly as they are spelled in the input. \
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
    static func suggestFileName(for context: DownloadContext, force: Bool = false) async -> String? {
        guard status == .available else { return nil }
        // An already friendly name is left alone unless the user explicitly asked.
        if !force, looksFriendly(context.originalName) { return nil }
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: prompt(for: context), generating: SmartFileName.self,
                                                      options: GenerationOptions(temperature: 0.2))
            let answer = response.content
            guard answer.shouldRename || force else { return nil }
            // Never let the model misspell the product/brand the file is named after.
            let suggestion = keepsLeadingName(answer.name, original: context.originalName)
                ? answer.name : tidy(stem(of: context.originalName))
            return finalName(suggested: suggestion, original: context.originalName)
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
        let ext = fullExtension(original)
        var stem = suggested
        if !ext.isEmpty, stem.lowercased().hasSuffix("." + ext.lowercased()) {
            stem = String(stem.dropLast(ext.count + 1))
        }
        guard let clean = sanitize(stem) else { return nil }
        let result = ext.isEmpty ? clean : "\(clean).\(ext)"
        return result == original ? nil : result
    }

    nonisolated static let compoundExtensions = ["tar.gz", "tar.bz2", "tar.xz", "tar.zst", "tar.lz", "user.js"]

    /// Extension including compound ones like `tar.gz` (case preserved).
    nonisolated static func fullExtension(_ name: String) -> String {
        let lower = name.lowercased()
        if let c = compoundExtensions.first(where: { lower.hasSuffix("." + $0) }) {
            return String(name.suffix(c.count))
        }
        return (name as NSString).pathExtension
    }

    nonisolated static func stem(of name: String) -> String {
        let ext = fullExtension(name)
        return ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
    }

    /// Already human-friendly: has spaces, no technical separators/encoding/copy suffixes.
    nonisolated static func looksFriendly(_ name: String) -> Bool {
        let s = stem(of: name)
        guard s.contains(" "), !s.contains("_"), !s.contains("%"),
              s.range(of: #"\(\d+\)$|\bcopy$"#, options: [.regularExpression, .caseInsensitive]) == nil,
              s != s.lowercased() else { return false }
        return true
    }

    nonisolated static let genericWords: Set<String> = [
        "img", "image", "photo", "pic", "screenshot", "screen", "file", "download", "document", "doc",
        "scan", "untitled", "new", "copy", "final", "draft", "export", "report", "invoice", "data", "video", "audio",
    ]

    /// The original's leading word (usually the product/brand, e.g. "ripgrep", "Figma") must survive.
    nonisolated static func keepsLeadingName(_ suggestion: String, original: String) -> Bool {
        guard let first = stem(of: original).split(whereSeparator: { !$0.isLetter }).first,
              first.count >= 4, !genericWords.contains(first.lowercased()) else { return true }
        return suggestion.localizedCaseInsensitiveContains(first)
    }

    /// Deterministic fallback: separators to spaces, drop arch/platform/build noise, capitalise.
    nonisolated static func tidy(_ stem: String) -> String {
        let noise: Set<String> = ["x64", "x86", "x86_64", "amd64", "arm64", "aarch64", "universal", "apple",
                                  "darwin", "macos", "mac", "osx", "linux", "win", "windows", "gnu", "musl"]
        let decoded = stem.removingPercentEncoding ?? stem
        let words = decoded.replacing(/[_\-+]+/, with: " ").split(separator: " ")
            .filter { !noise.contains($0.lowercased()) }
            .map { w -> String in
                guard let f = w.first, f.isLowercase, w.allSatisfy({ $0.isLetter }) else { return String(w) }
                return f.uppercased() + w.dropFirst()
            }
        return words.joined(separator: " ")
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
