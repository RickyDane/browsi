import Foundation
import FoundationModels
import Observation

/// A web page the assistant looked at; numbered for inline citations like [2].
nonisolated struct AnswerSource: Identifiable, Equatable, Sendable {
    var number: Int
    var title: String
    var url: URL
    var id: Int { number }
}

/// Collects sources from concurrent tool calls and numbers them once.
nonisolated final class SourceCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var sources: [AnswerSource] = []
    private let onChange: @Sendable ([AnswerSource]) -> Void

    init(onChange: @escaping @Sendable ([AnswerSource]) -> Void) { self.onChange = onChange }

    /// Returns the citation number for `url`, registering it if new.
    func number(for url: URL, title: String) -> Int {
        lock.lock()
        if let existing = sources.first(where: { $0.url == url }) { lock.unlock(); return existing.number }
        let n = sources.count + 1
        sources.append(AnswerSource(number: n, title: title, url: url))
        let snapshot = sources
        lock.unlock()
        onChange(snapshot)
        return n
    }

    func url(for number: Int) -> URL? {
        lock.lock(); defer { lock.unlock() }
        return sources.first { $0.number == number }?.url
    }
}

// MARK: - Web search (DuckDuckGo HTML endpoint, no API key)

nonisolated enum WebSearch {
    struct Result: Equatable, Sendable {
        var title: String
        var url: URL
        var snippet: String
    }

    static func search(_ query: String, limit: Int = 5) async throws -> [Result] {
        var c = URLComponents(string: "https://html.duckduckgo.com/html/")!
        c.queryItems = [URLQueryItem(name: "q", value: query)]
        var request = URLRequest(url: c.url!, timeoutInterval: 10)
        request.setValue(UserAgent.safari, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.8,de;q=0.6", forHTTPHeaderField: "Accept-Language")
        let (data, _) = try await URLSession.shared.data(for: request)
        return Array(parse(String(decoding: data, as: UTF8.self)).prefix(limit))
    }

    /// Parses DuckDuckGo's HTML results page.
    static func parse(_ html: String) -> [Result] {
        let linkRe = /<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)<\/a>/
            .dotMatchesNewlines()
        let snippetRe = /<a[^>]*class="result__snippet"[^>]*>(.*?)<\/a>/.dotMatchesNewlines()
        let links = html.matches(of: linkRe)
        let snippets = html.matches(of: snippetRe).map { HTMLText.plain(String($0.1)) }
        var out: [Result] = []
        for (i, m) in links.enumerated() {
            guard let url = resolve(HTMLText.decodeEntities(String(m.1))) else { continue }
            if url.host()?.hasSuffix("duckduckgo.com") == true { continue }   // ads / internal
            out.append(Result(title: HTMLText.plain(String(m.2)), url: url,
                              snippet: i < snippets.count ? snippets[i] : ""))
        }
        return out
    }

    /// DuckDuckGo wraps targets as //duckduckgo.com/l/?uddg=<encoded>.
    static func resolve(_ href: String) -> URL? {
        let full = href.hasPrefix("//") ? "https:" + href : href
        guard let comps = URLComponents(string: full) else { return nil }
        if let target = comps.queryItems?.first(where: { $0.name == "uddg" })?.value, let url = URL(string: target) {
            return url
        }
        return comps.url?.scheme?.hasPrefix("http") == true ? comps.url : nil
    }
}

