import Foundation
import FoundationModels

/// Short sidebar titles for long or SEO-stuffed page titles.
/// A deterministic clean-up runs instantly; Apple Intelligence's on-device model refines it when available.
nonisolated enum SmartTitler {
    /// Separators sites use between the page and the site name ("Page | Site", "Page - Site").
    static let separators = [" | ", " – ", " — ", " - ", " · ", " • ", " :: ", " » "]
    /// Titles at most this long are left alone unless they carry a site-name segment.
    static let shortLength = 26

    /// Only rewrite titles that are long or carry separators; short, clean ones stay as they are.
    static func needsShortening(_ title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        return t.count > shortLength || separators.contains { t.contains($0) }
    }

    /// The leading notification counter some sites put in the title, like "(3) ".
    static func counterPrefix(_ title: String) -> String? {
        title.firstMatch(of: /^\(\d+\+?\)\s*/).map { String($0.0) }
    }

    /// Name of the site from its host: "www.developer.apple.com" → "apple", "github.com" → "github".
    static func siteName(of host: String?) -> String? {
        guard let host else { return nil }
        var parts = host.lowercased().split(separator: ".").map(String.init)
        if parts.first == "www" || parts.first == "m" { parts.removeFirst() }
        guard parts.count >= 2 else { return parts.first }
        // Handle two-part public suffixes like co.uk / com.au.
        let secondLevel: Set<String> = ["co", "com", "org", "net", "ac", "gov", "edu"]
        if parts.count >= 3, secondLevel.contains(parts[parts.count - 2]) { return parts[parts.count - 3] }
        return parts[parts.count - 2]
    }

    /// Splits on site separators, drops segments naming the site, keeps the most specific part.
    static func heuristic(_ title: String, host: String?) -> String {
        let counter = counterPrefix(title) ?? ""
        var body = String(title.dropFirst(counter.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        var segments = [body]
        for sep in separators {
            segments = segments.flatMap { $0.components(separatedBy: sep) }
        }
        segments = segments.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if segments.count > 1 {
            let site = siteName(of: host)
            let squashed = { (s: String) in s.lowercased().filter { $0.isLetter || $0.isNumber } }
            let kept = segments.filter { seg in
                guard let site, site.count >= 3 else { return true }
                return !squashed(seg).contains(site)
            }
            // Keep the first remaining segment: sites put the specific page first.
            body = (kept.first ?? segments[0])
        }
        return counter + clip(body, to: 42)
    }

    /// Cuts at a word boundary and adds an ellipsis.
    static func clip(_ s: String, to max: Int) -> String {
        guard s.count > max else { return s }
        var cut = String(s.prefix(max))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > max / 2 {
            cut = String(cut[..<space])
        }
        return cut.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—|")) + "…"
    }

    /// Accepts a model suggestion only if it is short, non-empty and actually shorter.
    static func validate(_ raw: String, original: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’`.*"))
        s = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        s = s.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard !s.isEmpty, s.count <= 40, s.count < original.count else { return nil }
        return s
    }

    static let instructions = """
    You shorten web page titles for a browser's tab sidebar. Reply with only the new title: 2 to 5 words that say what the page is \
    about, in the language of the title. Drop the website name, slogans, SEO filler and separators. Keep \
    specific names, products, people, numbers and versions exactly as written. Examples: \
    "Swift Concurrency | Apple Developer Documentation" → "Swift Concurrency"; \
    "Amazon.com: Logitech MX Master 3S Wireless Performance Mouse, Ergonomic Design : Electronics" → "Logitech MX Master 3S"; \
    "How to Bake Sourdough Bread at Home (Step-by-Step Guide) - The Perfect Loaf" → "Baking Sourdough Bread"; \
    "Pull requests · apple/swift · GitHub" → "apple/swift Pull Requests". Never invent facts.
    """
}

/// Computes and caches smart titles; model calls run one at a time.
final class SmartTitleService {
    static let shared = SmartTitleService()

    private var cache: [String: String] = [:]
    private var pending: [UUID: Task<Void, Never>] = [:]
    private var tail: Task<Void, Never>?

    private func key(_ title: String, _ host: String?) -> String { (host ?? "") + "\n" + title }

    /// Updates `tab.smartTitle` for its current title (call when the title or the setting changes).
    func refresh(_ tab: Tab) {
        pending[tab.id]?.cancel()
        pending[tab.id] = nil
        let title = tab.title
        let host = tab.url?.host()
        guard Preferences.shared.smartTabTitles, !tab.isHome, SmartTitler.needsShortening(title) else {
            tab.smartTitle = nil
            return
        }
        let counter = SmartTitler.counterPrefix(title) ?? ""
        let base = String(title.dropFirst(counter.count))
        let k = key(base, host)
        if let cached = cache[k] { apply(counter + cached, to: tab); return }
        let quick = SmartTitler.heuristic(base, host: host)
        apply(counter + quick, to: tab)
        guard SmartRenamer.status == .available else { return }

        // Titles change quickly while pages load; wait for them to settle, then queue one model call.
        let previous = tail
        let job = Task { [weak self, weak tab] in
            try? await Task.sleep(for: .milliseconds(900))
            await previous?.value
            guard !Task.isCancelled, let self, let tab, tab.title == title else { return }
            let refined = await Self.ask(title: base, host: host) ?? quick
            self.store(refined, for: k)
            if tab.title == title, !Task.isCancelled { self.apply(counter + refined, to: tab) }
        }
        pending[tab.id] = job
        tail = job
    }

    private func apply(_ value: String, to tab: Tab) {
        tab.smartTitle = value == tab.title ? nil : value
    }

    func forget(_ tab: Tab) {
        pending[tab.id]?.cancel()
        pending[tab.id] = nil
    }

    private func store(_ value: String, for key: String) {
        if cache.count > 600 { cache.removeAll(keepingCapacity: true) }
        cache[key] = value
    }

    private static func ask(title: String, host: String?) async -> String? {
        // Plain text with permissive guardrails: guided generation refuses some harmless news headlines.
        let session = LanguageModelSession(model: SystemLanguageModel(guardrails: .permissiveContentTransformations),
                                           instructions: SmartTitler.instructions)
        let prompt = "Website: \(host ?? "unknown")\nTitle: \(title.prefix(300))\nShort title:"
        do {
            let r = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.1))
            return SmartTitler.validate(r.content, original: title)
        } catch {
            debugLog("smart title failed: \(error)")
            return nil
        }
    }
}
