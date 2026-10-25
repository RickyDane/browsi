import Foundation
import FoundationModels
import Observation
import WebKit

/// A numbered piece of the page's text the assistant can cite, like [3].
nonisolated struct PagePassage: Equatable, Sendable {
    var number: Int
    var text: String
}

/// Pure text handling for the page assistant (unit tested).
nonisolated enum PageText {
    /// Splits the page's visible text into passages of roughly `target` characters, on line boundaries.
    static func passages(from text: String, target: Int = 420, maxPassageLength: Int = 900) -> [PagePassage] {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { $0.count >= 2 }
        var out: [String] = []
        var current = ""
        for line in lines {
            var line = line
            if line.count > maxPassageLength { line = SmartTitler.clip(line, to: maxPassageLength) }
            if !current.isEmpty, current.count + line.count > target {
                out.append(current)
                current = ""
            }
            current += current.isEmpty ? line : "\n" + line
        }
        if !current.isEmpty { out.append(current) }
        // Navigation crumbs and button labels: drop tiny passages that are mostly very short lines.
        let meaningful = out.filter { $0.count >= 40 || $0.contains(where: { ".!?:".contains($0) }) }
        return meaningful.enumerated().map { PagePassage(number: $0.offset + 1, text: $0.element) }
    }

    /// Picks passages in page order until `budget` characters are used.
    /// With a question, the most relevant passages are preferred (the page's opening is always kept).
    static func select(_ passages: [PagePassage], budget: Int, question: String? = nil) -> [PagePassage] {
        guard passages.reduce(0, { $0 + $1.text.count }) > budget else { return passages }
        var ranked = passages
        if let question {
            let scores = relevance(passages, question: question)
            let opening = Array(passages.prefix(1))
            let rest = passages.dropFirst(1).sorted {
                let a = scores[$0.number] ?? 0, b = scores[$1.number] ?? 0
                return a != b ? a > b : $0.number < $1.number
            }
            ranked = opening + rest
        }
        var used = 0
        var picked: [PagePassage] = []
        for p in ranked where used + p.text.count <= budget {
            picked.append(p)
            used += p.text.count
        }
        return picked.sorted { $0.number < $1.number }
    }

    /// How well each passage matches the question (passage number → score; 0 or missing = no match).
    /// Stop words are ignored, words are lightly stemmed ("launched" → "launch"), each term counts once per
    /// passage and is weighted by how rare it is on the page, so "primary mirror" beats passages full of "the".
    /// Questions about a time or an amount also favour passages with dates or numbers.
    static func relevance(_ passages: [PagePassage], question: String) -> [Int: Double] {
        let qWords = words(question)
        let terms = Set(qWords.filter { $0.count >= 3 && !stopWords.contains($0) }.map(stem))
        let wantsDate = qWords.contains { ["when", "year", "date", "wann", "jahr", "datum"].contains($0) }
        let wantsAmount = zip(qWords, qWords.dropFirst()).contains { a, b in
            ["how", "wie"].contains(a) && ["big", "large", "many", "much", "long", "tall", "far", "old", "heavy",
                                            "fast", "high", "wide", "deep", "small", "groß", "viele", "viel", "lang",
                                            "hoch", "alt", "weit", "schwer", "schnell"].contains(b)
        } || qWords.contains { ["size", "cost", "price", "weight", "diameter", "height", "length", "distance",
                                "größe", "kosten", "preis", "gewicht"].contains($0) }
        guard !terms.isEmpty || wantsDate || wantsAmount else { return [:] }
        let stems = passages.map { Set(words($0.text).map(stem)) }
        let n = Double(passages.count)
        var idf: [String: Double] = [:]
        for t in terms {
            let df = Double(stems.filter { $0.contains(t) }.count)
            idf[t] = log((n + 1) / (df + 0.5))
        }
        var scores: [Int: Double] = [:]
        for (p, set) in zip(passages, stems) {
            var score = terms.reduce(0.0) { $0 + (set.contains($1) ? max(idf[$1] ?? 0, 0.1) : 0) }
            if score > 0 || terms.isEmpty {
                if wantsDate, p.text.contains(/\b(1[5-9]|20)\d{2}\b/) { score += 0.8 }
                if wantsAmount, p.text.contains(/\d/) { score += 0.5 }
            }
            if score > 0 { scores[p.number] = score }
        }
        return scores
    }

    /// Light English/German suffix stripping, enough to match "launched" with "launch" or "mirrors" with "mirror".
    static func stem(_ w: String) -> String {
        guard w.count > 4 else { return w }
        for suffix in ["ingly", "edly", "ing", "ied", "ies", "ed", "es", "ly", "en", "er", "s"] where w.hasSuffix(suffix) {
            let base = String(w.dropLast(suffix.count))
            if base.count >= 4 { return suffix == "ies" || suffix == "ied" ? base + "y" : base }
        }
        return w
    }

    static let stopWords: Set<String> = [
        "the", "and", "for", "are", "was", "were", "what", "where", "when", "who", "whom", "why", "how", "does",
        "did", "this", "that", "these", "those", "with", "they", "them", "their", "there", "about", "page", "from",
        "into", "has", "have", "had", "its", "it's", "you", "your", "can", "could", "would", "should", "will",
        "mention", "mentions", "mentioned", "say", "says", "said", "any", "which", "tell", "explain", "please",
        "der", "die", "das", "und", "ist", "sind", "wer", "wie", "wann", "warum", "wo", "welche", "welcher",
        "ein", "eine", "einen", "dem", "den", "des", "mit", "von", "für", "auf", "über", "seite",
    ]

    static func words(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    static func prompt(_ passages: [PagePassage]) -> String {
        passages.map { "[\($0.number)] \($0.text)" }.joined(separator: "\n\n")
    }

    /// "[2]" → a `browsi-cite:2` link; numbers that aren't passages are dropped.
    static func linkCitations(_ text: String, valid: Set<Int>) -> String {
        text.replacing(/\[(\d{1,3})(?:,\s*(\d{1,3}))*\](?!\()/) { m in
            let numbers = m.0.dropFirst().dropLast().split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .filter { valid.contains($0) }
            return numbers.map { "[\\[\($0)\\]](browsi-cite:\($0))" }.joined()
        }
    }

    /// Model Markdown list lines ("- ", "* ", "1. ") as bullets, since inline Markdown has no lists.
    static func bulletize(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("- ") || l.hasPrefix("* ") { return "•  " + l.dropFirst(2) }
            return l
        }.joined(separator: "\n")
    }

    /// The text to search for on the page when a citation is clicked: the start of the passage's first line.
    static func findSnippet(_ passage: String) -> String {
        let first = passage.split(whereSeparator: \.isNewline).first.map(String.init) ?? passage
        guard first.count > 70 else { return first }
        let cut = String(first.prefix(70))
        return cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? cut
    }
}

enum PageAssistantMode: Equatable { case summary, chat }

/// Summary and Q&A about one tab's page, with Apple Intelligence's on-device model. Nothing leaves the Mac.
@Observable
final class PageAssistant {
    struct Turn: Identifiable, Equatable {
        let id = UUID()
        var question: String
        var answer = ""
        var failed: String?
        var done = false
    }

    enum Phase: Equatable { case idle, reading, summarizing, ready, failed(String) }

    var phase: Phase = .idle
    var summary = ""
    var turns: [Turn] = []
    private(set) var url: URL?
    private(set) var pageTitle = ""
    @ObservationIgnored private(set) var passages: [PagePassage] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private weak var tab: Tab?

    var isBusy: Bool {
        phase == .reading || phase == .summarizing || turns.last.map { !$0.done } == true
    }

    static let summaryBudget = 5200
    static let answerBudget = 4400

    static let summaryInstructions = """
    You summarize web pages in a browser's side panel. Use only the numbered page passages you are given. \
    Write in the language of the page. Start with one sentence (at most 30 words) saying what the page is \
    and its main point. Then an empty line, then 3 to 5 key points, each on its own line starting with "- ", \
    each at most 25 words, each ending with the number of the passage it comes from in square brackets, \
    like [2]. Use Markdown bold for the most important names or numbers. Never add facts that are not in \
    the passages.
    """

    static let answerInstructions = """
    You answer questions about the web page the user is reading, using only its numbered passages. \
    Answer directly and concisely (at most about 100 words) in the language of the question. Cite the \
    passages you used with their numbers in square brackets, like [3]. Use Markdown bold for key facts. \
    If the passages don't contain the answer, say so in one sentence and don't guess.
    """

    static func model() -> SystemLanguageModel {
        SystemLanguageModel(guardrails: .permissiveContentTransformations)
    }

    /// Reads the tab's page (and summarizes it when `summarize` is set) unless that was already done
    /// for this address. Asking for a summary of a page that was opened as a chat adds it.
    func prepare(for tab: Tab, summarize: Bool, force: Bool = false) {
        if !force, tab.url == url, phase != .idle {
            if summarize, summary.isEmpty, phase == .ready, !isBusy {
                task = Task { [weak self] in await self?.summarize() }
            }
            return
        }
        reset()
        self.tab = tab
        url = tab.url
        pageTitle = tab.displayTitle
        guard SmartRenamer.status == .available else {
            if case .unavailable(let why) = SmartRenamer.status { phase = .failed(why) }
            return
        }
        phase = .reading
        task = Task { [weak self] in
            guard let self else { return }
            // Let the page finish loading (up to ~8 s) so the text is complete.
            for _ in 0..<40 where tab.isLoading { try? await Task.sleep(for: .milliseconds(200)) }
            guard !Task.isCancelled else { return }
            let text = await Self.extractText(from: tab)
            guard !Task.isCancelled else { return }
            self.passages = PageText.passages(from: text ?? "")
            self.pageTitle = tab.displayTitle
            guard !self.passages.isEmpty else {
                self.phase = .failed("This page has no text to read.")
                return
            }
            if summarize { await self.summarize() } else { self.phase = .ready }
        }
    }

    private func summarize(budget: Int = summaryBudget) async {
        phase = .summarizing
        let picked = PageText.select(passages, budget: budget)
        let session = LanguageModelSession(model: Self.model(), instructions: Self.summaryInstructions)
        let prompt = "Page title: \(pageTitle.prefix(200))\n\nPassages:\n\(PageText.prompt(picked))\n\nSummarize this page."
        do {
            for try await snap in session.streamResponse(to: prompt, options: GenerationOptions(temperature: 0.2)) {
                if Task.isCancelled { return }
                summary = snap.content
            }
            phase = .ready
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize where budget > 2000 {
            await summarize(budget: budget / 2)
        } catch is CancellationError {
        } catch {
            phase = summary.isEmpty ? .failed(Self.describe(error)) : .ready
        }
    }

    /// Answers a follow-up question about the page. Earlier answers are included briefly for context.
    func ask(_ question: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !passages.isEmpty, !isBusy else { return }
        let turn = Turn(question: q)
        turns.append(turn)
        let id = turn.id
        let history = turns.dropLast().suffix(2)
            .map { "Q: \($0.question)\nA: \(String($0.answer.prefix(400)))" }.joined(separator: "\n\n")
        task = Task { [weak self] in
            guard let self else { return }
            var budget = Self.answerBudget
            while true {
                let picked = PageText.select(self.passages, budget: budget, question: q)
                let session = LanguageModelSession(model: Self.model(), instructions: Self.answerInstructions)
                var prompt = "Page title: \(self.pageTitle.prefix(200))\n\nPassages:\n\(PageText.prompt(picked))\n\n"
                if !history.isEmpty { prompt += "Earlier in this conversation:\n\(history)\n\n" }
                prompt += "Question: \(q)"
                do {
                    for try await snap in session.streamResponse(to: prompt, options: GenerationOptions(temperature: 0.3)) {
                        if Task.isCancelled { return }
                        self.update(id) { $0.answer = snap.content }
                    }
                    self.update(id) { $0.done = true }
                    return
                } catch LanguageModelSession.GenerationError.exceededContextWindowSize where budget > 1500 {
                    budget /= 2
                } catch is CancellationError {
                    return
                } catch {
                    self.update(id) { $0.failed = Self.describe(error); $0.done = true }
                    return
                }
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout Turn) -> Void) {
        guard let i = turns.firstIndex(where: { $0.id == id }) else { return }
        change(&turns[i])
    }

    func reset() {
        task?.cancel()
        task = nil
        phase = .idle
        summary = ""
        turns = []
        passages = []
    }

    /// Scrolls the page to a cited passage and selects its opening words.
    func reveal(_ number: Int) {
        guard let p = passages.first(where: { $0.number == number }), let webView = tab?.controller?.webView else { return }
        let js = """
        const sel = window.getSelection(); sel.removeAllRanges();
        if (!window.find(snippet, false, false, true)) return false;
        const r = sel.rangeCount ? sel.getRangeAt(0) : null;
        const el = r && (r.startContainer.nodeType === 1 ? r.startContainer : r.startContainer.parentElement);
        if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
        return true;
        """
        Task {
            _ = try? await webView.callAsyncJavaScript(js, arguments: ["snippet": PageText.findSnippet(p.text)],
                                                       contentWorld: .defaultClient)
        }
    }

    /// The page's visible text (main content when the page marks it), read in an isolated content world.
    static func extractText(from tab: Tab) async -> String? { await PageScripts.mainText(of: tab) }

    static func describe(_ error: Error) -> String {
        switch error as? LanguageModelSession.GenerationError {
        case .exceededContextWindowSize: "This page is too long for the on-device model."
        case .guardrailViolation, .refusal: "Apple Intelligence can’t help with this page."
        case .unsupportedLanguageOrLocale: "This page’s language isn’t supported by Apple Intelligence yet."
        case .rateLimited: "Apple Intelligence is busy. Try again in a moment."
        default: "Apple Intelligence couldn’t finish that."
        }
    }
}
