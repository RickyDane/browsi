import Foundation

nonisolated enum SearchEngine: String, CaseIterable, Identifiable, Codable {
    case duckDuckGo, google, kagi, bing, ecosia
    var id: String { rawValue }
    var name: String {
        switch self {
        case .duckDuckGo: "DuckDuckGo"
        case .google: "Google"
        case .kagi: "Kagi"
        case .bing: "Bing"
        case .ecosia: "Ecosia"
        }
    }
    func searchURL(for query: String) -> URL {
        var c: URLComponents
        switch self {
        case .duckDuckGo: c = URLComponents(string: "https://duckduckgo.com/")!
        case .google: c = URLComponents(string: "https://www.google.com/search")!
        case .kagi: c = URLComponents(string: "https://kagi.com/search")!
        case .bing: c = URLComponents(string: "https://www.bing.com/search")!
        case .ecosia: c = URLComponents(string: "https://www.ecosia.org/search")!
        }
        c.queryItems = [URLQueryItem(name: "q", value: query)]
        return c.url!
    }
}

/// Turns whatever the user typed into a URL: either a navigable address or a search.
nonisolated enum URLInputParser {
    enum Result: Equatable {
        case url(URL)
        case search(String)
    }

    static func parse(_ raw: String) -> Result? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        if input.contains(" ") { return .search(input) }

        let lower = input.lowercased()
        let explicitSchemes = ["http://", "https://", "file://", "about:", "data:"]
        if explicitSchemes.contains(where: lower.hasPrefix), let url = URL(string: input) {
            return .url(url)
        }

        // localhost / IPv4, optionally with port and path → http
        let hostPart = String(lower.split(separator: "/", maxSplits: 1).first ?? "")
        let hostOnly = String(hostPart.split(separator: ":").first ?? "")
        if hostOnly == "localhost" || isIPv4(hostOnly) {
            if let url = URL(string: "http://" + input) { return .url(url) }
        }

        // something.tld → https
        if hostOnly.contains("."),
           let tld = hostOnly.split(separator: ".").last, tld.count >= 2,
           tld.allSatisfy({ $0.isLetter }),
           hostOnly.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }),
           !hostOnly.hasPrefix("."), !hostOnly.hasSuffix("."),
           let url = URL(string: "https://" + input), url.host() != nil {
            return .url(url)
        }
        return .search(input)
    }

    static func url(for raw: String, engine: SearchEngine) -> URL? {
        switch parse(raw) {
        case .url(let u): u
        case .search(let q): engine.searchURL(for: q)
        case nil: nil
        }
    }

    private static func isIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
    }
}
