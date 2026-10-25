import Testing
import Foundation
@testable import Browsi

struct PaletteSearchTests {
    typealias C = PaletteSearch.Candidate<String>

    @Test func hostPrefixBeatsTitleContains() {
        let ranked = PaletteSearch.rank([
            C(id: "a", kind: .history, title: "A page mentioning github", subtitle: "https://blog.example.com"),
            C(id: "b", kind: .history, title: "Repositories", subtitle: "https://github.com/explore"),
        ], query: "git")
        #expect(ranked == ["b", "a"])
    }

    @Test func openTabsBoostedOverHistory() {
        let ranked = PaletteSearch.rank([
            C(id: "h", kind: .history, title: "Swift Forums", subtitle: "https://forums.swift.org"),
            C(id: "t", kind: .tab, title: "Swift Forums", subtitle: "https://forums.swift.org/latest"),
        ], query: "swift")
        #expect(ranked.first == "t")
    }

    @Test func fuzzySubsequenceMatches() {
        #expect(PaletteSearch.score(query: "tglsb", title: "Toggle Sidebar", subtitle: "") != nil)
        #expect(PaletteSearch.score(query: "zzz", title: "Toggle Sidebar", subtitle: "") == nil)
    }

    @Test func deduplicatesSameURL() {
        let ranked = PaletteSearch.rank([
            C(id: "t", kind: .tab, title: "Apple", subtitle: "https://apple.com/"),
            C(id: "h", kind: .history, title: "Apple", subtitle: "https://apple.com/"),
        ], query: "apple")
        #expect(ranked == ["t"])
    }

    @Test func respectsLimit() {
        let many = (0..<30).map { C(id: "\($0)", kind: .history, title: "item \($0)", subtitle: "https://x\($0).com") }
        #expect(PaletteSearch.rank(many, query: "item", limit: 5).count == 5)
    }

    /// Regression: "Watch Page for Changes…" (with an ellipsis) lost to "Search DuckDuckGo" when typed in full.
    @Test func typedCommandNamesBeatWebSearch() {
        #expect(PaletteSearch.score(query: "Watch Page for Changes", title: "Watch Page for Changes…", subtitle: "", subtitleIsAddress: false) == 120)
        #expect(PaletteSearch.outranksWebSearch(query: "Watch Page for Changes", title: "Watch Page for Changes…", subtitle: "", kind: .command))
        #expect(PaletteSearch.outranksWebSearch(query: "watch page for chan", title: "Watch Page for Changes…", subtitle: "", kind: .command))
        // A short word that merely starts a command name is still a search by default.
        #expect(!PaletteSearch.outranksWebSearch(query: "watch", title: "Watch Page for Changes…", subtitle: "", kind: .command))
        // History entries need a near-exact match, as before.
        #expect(!PaletteSearch.outranksWebSearch(query: "swift", title: "Swift Concurrency docs", subtitle: "https://docs.example.com", kind: .history))
        #expect(PaletteSearch.outranksWebSearch(query: "github", title: "GitHub", subtitle: "https://github.com", kind: .history))
    }
}
