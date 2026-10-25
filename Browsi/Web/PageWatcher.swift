import AppKit
import FoundationModels
import Observation
import UserNotifications
import WebKit

/// A page Browsi re-checks in the background, notifying when its content changes.
nonisolated struct PageWatch: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var url: URL
    var title: String
    var intervalMinutes: Int = 60
    var created = Date()
    var lastChecked: Date?
    var lastChanged: Date?
    var lastSummary: String?
    var lastError: String?
    /// The page's text at the last check; changes are measured against it.
    var baseline: String = ""
    var unseen = false
    /// What the user cares about, e.g. "price drops below $100" or "new chapters". Empty/nil: any meaningful change.
    var focus: String?

    var trimmedFocus: String? {
        let f = focus?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return f.isEmpty ? nil : f
    }

    /// Instructions for the change check; with a focus, only changes about it count.
    static func judgeInstructions(focus: String?) -> String {
        var s = """
        You watch a web page for someone and decide if it changed in a way they would want to be told about. \
        Ignore noise such as clocks, "x minutes ago", view or like counts, ads and rotating recommendations.
        """
        if let focus, !focus.isEmpty {
            s += """
             They asked to be told only about this: "\(focus)". Set meaningful to true only if the change is \
            about that or makes it come true; everything else is not meaningful. The summary says what happened \
            regarding it.
            """
        } else {
            s += " Typical meaningful changes: new posts or articles, price or stock changes, new versions, schedule or status updates."
        }
        return s
    }

    static let focusSuggestions = ["Price drops", "Back in stock", "New articles or posts", "New version released"]

    func isDue(at now: Date) -> Bool {
        guard let lastChecked else { return true }
        return now.timeIntervalSince(lastChecked) >= Double(intervalMinutes) * 60
    }

    static let intervals: [(minutes: Int, name: String)] = [
        (15, "Every 15 minutes"), (60, "Every hour"), (360, "Every 6 hours"), (1440, "Every day"),
    ]
}

/// Line-level diff of a page's text (unit tested).
nonisolated enum PageDiff {
    struct Change: Equatable, Sendable {
        var added: [String]
        var removed: [String]
        var isEmpty: Bool { added.isEmpty && removed.isEmpty }
    }

    static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { $0.count >= 2 }
    }

    /// Lines that appear more often in `new` than in `old` (added) and vice versa (removed), in page order.
    static func compare(old: String, new: String) -> Change {
        let a = lines(old), b = lines(new)
        func extra(_ xs: [String], over ys: [String]) -> [String] {
            var remaining: [String: Int] = [:]
            ys.forEach { remaining[$0, default: 0] += 1 }
            return xs.filter { l in
                if let n = remaining[l], n > 0 { remaining[l] = n - 1; return false }
                return true
            }
        }
        let added = extra(b, over: a), removed = extra(a, over: b)
        return Change(added: added, removed: removed)
    }

    /// Plain-language fallback summary when Apple Intelligence isn't available.
    static func fallbackSummary(_ c: Change) -> String {
        if let first = c.added.first { return "New: " + SmartTitler.clip(first, to: 120) }
        if let first = c.removed.first { return "Removed: " + SmartTitler.clip(first, to: 120) }
        return "The page changed."
    }

    static func clipped(_ lines: [String], budget: Int) -> String {
        var used = 0
        var out: [String] = []
        for l in lines {
            let l = SmartTitler.clip(l, to: 300)
            guard used + l.count <= budget else { break }
            out.append("- " + l)
            used += l.count
        }
        return out.joined(separator: "\n")
    }
}

@Generable(description: "Whether a web page changed in a way its reader cares about")
nonisolated struct ChangeReport {
    @Guide(description: "False if the change is only noise: timestamps, view counts, ads, rotating recommendations, cookie notices or session tokens")
    var meaningful: Bool
    @Guide(description: "What changed, in one short sentence (at most 20 words), e.g. 'Price dropped from $129 to $99'")
    var summary: String
}

/// Keeps the watched pages, checks them on their interval in a hidden web view and posts notifications.
@Observable
final class PageWatcher: NSObject {
    static let shared = PageWatcher()

    private(set) var watches: [PageWatch] = []
    private(set) var checking: Set<UUID> = []
    @ObservationIgnored weak var browser: BrowserState?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var running = false
    @ObservationIgnored private let file: URL

    init(file: URL = URL.applicationSupportDirectory.appending(path: "Browsi/watches.json")) {
        self.file = file
        super.init()
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([PageWatch].self, from: data) {
            watches = saved
        }
    }

