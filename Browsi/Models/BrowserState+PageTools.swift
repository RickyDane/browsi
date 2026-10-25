import AppKit
import SwiftUI
@preconcurrency import Translation

/// Find in page, translation, page actions and page watching.
extension BrowserState {
    /// The selected tab when it shows a real web page.
    var selectedWebTab: Tab? {
        guard let tab = selectedTab, !tab.isHome, tab.url != nil else { return nil }
        return tab
    }

    // MARK: Find

    func openFind(_ mode: FindInPage.Mode = .text) {
        guard let tab = selectedWebTab else { return }
        activate(tab)
        find.tint = NSColor(selectedSpace.color)
        withAnimation(Motion.snappy) { find.open(mode, tab: tab) }
    }

    func findNext(forward: Bool) {
        if !find.visible { openFind(); return }
        find.next(forward: forward)
    }

    func closeFind() {
        withAnimation(Motion.snappy) { find.close() }
    }

    // MARK: Translation

    func translator(for tab: Tab) -> PageTranslator {
        if let t = pageTranslators[tab.id] { return t }
        let t = PageTranslator()
        pageTranslators[tab.id] = t
        return t
    }

    func detectLanguage(of tab: Tab) {
        guard Preferences.shared.offerTranslation || !Preferences.shared.alwaysTranslate.isEmpty,
              tab.controller?.isPeek != true else { return }
        let t = translator(for: tab)
        if t.isBusy, translationTab === tab { translationTab = nil }
        Task {
            guard await t.pageLoaded(tab), let lang = t.language,
                  Preferences.shared.alwaysTranslate.contains(lang), translationTab == nil else { return }
            translate(tab)
        }
    }

    /// Translates the tab's page, or shows the original if it's already translated.
    func toggleTranslation(_ tab: Tab? = nil) {
        guard let tab = tab ?? selectedWebTab else { return }
        let t = translator(for: tab)
        if t.isTranslated || t.isBusy {
            if translationTab === tab { translationTab = nil }
            t.restore(tab)
        } else {
            translate(tab)
        }
    }

    private func translate(_ tab: Tab) {
        let t = translator(for: tab)
        t.state = .translating(done: 0, total: 0)
        translationTab = tab
        let config = TranslationSession.Configuration(source: t.language.map { Locale.Language(identifier: $0) },
                                                      target: PageTranslator.targetLanguage)
        if translationConfig == config { translationConfig?.invalidate() } else { translationConfig = config }
    }

    /// Called by the window's `.translationTask` with a session for the current configuration.
    func runTranslation(with session: TranslationSession) async {
        guard let tab = translationTab else { return }
        let t = translator(for: tab)
        await t.translate(tab, with: session)
        if translationTab === tab { translationTab = nil }
        if case .failed(let message) = t.state { showToast("exclamationmark.triangle.fill", message) }
    }

    func setAlwaysTranslate(_ lang: String, _ on: Bool) {
        if on { Preferences.shared.alwaysTranslate.insert(lang) } else { Preferences.shared.alwaysTranslate.remove(lang) }
    }

    // MARK: Page actions

    func startPageAction(_ kind: PageActionRun.Kind) {
        guard let tab = selectedWebTab else { return }
        activate(tab)
        pageAction?.cancel()
        let run = PageActionRun(kind: kind)
        run.start(tab: tab, others: kind == .compare ? compareCandidates(for: tab) : [])
        withAnimation(Motion.bouncy) { pageAction = run }
    }

    func closePageAction() {
        pageAction?.cancel()
        withAnimation(Motion.snappy) { pageAction = nil }
    }

    /// Other web pages in the tab's space to compare with, most recently used first (up to 3).
    func compareCandidates(for tab: Tab) -> [Tab] {
        let space = space(of: tab) ?? selectedSpace
        return space.allTabs
            .filter { $0 !== tab && !$0.isHome && $0.url?.scheme?.hasPrefix("http") == true }
            .sorted { $0.lastActive > $1.lastActive }
            .prefix(3)
            .map { $0 }
    }

    // MARK: Watching

    /// Opens the "Watch This Page" sheet: to start watching, or to edit/stop an existing watch.
    func showWatchSetup(_ tab: Tab? = nil) {
        guard let tab = tab ?? selectedWebTab, let url = tab.url, url.scheme?.hasPrefix("http") == true else { return }
        let existing = PageWatcher.shared.watch(for: url)
        withAnimation(Motion.bouncy) {
            watchSetup = WatchSetup(url: url, title: existing?.title ?? tab.smartTitle ?? tab.displayTitle, existing: existing)
        }
    }

    func closeWatchSetup() {
        withAnimation(Motion.snappy) { watchSetup = nil }
    }

    func stopWatching(_ url: URL?) {
        guard let w = PageWatcher.shared.watch(for: url) else { return }
        PageWatcher.shared.remove(w.id)
        showToast("eye.slash", "Stopped watching this page")
    }
}

struct WatchSetup: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let existing: PageWatch?
}
