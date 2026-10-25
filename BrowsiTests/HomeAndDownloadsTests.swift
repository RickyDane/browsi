import Testing
import Foundation
import AppKit
@testable import Browsi

struct GridLayoutTests {
    typealias R = GridRect

    @Test func movingOntoAnotherPushesItDown() {
        let items: [(id: String, rect: R)] = [("a", R(col: 0, row: 0, w: 6, h: 4)), ("b", R(col: 6, row: 0, w: 6, h: 4))]
        let out = GridLayout.resolve(items, fixedID: "b", fixed: R(col: 0, row: 0, w: 6, h: 4))
        #expect(out["b"] == R(col: 0, row: 0, w: 6, h: 4))
        #expect(out["a"] == R(col: 0, row: 4, w: 6, h: 4))
    }

    @Test func compactsGapsUpwards() {
        let items: [(id: String, rect: R)] = [("a", R(col: 0, row: 7, w: 4, h: 3))]
        #expect(GridLayout.resolve(items, fixedID: nil, fixed: nil)["a"]?.row == 0)
    }

    @Test func clampsToGridAndMinimumSize() {
        #expect(GridLayout.clamp(R(col: 10, row: -2, w: 6, h: 1)) == R(col: 6, row: 0, w: 6, h: 2))
        #expect(GridLayout.clamp(R(col: 0, row: 0, w: 40, h: 40)).w == GridLayout.columns)
    }

