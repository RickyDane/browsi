import AppKit
import FoundationModels
import Observation
import WebKit

/// Pure helpers for question-based find (unit tested).
nonisolated enum PageFind {
    /// Looks like a question rather than words to find literally.
    static func looksLikeQuestion(_ q: String) -> Bool {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.hasSuffix("?") { return true }
        let starters: [String] = ["what", "where", "when", "who", "why", "how", "which", "is ", "are ", "does", "do ", "can ",
                        "was", "were", "will", "should", "did", "wo ", "was ", "wann", "wie ", "warum", "gibt es"]
        return t.split(separator: " ").count >= 3 && starters.contains { t.hasPrefix($0) }
    }

    /// Passages sharing the most words with the question (stop words ignored), best first.
    static func keywordHits(_ passages: [PagePassage], question: String, limit: Int = 4) -> [PagePassage] {
        let stop: Set<String> = ["the", "and", "for", "are", "was", "what", "where", "when", "who", "why", "how",
                                 "does", "did", "this", "that", "with", "they", "them", "there", "about", "page",
                                 "mention", "mentions", "say", "says", "any", "which", "der", "die", "das", "und"]
        let terms = Set(PageText.words(question).filter { $0.count >= 3 && !stop.contains($0) })
        guard !terms.isEmpty else { return [] }
        var scored: [(passage: PagePassage, score: Int)] = []
        for p in passages {
            let ws = PageText.words(p.text)
            let distinct = Set(ws).intersection(terms).count
            let total = ws.filter { terms.contains($0) }.count
            if distinct > 0 { scored.append((p, distinct * 10 + total)) }
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.passage.number < $1.passage.number }
        return scored.prefix(limit).map(\.passage)
    }

    /// Keeps the model's passage numbers that exist, without duplicates, in its order.
    static func validHits(_ numbers: [Int], in passages: [PagePassage], limit: Int = 4) -> [PagePassage] {
        var seen = Set<Int>()
        return numbers.compactMap { n in
            guard seen.insert(n).inserted else { return nil }
            return passages.first { $0.number == n }
        }.prefix(limit).map { $0 }
    }
}

@Generable(description: "Where on a web page a question is answered")
nonisolated struct FindAnswer {
    @Guide(description: "A direct answer in one short sentence (at most 25 words), in the language of the question. Empty if the passages don't answer it.")
    var answer: String
    @Guide(description: "Numbers of the passages that answer the question, most relevant first. Empty if none do.", .maximumCount(4))
    var passages: [Int]
}

/// The find bar's state: literal find (⌘F) and "ask" find (⌘⇧F) that highlights the passages answering a question.
@Observable
final class FindInPage {
    enum Mode: Equatable { case text, ask }
    enum AskPhase: Equatable { case idle, reading, thinking, answered, failed(String) }

    var visible = false
    var mode: Mode = .text
    var query = ""
    var focusRequest = 0
    /// Literal matches on the page (nil while counting or for an empty query).
    var matchCount: Int?
    var currentMatch = 0

    var askPhase: AskPhase = .idle
    var answer = ""
    var hits: [PagePassage] = []
    var hitIndex = 0
    /// The question that `answer`/`hits` belong to.
    private(set) var askedQuestion = ""

    @ObservationIgnored private weak var tab: Tab?
    @ObservationIgnored private var passagesURL: URL?
    @ObservationIgnored private var passages: [PagePassage] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var countTask: Task<Void, Never>?
    @ObservationIgnored var tint: NSColor = .controlAccentColor

    static let instructions = """
    You help someone find where a web page answers their question. You get the page's numbered passages. \
    Pick the passages that actually answer the question and give a one-sentence answer using only them. \
    If nothing answers it, return an empty answer and no passages. Never guess.
    """

    func open(_ mode: Mode, tab: Tab?) {
        if self.tab !== tab { reset() }
        self.tab = tab
        if self.mode != mode { self.mode = mode; clearResults() }
        visible = true
        focusRequest += 1
        if mode == .text, !query.isEmpty { search() }
    }

    func close() {
        task?.cancel(); countTask?.cancel()
        if let webView = tab?.controller?.webView { PageScripts.clearHighlight(in: webView) }
        visible = false
        clearResults()
    }

    /// The tab navigated or changed: drop everything tied to the old page.
    func pageChanged(_ tab: Tab?) {
        guard visible else { return }
        if tab !== self.tab { close(); return }
        passages = []
        passagesURL = nil
        clearResults()
        if mode == .text, !query.isEmpty { search() }
    }

