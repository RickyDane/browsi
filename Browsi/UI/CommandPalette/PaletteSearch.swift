import Foundation

nonisolated enum PaletteKind: Int, Sendable, Comparable {
    case navigate, tab, bookmark, history, command, search
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var boost: Double {
        switch self {
        case .navigate: 1000
        case .tab: 15
        case .bookmark: 10
        case .history: 0
        case .command: 5
        case .search: 0
        }
    }
}

/// Pure ranking logic for the command palette (unit tested).
nonisolated enum PaletteSearch {
    /// Higher is better; nil means no match.
    /// Command subtitles are descriptions, not addresses: `subtitleIsAddress: false` skips host matching.
    static func score(query rawQuery: String, title: String, subtitle: String, subtitleIsAddress: Bool = true) -> Double? {
        let q = rawQuery.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return 1 }
        let t = title.lowercased()
        let s = subtitle.lowercased()
        let host = s.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")

        if t == q { return 120 }
        if subtitleIsAddress, host.hasPrefix(q) { return 100 - Double(host.count - q.count) * 0.1 }
        if t.hasPrefix(q) { return 95 - Double(t.count - q.count) * 0.1 }
        if t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(q) }) { return 80 }
        if t.contains(q) { return 60 }
        if subtitleIsAddress, host.contains(q) { return 50 }
        if let f = subsequenceScore(q, t) { return 20 + f }
        return nil
    }

    /// Fuzzy subsequence match; rewards consecutive runs. Returns 0…20.
    static func subsequenceScore(_ q: String, _ text: String) -> Double? {
        var ti = text.startIndex
        var run = 0, best = 0, matched = 0
        for qc in q {
            var found = false
            while ti < text.endIndex {
                let c = text[ti]
                ti = text.index(after: ti)
                if c == qc { run += 1; best = max(best, run); matched += 1; found = true; break }
                run = 0
            }
            if !found { return nil }
        }
        return min(20, Double(best) * 3 + Double(matched) / Double(max(1, text.count)) * 5)
    }

    struct Candidate<ID: Hashable & Sendable>: Sendable {
        var id: ID
        var kind: PaletteKind
        var title: String
        var subtitle: String
        var extraBoost: Double = 0
        /// Extra words a command answers to, e.g. "event meeting date" for "Add Event to Calendar".
        var keywords: String = ""
    }

    /// Natural phrasing like "add this to my calendar": every meaningful query word starts a word
    /// of the title or keywords.
    static func keywordScore(query: String, title: String, keywords: String) -> Double? {
        guard !keywords.isEmpty else { return nil }
        let stop: Set<String> = ["this", "that", "the", "these", "those", "page", "for", "with", "and", "into", "from", "all"]
        func split(_ s: String) -> [Substring] { s.lowercased().split { !$0.isLetter && !$0.isNumber } }
        let terms = split(query).filter { $0.count >= 3 && !stop.contains(String($0)) }
        guard !terms.isEmpty else { return nil }
        let hay = split(title + " " + keywords)
        return terms.allSatisfy { t in hay.contains { $0.hasPrefix(t) } } ? 70 : nil
    }

    static func rank<ID>(_ candidates: [Candidate<ID>], query: String, limit: Int = 9) -> [ID] {
        var seen = Set<String>()
        return candidates
            .compactMap { c -> (Candidate<ID>, Double)? in
                let direct = score(query: query, title: c.title, subtitle: c.subtitle, subtitleIsAddress: c.kind != .command)
                guard let s = [direct, keywordScore(query: query, title: c.title, keywords: c.keywords)].compactMap({ $0 }).max()
                else { return nil }
                return (c, s + c.kind.boost + c.extraBoost)
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.kind < $1.0.kind }
            .filter { c, _ in
                // De-duplicate the same URL appearing as tab/bookmark/history.
                guard c.kind != .command, !c.subtitle.isEmpty else { return true }
                return seen.insert(c.subtitle).inserted
            }
            .prefix(limit)
            .map(\.0.id)
    }
}