    @Test func noOverlapsAfterResolve() {
        let items: [(id: Int, rect: R)] = (0..<8).map { ($0, R(col: ($0 * 3) % 12, row: $0 / 4, w: 4, h: 3)) }
        let out = GridLayout.resolve(items, fixedID: 3, fixed: R(col: 2, row: 0, w: 8, h: 5))
        let rects = Array(out.values)
        for i in rects.indices { for j in rects.indices where i < j { #expect(!rects[i].intersects(rects[j])) } }
    }

    @Test func lockedAreaIsNeverCoveredOrMoved() {
        let hero = R(col: 3, row: 3, w: 6, h: 4)
        let items: [(id: String, rect: R)] = [("a", R(col: 2, row: 2, w: 4, h: 3)), ("side", R(col: 0, row: 4, w: 3, h: 3))]
        let out = GridLayout.resolve(items, fixedID: nil, fixed: nil, locked: [hero])
        for r in out.values { #expect(!r.intersects(hero)) }
        #expect(out["side"]?.col == 0, "modules beside the search area stay beside it")
        // Dragging onto the hero lands just below it instead.
        let moved = GridLayout.resolve(items, fixedID: "a", fixed: R(col: 4, row: 4, w: 4, h: 2), locked: [hero])
        #expect(moved["a"].map { !$0.intersects(hero) } == true)
    }

    @Test func firstFreeFindsHole() {
        let r = GridLayout.firstFree(w: 4, h: 2, among: [R(col: 0, row: 0, w: 8, h: 2)])
        #expect(r == R(col: 8, row: 0, w: 4, h: 2))
    }
}

@MainActor
struct HomeStoreTests {
    @Test func addMoveRemovePersists() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "home-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = HomeStore(fileURL: file)
        let start = store.modules.count
        let m = store.add(url: URL(string: "https://example.com")!, title: "")
        #expect(store.modules.count == start + 1)
        #expect(m.title == "example.com")
        store.commit(m.id, at: GridRect(col: 0, row: 0, w: 12, h: 3))
        let reloaded = HomeStore(fileURL: file)
        #expect(reloaded.modules.first { $0.id == m.id }?.rect == GridRect(col: 0, row: 0, w: 12, h: 3))
        // Everything else was pushed below the full-width module.
        #expect(reloaded.modules.filter { $0.id != m.id }.allSatisfy { $0.rect.row >= 3 })
        store.remove(m.id)
        #expect(HomeStore(fileURL: file).modules.count == start)
    }
}

struct SmartSearchParsingTests {
    static let html = """
    <div class="result"><h2><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fen.wikipedia.org%2Fwiki%2FParis&amp;rut=x">Paris - <b>Wikipedia</b></a></h2>
    <a class="result__snippet" href="x">Paris is the <b>capital</b> of France &amp; its largest city.</a></div>
    <div class="result"><a class="result__a" href="https://duckduckgo.com/y.js?ad=1">Ad</a><a class="result__snippet">ad</a></div>
    <div class="result"><a class="result__a" href="https://www.britannica.com/place/Paris">Paris | Britannica</a>
    <a class="result__snippet" href="y">City in France.</a></div>
    """

    @Test func parsesDuckDuckGoResults() {
        let r = WebSearch.parse(Self.html)
        #expect(r.count == 2)
        #expect(r.first?.url.absoluteString == "https://en.wikipedia.org/wiki/Paris")
        #expect(r.first?.title == "Paris - Wikipedia")
        #expect(r.first?.snippet == "Paris is the capital of France & its largest city.")
        #expect(r.last?.url.host() == "www.britannica.com")
    }

    @Test func stripsHTML() {
        #expect(HTMLText.plain("<style>a{}</style><p>Hi <b>there</b></p><script>x()</script>") == "Hi there")
    }

    @Test func linksCitations() {
        let s = [AnswerSource(number: 1, title: "W", url: URL(string: "https://w.org")!)]
        #expect(SmartSearch.linkCitations("Paris [1], see [2].", sources: s) == "Paris [\\[1\\]](https://w.org), see [2].")
    }

    @MainActor
    @Test(.enabled(if: SmartSearch.isAvailable, "Apple Intelligence not available"))
    func liveSmartAnswer() async {
        let search = SmartSearch()
        search.run("What is the capital of France? Answer in one sentence.", library: LibraryStore(inMemory: true))
        let end = ContinuousClock.now + .seconds(60)
        while search.phase == .working, ContinuousClock.now < end { try? await Task.sleep(for: .milliseconds(200)) }
        print("SMART-ANSWER phase=\(search.phase) sources=\(search.sources.count): \(search.answer)")
        #expect(search.phase == .done)
        #expect(search.answer.localizedCaseInsensitiveContains("Paris"))
    }

    @Test func liveWebSearchReturnsResults() async throws {
        let results = try await WebSearch.search("Swift programming language")
        print("WEB-SEARCH", results.count, results.first?.url.absoluteString ?? "-")
        #expect(!results.isEmpty)
    }
}

@MainActor
struct PinnedAndHomeTabTests {
    @Test func commandWKeepsPinnedTabButUnloadsIt() {
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        let regular = browser.newTab(url: URL(string: "about:blank#r"))
        let pinned = browser.newTab(url: URL(string: "about:blank#p"))
        browser.togglePin(pinned)
        pinned.controller?.webView.load(URLRequest(url: URL(string: "about:blank#elsewhere")!))
        pinned.url = URL(string: "about:blank#elsewhere")
        browser.select(pinned)

        browser.closeSelectedTab()
        #expect(browser.selectedSpace.pinnedTabs.contains { $0 === pinned }, "still pinned")
        #expect(pinned.isSuspended, "unloaded")
        #expect(pinned.url?.absoluteString == "about:blank#p", "reset to its pinned address")
        #expect(browser.selectedTab === regular)

        browser.close(pinned, removePinned: true)
        #expect(!browser.allTabs.contains { $0 === pinned })
    }

    @Test func homeIsAlwaysAvailableAndLinksOpenTabs() {
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        let a = browser.newTab(url: URL(string: "about:blank#a"))
        browser.showHome()
        #expect(browser.selectedTab == nil, "home is shown")
        #expect(browser.allTabs.count == 1 && a.controller != nil, "the tab keeps running")
        browser.openFromHome(URL(string: "about:blank#x")!)
        #expect(browser.allTabs.count == 2)
        #expect(browser.selectedTab?.url?.absoluteString == "about:blank#x")
        browser.showHome()
        browser.openFromHome(URL(string: "about:blank#y")!, background: true)
        #expect(browser.selectedTab == nil && browser.allTabs.count == 3)
        browser.select(a)
        #expect(browser.selectedTab === a)
    }

    @Test func closingLastTabShowsHomeNotPalette() {
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        let t = browser.newTab(url: URL(string: "about:blank"))
        browser.close(t)
        #expect(browser.selectedTab == nil)
        #expect(browser.palette == .hidden)
    }
}

@MainActor
@Suite(.serialized)
struct DownloadQueueTests {
    @Test func renameKeepsExtensionAndCanUndo() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "file_8f3a2c91.pdf")
        try Data("x".utf8).write(to: file)
        let item = DownloadItem(fileName: file.lastPathComponent, fileURL: file, state: .finished,
                                context: DownloadContext(originalName: file.lastPathComponent))
        let manager = DownloadManager.shared
        manager.reset([item])

        #expect(manager.rename(item, to: "Acme: Invoice 8823"))
        #expect(item.fileName == "Acme Invoice 8823.pdf")
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "Acme Invoice 8823.pdf").path(percentEncoded: false)))
        #expect(item.renamedFrom == "file_8f3a2c91.pdf")

        manager.undoRename(item)
        #expect(item.fileName == "file_8f3a2c91.pdf")
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        manager.reset()
    }

    @Test func downloadsButtonShowsOnActivityAndHidesWhenIdle() async {
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        #expect(!browser.downloadsButtonShown, "hidden by default")
        browser.noteDownloadActivity()
        #expect(browser.downloadsButtonShown)
        browser.scheduleDownloadsAutoHide(after: .milliseconds(150))
        try? await Task.sleep(for: .milliseconds(400))
        #expect(!browser.downloadsButtonShown, "hides after the idle timeout")

        // Hovering (or an open panel) keeps it visible.
        browser.noteDownloadActivity()
        browser.downloadsHovering = true
        browser.scheduleDownloadsAutoHide(after: .milliseconds(100))
        try? await Task.sleep(for: .milliseconds(300))
        #expect(browser.downloadsButtonShown)
        browser.downloadsHovering = false
    }

    @Test func commandJTogglesQueue() {
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        browser.toggleDownloads()
        #expect(browser.downloadsButtonShown && browser.downloadsVisible)
        browser.toggleDownloads()
        #expect(!browser.downloadsButtonShown && !browser.downloadsVisible)
    }

    @Test func downloadFliesFromLastClickAndBouncesButton() {
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        browser.recordClick(at: CGPoint(x: 640, y: 320))
        browser.launchDownloadFlight(for: "report.pdf")
        let flight = try! #require(browser.downloadFlights.first)
        #expect(flight.from == CGPoint(x: 640, y: 320))
        browser.landDownloadFlight(flight.id)
        #expect(browser.downloadFlights.isEmpty)
        #expect(browser.downloadsBounce == 1)
    }
}

