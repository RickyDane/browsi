import Testing
import Foundation
@testable import Browsi

struct URLInputParserTests {
    @Test(arguments: [
        ("apple.com", "https://apple.com"),
        ("https://example.org/a?b=1", "https://example.org/a?b=1"),
        ("news.ycombinator.com/item?id=1", "https://news.ycombinator.com/item?id=1"),
        ("localhost:3000", "http://localhost:3000"),
        ("192.168.1.10/admin", "http://192.168.1.10/admin"),
        ("about:blank", "about:blank"),
    ])
    func parsesURLs(input: String, expected: String) {
        #expect(URLInputParser.parse(input) == .url(URL(string: expected)!))
    }

    @Test(arguments: ["swift concurrency", "hello", "what is 1.5", "file.", "v1.2"])
    func parsesSearches(input: String) {
        #expect(URLInputParser.parse(input) == .search(input))
    }

    @Test func emptyIsNil() {
        #expect(URLInputParser.parse("   ") == nil)
    }

    @Test func searchURLEncodesQuery() {
        let url = SearchEngine.duckDuckGo.searchURL(for: "a&b c")
        #expect(url.absoluteString == "https://duckduckgo.com/?q=a%26b%20c")
    }
}