    private func reset() {
        query = ""
        passages = []
        passagesURL = nil
        clearResults()
    }

    private func clearResults() {
        task?.cancel()
        matchCount = nil
        currentMatch = 0
        askPhase = .idle
        answer = ""
        hits = []
        hitIndex = 0
        askedQuestion = ""
    }

    // MARK: Literal find

    func queryChanged() {
        if mode == .ask {
            if query != askedQuestion, askPhase != .reading, askPhase != .thinking { askPhase = .idle }
            return
        }
        currentMatch = 0
        search()
    }

    private func search() {
        guard let webView = tab?.controller?.webView else { return }
        let q = query
        countTask?.cancel()
        guard !q.isEmpty else {
            matchCount = nil
            PageScripts.clearHighlight(in: webView)
            return
        }
        countTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            let n = await PageScripts.countMatches(q, in: webView)
            guard !Task.isCancelled, self.query == q else { return }
            self.matchCount = n
            self.currentMatch = 0
            if n > 0 { await self.step(forward: true) }
        }
    }

    func next(forward: Bool = true) {
        switch mode {
        case .text:
            Task { await step(forward: forward) }
        case .ask:
            guard !hits.isEmpty else { return }
            hitIndex = (hitIndex + (forward ? 1 : -1) + hits.count) % hits.count
            revealHit()
        }
    }

    private func step(forward: Bool) async {
        guard let webView = tab?.controller?.webView, !query.isEmpty, let count = matchCount, count > 0 else { return }
        let config = WKFindConfiguration()
        config.backwards = !forward
        config.caseSensitive = false
        config.wraps = true
        let result = try? await webView.find(query, configuration: config)
        guard result?.matchFound == true else { return }
        currentMatch = currentMatch == 0 ? 1 : ((currentMatch - 1 + (forward ? 1 : -1) + count) % count) + 1
    }

    // MARK: Ask

    /// Answers `query` from the page's text and highlights the passages that answer it.
    /// Works without Apple Intelligence too, by keyword relevance.
    func ask() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let tab else { return }
        mode = .ask
        task?.cancel()
        askedQuestion = q
        answer = ""
        hits = []
        hitIndex = 0
        askPhase = .reading
        task = Task { [weak self] in
            guard let self else { return }
            if self.passagesURL != tab.url || self.passages.isEmpty {
                let text = await PageScripts.mainText(of: tab) ?? ""
                guard !Task.isCancelled else { return }
                self.passages = PageText.passages(from: text, target: 300, maxPassageLength: 700)
                self.passagesURL = tab.url
            }
            guard !self.passages.isEmpty else {
                self.askPhase = .failed("This page has no text to search.")
                return
            }
            if SmartSearch.isAvailable {
                self.askPhase = .thinking
                await self.askModel(q)
            } else {
                self.hits = PageFind.keywordHits(self.passages, question: q)
            }
            guard !Task.isCancelled else { return }
            if case .failed = self.askPhase { return }
            if self.hits.isEmpty, self.answer.isEmpty {
                self.askPhase = .failed("Couldn’t find an answer on this page.")
                return
            }
            self.askPhase = .answered
            self.revealHit()
        }
    }

    private func askModel(_ q: String) async {
        var budget = 4000
        while true {
            let picked = PageText.select(passages, budget: budget, question: q)
            let session = LanguageModelSession(model: PageAssistant.model(), instructions: Self.instructions)
            let prompt = "Passages:\n\(PageText.prompt(picked))\n\nQuestion: \(q)"
            do {
                let r = try await session.respond(to: prompt, generating: FindAnswer.self,
                                                  options: GenerationOptions(temperature: 0.1))
                answer = r.content.answer.trimmingCharacters(in: .whitespacesAndNewlines)
                hits = PageFind.validHits(r.content.passages, in: picked)
                if hits.isEmpty { hits = PageFind.keywordHits(passages, question: q + " " + answer) }
                return
            } catch LanguageModelSession.GenerationError.exceededContextWindowSize where budget > 1500 {
                budget /= 2
            } catch is CancellationError {
                return
            } catch {
                // Fall back to plain keyword relevance rather than failing outright.
                hits = PageFind.keywordHits(passages, question: q)
                if hits.isEmpty { askPhase = .failed(PageAssistant.describe(error)) }
                return
            }
        }
    }

    private func revealHit() {
        guard hits.indices.contains(hitIndex), let webView = tab?.controller?.webView else { return }
        let snippet = PageText.findSnippet(hits[hitIndex].text)
        let tint = tint
        Task { await PageScripts.highlight(snippet, in: webView, tint: tint) }
    }
}