    func start(browser: BrowserState) {
        self.browser = browser
        UNUserNotificationCenter.current().delegate = self
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { PageWatcher.shared.checkDue() }
        }
        Task {
            try? await Task.sleep(for: .seconds(20))
            checkDue()
        }
    }

    // MARK: Watches

    func watch(for url: URL?) -> PageWatch? {
        guard let url else { return nil }
        return watches.first { Self.same($0.url, url) }
    }

    func isWatching(_ url: URL?) -> Bool { watch(for: url) != nil }

    /// Starts watching `url`; the first check records the baseline.
    func add(url: URL, title: String, focus: String? = nil, intervalMinutes: Int = 60) {
        guard !isWatching(url) else { return }
        var w = PageWatch(url: url, title: title.isEmpty ? (url.host() ?? url.absoluteString) : title)
        w.focus = focus
        w.intervalMinutes = intervalMinutes
        watches.append(w)
        save()
        requestNotificationPermission()
        Task { await check(w.id) }
    }

    func remove(_ id: UUID) {
        watches.removeAll { $0.id == id }
        save()
    }

    func setInterval(_ minutes: Int, for id: UUID) {
        update(id) { $0.intervalMinutes = minutes }
    }

    func setFocus(_ focus: String, for id: UUID) {
        update(id) { $0.focus = focus.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// The user looked at the page: clear its "changed" badge.
    func markSeen(_ url: URL?) {
        guard let w = watch(for: url), w.unseen else { return }
        update(w.id) { $0.unseen = false }
    }

    private func update(_ id: UUID, _ change: (inout PageWatch) -> Void) {
        guard let i = watches.firstIndex(where: { $0.id == id }) else { return }
        change(&watches[i])
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(watches).write(to: file, options: .atomic)
    }

    nonisolated static func same(_ a: URL, _ b: URL) -> Bool {
        func key(_ u: URL) -> String {
            var s = u.absoluteString
            if let hash = s.firstIndex(of: "#") { s = String(s[..<hash]) }
            if s.hasSuffix("/") { s.removeLast() }
            return s.replacingOccurrences(of: "://www.", with: "://")
        }
        return key(a) == key(b)
    }

    // MARK: Checking

    func checkDue() {
        guard !running else { return }
        let due = watches.filter { $0.isDue(at: .now) }.map(\.id)
        guard !due.isEmpty else { return }
        running = true
        Task {
            for id in due { await check(id) }
            running = false
        }
    }

    func check(_ id: UUID) async {
        guard let w = watches.first(where: { $0.id == id }), !checking.contains(id) else { return }
        checking.insert(id)
        defer { checking.remove(id) }
        guard let text = await HeadlessPage.text(of: w.url), !text.isEmpty else {
            update(id) { $0.lastChecked = .now; $0.lastError = "Couldn’t load the page." }
            return
        }
        guard !w.baseline.isEmpty else {
            update(id) { $0.lastChecked = .now; $0.baseline = text; $0.lastError = nil }
            return
        }
        let change = PageDiff.compare(old: w.baseline, new: text)
        guard !change.isEmpty else {
            update(id) { $0.lastChecked = .now; $0.lastError = nil }
            return
        }
        let report = await Self.judge(change, title: w.title, focus: w.trimmedFocus)
        update(id) {
            $0.lastChecked = .now
            $0.baseline = text
            $0.lastError = nil
            if let report {
                $0.lastChanged = .now
                $0.lastSummary = report
                $0.unseen = true
            }
        }
        if let report { notify(w, summary: report) }
    }

    /// A one-line summary when the change matters, nil when it's noise.
    private static func judge(_ c: PageDiff.Change, title: String, focus: String?) async -> String? {
        guard SmartSearch.isAvailable else { return PageDiff.fallbackSummary(c) }
        let instructions = PageWatch.judgeInstructions(focus: focus)
        var prompt = "Page: \(title.prefix(150))\n\n"
        if let focus { prompt += "Watching for: \(focus)\n\n" }
        if !c.removed.isEmpty { prompt += "Lines removed:\n\(PageDiff.clipped(c.removed, budget: 1400))\n\n" }
        if !c.added.isEmpty { prompt += "Lines added:\n\(PageDiff.clipped(c.added, budget: 1800))\n\n" }
        let session = LanguageModelSession(model: PageAssistant.model(), instructions: instructions)
        do {
            let r = try await session.respond(to: prompt, generating: ChangeReport.self,
                                              options: GenerationOptions(temperature: 0.1))
            let summary = r.content.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            return r.content.meaningful ? (summary.isEmpty ? PageDiff.fallbackSummary(c) : summary) : nil
        } catch {
            return PageDiff.fallbackSummary(c)
        }
    }

    // MARK: Notifications

    private func requestNotificationPermission() {
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    private func notify(_ w: PageWatch, summary: String) {
        let content = UNMutableNotificationContent()
        content.title = w.title
        content.subtitle = w.url.host()?.replacingOccurrences(of: "www.", with: "") ?? ""
        content.body = summary
        content.sound = .default
        content.userInfo = ["url": w.url.absoluteString]
        let request = UNNotificationRequest(identifier: "watch-\(w.id)-\(Date.now.timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        browser?.showToast("eye.fill", "\(SmartTitler.clip(w.title, to: 30)) changed")
    }

    fileprivate func openFromNotification(_ url: URL) {
        NSApp.activate()
        markSeen(url)
        guard let browser else { return }
        if let tab = browser.allTabs.first(where: { $0.url.map { Self.same($0, url) } ?? false }) {
            browser.select(tab)
            tab.controller?.webView.reload()
        } else {
            browser.newTab(url: url)
        }
    }
}

extension PageWatcher: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let s = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: s) else { return }
        await MainActor.run { PageWatcher.shared.openFromNotification(url) }
    }
}

/// Loads a page in an off-screen web view (sharing the browser's cookies) and returns its main text.
@MainActor
final class HeadlessPage: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Bool, Never>?
    private let webView: WKWebView

    private override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = .all
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 900), configuration: config)
        webView.customUserAgent = UserAgent.current
        super.init()
        webView.navigationDelegate = self
    }

    static func text(of url: URL, timeout: Duration = .seconds(25)) async -> String? {
        let page = HeadlessPage()
        defer { page.webView.stopLoading(); page.webView.navigationDelegate = nil }
        let timer = Task {
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled { page.finish(false) }
        }
        let loaded = await page.load(url)
        timer.cancel()
        guard loaded else { return nil }
        // Give script-rendered pages a moment to fill in.
        try? await Task.sleep(for: .seconds(2.5))
        return await PageScripts.mainText(of: page.webView)
    }

    private func load(_ url: URL) async -> Bool {
        await withCheckedContinuation { c in
            continuation = c
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
        }
    }

    private func finish(_ ok: Bool) {
        continuation?.resume(returning: ok)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(true) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(false) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(false)
    }
}