struct PathEncodingRegressionTests {
    /// `URL.path()` percent-encodes spaces; collision checks must use the real path.
    @Test func uniqueURLDetectsCollisionsWithSpaces() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data().write(to: dir.appending(path: "My Report.pdf"))
        #expect(DownloadManager.uniqueURL(in: dir, fileName: "My Report.pdf").lastPathComponent == "My Report 2.pdf")
    }
}

struct RenameMorphTests {
    private func plain(_ s: AttributedString) -> String { String(s.characters) }

    @Test func morphStartsOldEndsNew() {
        let old = "winfer_0.1.105-75_x64.dmg", new = "Winfer 0.1.105.dmg"
        #expect(plain(RenameMorphText.compose(from: old, to: new, progress: 0, frame: 0)) == old)
        #expect(plain(RenameMorphText.compose(from: old, to: new, progress: 1, frame: 7)) == new)
        let mid = plain(RenameMorphText.compose(from: old, to: new, progress: 0.4, frame: 3))
        #expect(mid != old && mid != new)
    }
}

@MainActor
struct SharedSuggestionTests {
    @Test func homeAndPaletteShareResults() {
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        browser.library.recordVisit(url: URL(string: "https://www.google.com/")!, title: "Google")
        let results = PaletteResults.build(query: "goog", editingCurrent: false, browser: browser, openSettings: {})
        #expect(results.contains { $0.kind == .history && $0.title == "Google" })
        #expect(results.contains { $0.id == "search" })
        let url = PaletteResults.build(query: "apple.com", editingCurrent: false, browser: browser, openSettings: {})
        #expect(url.first?.id == "nav")
    }
}

@MainActor
struct HeroLayoutTests {
    @Test func searchBlockMovesAndModulesMakeRoom() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "home-\(UUID()).json")
        defer {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent().appending(path: "home-hero.json"))
        }
        let store = HomeStore(fileURL: file)
        let m = store.add(url: URL(string: "https://example.com")!, title: "M", w: 4, h: 3)
        store.commit(m.id, at: GridRect(col: 0, row: 0, w: 4, h: 3))
        store.commitHero(GridRect(col: 0, row: 0, w: 6, h: 4))
        #expect(store.heroRect == GridRect(col: 0, row: 0, w: 6, h: 4))
        let moved = try #require(store.modules.first { $0.id == m.id }?.rect)
        #expect(!moved.intersects(store.heroRect), "module pushed out of the search block")
        #expect(HomeStore(fileURL: file).heroRect == GridRect(col: 0, row: 0, w: 6, h: 4), "persisted")
        // Too small → clamped to the minimum.
        store.commitHero(GridRect(col: 11, row: 0, w: 1, h: 1))
        #expect(store.heroRect.w >= HomeStore.heroMin.w && store.heroRect.h >= HomeStore.heroMin.h)
        #expect(store.heroRect.col + store.heroRect.w <= GridLayout.columns)
    }
}