nonisolated enum HTMLText {
    static func decodeEntities(_ s: String) -> String {
        var s = s
        for (k, v) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#x27;": "'", "&#39;": "'", "&nbsp;": " "] {
            s = s.replacingOccurrences(of: k, with: v)
        }
        return s
    }

    /// Strips scripts, styles and tags; collapses whitespace.
    static func plain(_ html: String) -> String {
        var s = html.replacing(/<(script|style|noscript|svg)[^>]*>.*?<\/\1>/.dotMatchesNewlines().ignoresCase(), with: " ")
        s = s.replacing(/<[^>]+>/, with: " ")
        s = decodeEntities(s)
        return s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

// MARK: - Tools

nonisolated struct SearchWebTool: Tool {
    let name = "searchWeb"
    let description = "Searches the web. Use for facts, news, prices, people, places, how-tos or anything you are not certain about."
    let sources: SourceCollector
    let onActivity: @Sendable (String) -> Void

    @Generable
    struct Arguments {
        @Guide(description: "A concise web search query")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        onActivity("Searching the web for “\(arguments.query)”")
        let results = (try? await WebSearch.search(arguments.query)) ?? []
        guard !results.isEmpty else { return "No results." }
        return results.map { r in
            let n = sources.number(for: r.url, title: r.title)
            return "[\(n)] \(r.title) — \(r.url.host() ?? "")\n\(r.snippet.prefix(220))"
        }.joined(separator: "\n\n")
    }
}

nonisolated struct ReadPageTool: Tool {
    let name = "readWebPage"
    let description = "Reads the text of a web page from the search results, by its citation number, when snippets are not enough."
    let sources: SourceCollector
    let onActivity: @Sendable (String) -> Void

    @Generable
    struct Arguments {
        @Guide(description: "The citation number of a search result, like 1 or 2", .range(1...20))
        var number: Int
    }

    func call(arguments: Arguments) async throws -> String {
        guard let url = sources.url(for: arguments.number) else { return "Unknown source number." }
        onActivity("Reading \(url.host() ?? "page")")
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(UserAgent.safari, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return "Could not load the page." }
        let text = HTMLText.plain(String(decoding: data.prefix(400_000), as: UTF8.self))
        return "[\(arguments.number)] " + String(text.prefix(1800))
    }
}

nonisolated struct LibraryTool: Tool {
    let name = "searchMyHistory"
    let description = "Searches the user's own browsing history and bookmarks, e.g. 'that article I read about…' or 'my bookmark for…'."
    let sources: SourceCollector
    let lookup: @Sendable (String) async -> [(title: String, url: URL)]
    let onActivity: @Sendable (String) -> Void

    @Generable
    struct Arguments {
        @Guide(description: "Words to look for in titles and addresses")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        onActivity("Looking through your history")
        let hits = await lookup(arguments.query)
        guard !hits.isEmpty else { return "Nothing found in history or bookmarks." }
        return hits.prefix(6).map { h in "[\(sources.number(for: h.url, title: h.title))] \(h.title) — \(h.url.absoluteString)" }
            .joined(separator: "\n")
    }
}

// MARK: - Session

/// Drives one smart answer: streams text and reports tool activity and sources.
@Observable
final class SmartSearch {
    enum Phase: Equatable { case idle, working, done, failed(String) }

    var phase: Phase = .idle
    var activity = ""
    var answer = ""
    var sources: [AnswerSource] = []
    @ObservationIgnored private var task: Task<Void, Never>?

    nonisolated static var isAvailable: Bool { SmartRenamer.status == .available }

    static let instructions = """
    You are the search assistant of the Browsi web browser. Answer the user's question directly and \
    concisely (at most about 120 words), in the same language as the question. Use the searchWeb tool \
    for facts, current events, numbers or anything you are not sure about; use readWebPage when the \
    snippets are not enough; use searchMyHistory when the user refers to something they visited. \
    Cite sources inline with their numbers in square brackets, like [1]. Use Markdown bold for key facts. \
    Never invent sources or URLs. If the question is just a website name, say which site it is in one sentence.
    """

    func run(_ query: String, library: LibraryStore) {
        cancel()
        answer = ""
        sources = []
        activity = "Thinking"
        phase = .working
        task = Task { [weak self] in
            guard let self else { return }
            let collector = SourceCollector { list in Task { @MainActor [weak self] in self?.sources = list } }
            let activity: @Sendable (String) -> Void = { text in Task { @MainActor [weak self] in self?.activity = text } }
            let lookup: @Sendable (String) async -> [(title: String, url: URL)] = { q in
                await MainActor.run {
                    let bookmarks = library.allBookmarks().filter {
                        $0.title.localizedStandardContains(q) || $0.urlString.localizedStandardContains(q)
                    }.compactMap { b in URL(string: b.urlString).map { (b.title, $0) } }
                    let history = library.searchHistory(q, limit: 8).compactMap { h in
                        URL(string: h.urlString).map { (h.title.isEmpty ? h.host : h.title, $0) }
                    }
                    return Array((bookmarks + history).prefix(8))
                }
            }
            let session = LanguageModelSession(
                tools: [SearchWebTool(sources: collector, onActivity: activity),
                        ReadPageTool(sources: collector, onActivity: activity),
                        LibraryTool(sources: collector, lookup: lookup, onActivity: activity)],
                instructions: Self.instructions)
            do {
                let stream = session.streamResponse(to: query, options: GenerationOptions(temperature: 0.3))
                for try await snapshot in stream {
                    if Task.isCancelled { return }
                    self.answer = snapshot.content
                }
                self.phase = .done
            } catch is CancellationError {
            } catch let error as LanguageModelSession.GenerationError {
                self.phase = .failed(Self.describe(error))
            } catch {
                self.phase = .failed("Couldn’t answer that: \(error.localizedDescription)")
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase == .working { phase = .idle }
    }

    func reset() {
        cancel()
        phase = .idle
        answer = ""
        sources = []
    }

    private static func describe(_ e: LanguageModelSession.GenerationError) -> String {
        switch e {
        case .exceededContextWindowSize: "That needed more reading than the on-device model can hold. Try a more specific question."
        case .guardrailViolation: "Apple Intelligence can’t answer that one. Try searching the web instead."
        case .unsupportedLanguageOrLocale: "That language isn’t supported by Apple Intelligence yet."
        case .rateLimited: "Apple Intelligence is busy. Try again in a moment."
        default: "Apple Intelligence couldn’t answer that."
        }
    }

    /// Turns "[2]" citations into Markdown links to the sources (pure; unit tested).
    nonisolated static func linkCitations(_ text: String, sources: [AnswerSource]) -> String {
        text.replacing(/\[(\d{1,2})\](?!\()/) { m in
            guard let n = Int(m.1), let s = sources.first(where: { $0.number == n }) else { return String(m.0) }
            return "[\\[\(n)\\]](\(s.url.absoluteString))"
        }
    }
}
