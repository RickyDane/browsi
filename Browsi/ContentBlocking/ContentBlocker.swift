import WebKit

/// Compiles the bundled block list into a WKContentRuleList once and caches it on disk.
final class ContentBlocker {
    static let shared = ContentBlocker()
    static let identifier = "browsi-blocklist-v1"

    private(set) var ruleList: WKContentRuleList?
    private var waiters: [CheckedContinuation<WKContentRuleList?, Never>] = []
    private var loading = false

    /// Cosmetic filters applied on every site.
    nonisolated static let hiddenSelectors = [
        ".adsbygoogle", "ins.adsbygoogle", "[id^='google_ads_iframe']", "[id^='div-gpt-ad']",
        ".ad-banner", ".ad-container", ".advertisement", "[data-ad-slot]", ".taboola", "#taboola-below-article",
        ".OUTBRAIN", "[data-testid='placementTracking']",
    ]

    nonisolated static func rulesJSON(domains: [String]) -> String {
        var rules: [[String: Any]] = domains.map { d in
            let parts = d.split(separator: "/", maxSplits: 1).map(String.init)
            let host = NSRegularExpression.escapedPattern(for: parts[0])
            let path = parts.count > 1 ? "/" + NSRegularExpression.escapedPattern(for: parts[1]) : "[:/]"
            return [
                "trigger": ["url-filter": "^https?://([^/]+\\.)?\(host)\(path)", "load-type": ["third-party"]],
                "action": ["type": "block"],
            ]
        }
        rules.append([
            "trigger": ["url-filter": ".*"],
            "action": ["type": "css-display-none", "selector": hiddenSelectors.joined(separator: ", ")],
        ])
        let data = try! JSONSerialization.data(withJSONObject: rules)
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated static func bundledDomains() -> [String] {
        guard let url = Bundle.main.url(forResource: "blocklist", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// Loads the compiled list from WebKit's cache, compiling it if missing or outdated.
    func load() async -> WKContentRuleList? {
        if let ruleList { return ruleList }
        if loading { return await withCheckedContinuation { waiters.append($0) } }
        loading = true
        let store = WKContentRuleListStore.default()!
        var list = try? await store.contentRuleList(forIdentifier: Self.identifier)
        if list == nil {
            let json = Self.rulesJSON(domains: Self.bundledDomains())
            list = try? await store.compileContentRuleList(forIdentifier: Self.identifier, encodedContentRuleList: json)
        }
        ruleList = list
        loading = false
        waiters.forEach { $0.resume(returning: list) }
        waiters.removeAll()
        return list
    }

    func isEnabled(for host: String?) -> Bool {
        let p = Preferences.shared
        guard p.contentBlockingEnabled else { return false }
        guard let host else { return true }
        return !p.blockerAllowlist.contains(host)
    }

    /// Adds or removes the rule list for a web view depending on prefs for `host`.
    func apply(to controller: WKUserContentController, host: String?) {
        guard let ruleList else { return }
        controller.remove(ruleList)
        if isEnabled(for: host) { controller.add(ruleList) }
    }
}
