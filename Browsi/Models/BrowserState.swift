import SwiftUI
import WebKit
import Observation

enum PaletteMode: Equatable {
    case hidden
    case newTab
    case editCurrent
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let symbol: String
    let text: String
}

/// The window's whole browsing state: spaces, tabs, selection and transient UI.
@Observable
final class BrowserState {
    var spaces: [Space]
    var selectedSpaceID: UUID
    var palette: PaletteMode = .hidden
    var sidebarVisible = true
    var pendingPasswordSave: PendingPasswordSave?
    var toast: Toast?
    /// +1 / -1 direction of the last space switch, drives the push transition.
    var spaceSwitchDirection: Int = 1

    let library: LibraryStore
    @ObservationIgnored private var closedTabs: [(url: URL, spaceID: UUID)] = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private(set) var suspender: TabSuspender!

    init(library: LibraryStore = LibraryStore(), restore: Bool = true) {
        self.library = library
        if restore, let snap = SessionStore.load(), !snap.spaces.isEmpty {
            spaces = snap.spaces.map { s in
                Space(id: s.id, name: s.name, symbol: s.symbol, hue: s.hue,
                      pinnedTabs: s.pinned.map { Tab(id: $0.id, url: $0.url, title: $0.title, isPinned: true) },
                      tabs: s.tabs.map { Tab(id: $0.id, url: $0.url, title: $0.title) },
                      selectedTabID: s.selectedTabID)
            }
            selectedSpaceID = snap.selectedSpaceID.flatMap { id in snap.spaces.contains { $0.id == id } ? id : nil }
                ?? snap.spaces[0].id
        } else {
            let (n, sym, hue) = Space.palette[0]
            let s = Space(name: n, symbol: sym, hue: hue)
            spaces = [s]
            selectedSpaceID = s.id
        }
        suspender = TabSuspender(browser: self)
        WebConfigFactory.passwordBridge.onOfferSave = { [weak self] offer in
            withAnimation(.bouncy) { self?.pendingPasswordSave = offer }
        }
    }

    func start() {
        suspender.start()
        Task {
            _ = await ContentBlocker.shared.load()
            for tab in allTabs { tab.controller?.applyContentBlocking() }
        }
        if let tab = selectedTab { activate(tab) }
        else if spaces.allSatisfy({ $0.allTabs.isEmpty }) { palette = .newTab }
    }

    // MARK: Accessors

    var selectedSpace: Space { spaces.first { $0.id == selectedSpaceID } ?? spaces[0] }
    var selectedTab: Tab? { selectedSpace.selectedTab }
    var allTabs: [Tab] { spaces.flatMap(\.allTabs) }

    func space(of tab: Tab) -> Space? { spaces.first { $0.allTabs.contains { $0 === tab } } }

    // MARK: Tabs

    @discardableResult
    func newTab(url: URL?, in space: Space? = nil, background: Bool = false, after anchor: Tab? = nil) -> Tab {
        let space = space ?? selectedSpace
        let tab = Tab(url: url)
        withAnimation(Motion.snappy) {
            if let anchor, let i = space.tabs.firstIndex(where: { $0 === anchor }) {
                space.tabs.insert(tab, at: i + 1)
            } else {
                space.tabs.insert(tab, at: 0)
            }
        }
        if background {
            tab.controller = TabWebController(tab: tab, delegate: self)
            if let url { tab.controller?.load(url) }
        } else {
            select(tab)
        }
        scheduleSave()
        return tab
    }

    func select(_ tab: Tab) {
        let previous = selectedTab
        if previous === tab { return }
        if let space = space(of: tab), space.id != selectedSpaceID { switchSpace(to: space) }
        if let old = previous?.controller?.webView, old.window != nil {
            // Grab a snapshot while still on-screen; used if the tab is later suspended.
            Task { previous?.snapshot = try? await old.takeSnapshot(configuration: nil) }
        }
        previous?.lastActive = .now
        withAnimation(Motion.snappy) { space(of: tab)?.selectedTabID = tab.id }
        activate(tab)
        scheduleSave()
    }

    /// Ensures the tab has a live web view (reviving it if suspended).
    func activate(_ tab: Tab) {
        tab.lastActive = .now
        guard tab.controller == nil else { return }
        let c = TabWebController(tab: tab, delegate: self)
        tab.controller = c
        c.restore(interactionState: tab.interactionState, fallback: tab.url)
        tab.interactionState = nil
        // Drop the placeholder snapshot once the revived page has painted.
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.easeOut(duration: 0.25)) { tab.snapshot = nil }
        }
    }

    func close(_ tab: Tab) {
        guard let space = space(of: tab) else { return }
        if let url = tab.url { closedTabs.append((url, space.id)); closedTabs = closedTabs.suffix(30) }
        let ordered = space.allTabs
        let wasSelected = space.selectedTabID == tab.id
        let idx = ordered.firstIndex { $0 === tab } ?? 0
        withAnimation(Motion.snappy) {
            space.tabs.removeAll { $0 === tab }
            space.pinnedTabs.removeAll { $0 === tab }
        }
        tab.controller?.webView.stopLoading()
        tab.controller = nil
        if wasSelected {
            let remaining = space.allTabs
            if remaining.isEmpty {
                space.selectedTabID = nil
                palette = .newTab
            } else {
                select(remaining[min(idx, remaining.count - 1)])
            }
        }
        scheduleSave()
    }

    func closeSelectedTab() {
        if let t = selectedTab { close(t) }
    }

    func reopenClosedTab() {
        guard let last = closedTabs.popLast() else { return }
        newTab(url: last.url, in: spaces.first { $0.id == last.spaceID })
    }

    func togglePin(_ tab: Tab) {
        guard let space = space(of: tab) else { return }
        withAnimation(Motion.bouncy) {
            if tab.isPinned {
                space.pinnedTabs.removeAll { $0 === tab }
                tab.isPinned = false
                space.tabs.insert(tab, at: 0)
            } else {
                space.tabs.removeAll { $0 === tab }
                tab.isPinned = true
                space.pinnedTabs.append(tab)
            }
        }
        scheduleSave()
    }

    /// Reorders by dropping `id` before `target` (or at the end if nil) within the same list.
    func move(tabID: UUID, before target: Tab?, pinned: Bool) {
        let space = selectedSpace
        guard let tab = space.allTabs.first(where: { $0.id == tabID }), tab !== target else { return }
        withAnimation(Motion.snappy) {
            space.tabs.removeAll { $0 === tab }
            space.pinnedTabs.removeAll { $0 === tab }
            tab.isPinned = pinned
            if pinned {
                let i = target.flatMap { t in space.pinnedTabs.firstIndex { $0 === t } } ?? space.pinnedTabs.endIndex
                space.pinnedTabs.insert(tab, at: i)
            } else {
                let i = target.flatMap { t in space.tabs.firstIndex { $0 === t } } ?? space.tabs.endIndex
                space.tabs.insert(tab, at: i)
            }
        }
        scheduleSave()
    }

    func selectTab(atIndex i: Int) {
        let tabs = selectedSpace.allTabs
        guard !tabs.isEmpty else { return }
        select(i >= 8 ? tabs[tabs.count - 1] : tabs[min(i, tabs.count - 1)])
    }

    func selectAdjacentTab(_ delta: Int) {
        let tabs = selectedSpace.allTabs
        guard !tabs.isEmpty else { return }
        let cur = tabs.firstIndex { $0 === selectedTab } ?? 0
        select(tabs[(cur + delta + tabs.count) % tabs.count])
    }

    // MARK: Navigation

    func open(input: String, inNewTab: Bool) {
        guard let url = URLInputParser.url(for: input, engine: Preferences.shared.searchEngine) else { return }
        open(url: url, inNewTab: inNewTab)
    }

    func open(url: URL, inNewTab: Bool) {
        if !inNewTab, let tab = selectedTab {
            activate(tab)
            tab.controller?.load(url)
        } else {
            newTab(url: url)
        }
    }

    // MARK: Spaces

    func switchSpace(to space: Space) {
        guard space.id != selectedSpaceID else { return }
        let from = spaces.firstIndex { $0.id == selectedSpaceID } ?? 0
        let to = spaces.firstIndex { $0.id == space.id } ?? 0
        spaceSwitchDirection = to >= from ? 1 : -1
        selectedTab?.lastActive = .now
        withAnimation(Motion.smooth) { selectedSpaceID = space.id }
        if let tab = space.selectedTab ?? space.allTabs.first {
            space.selectedTabID = tab.id
            activate(tab)
        }
        scheduleSave()
    }

    func switchSpace(offset: Int) {
        guard let i = spaces.firstIndex(where: { $0.id == selectedSpaceID }) else { return }
        let j = i + offset
        guard spaces.indices.contains(j) else { return }
        switchSpace(to: spaces[j])
    }

    func selectSpace(atIndex i: Int) {
        guard spaces.indices.contains(i) else { return }
        switchSpace(to: spaces[i])
    }

    func addSpace() {
        let (n, sym, hue) = Space.palette[spaces.count % Space.palette.count]
        let s = Space(name: spaces.count < Space.palette.count ? n : "Space \(spaces.count + 1)", symbol: sym, hue: hue)
        withAnimation(Motion.bouncy) { spaces.append(s) }
        switchSpace(to: s)
        palette = .newTab
    }

    func delete(space: Space) {
        guard spaces.count > 1 else { return }
        if space.id == selectedSpaceID {
            switchSpace(to: spaces.first { $0.id != space.id }!)
        }
        space.allTabs.forEach { $0.controller = nil }
        withAnimation(Motion.snappy) { spaces.removeAll { $0.id == space.id } }
        scheduleSave()
    }

    // MARK: Library

    func toggleBookmarkForSelectedTab() {
        guard let tab = selectedTab, let url = tab.url else { return }
        let added = library.toggleBookmark(url: url, title: tab.displayTitle)
        showToast(added ? "star.fill" : "star.slash", added ? "Bookmarked" : "Bookmark removed")
    }

    func showToast(_ symbol: String, _ text: String) {
        withAnimation(Motion.bouncy) { toast = Toast(symbol: symbol, text: text) }
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.smooth) { toast = nil }
        }
    }

    // MARK: Passwords

    func resolvePasswordSave(_ choice: PasswordSaveChoice) {
        guard let p = pendingPasswordSave else { return }
        switch choice {
        case .save:
            let store = KeychainStore(synchronizable: Preferences.shared.syncPasswordsWithICloud)
            do {
                try store.save(Credential(host: p.host, username: p.username, password: p.password))
                showToast("key.fill", "Saved to Keychain")
            } catch {
                showToast("exclamationmark.triangle.fill", "Couldn’t save password")
            }
        case .never:
            Preferences.shared.neverSavePasswordHosts.insert(p.host)
        case .notNow:
            break
        }
        withAnimation(Motion.smooth) { pendingPasswordSave = nil }
    }

    // MARK: Content blocking

    func toggleBlockingForSelectedSite() {
        guard let tab = selectedTab, let host = tab.url?.host() else { return }
        let prefs = Preferences.shared
        if prefs.blockerAllowlist.contains(host) {
            prefs.blockerAllowlist.remove(host)
            showToast("shield.lefthalf.filled", "Blocking trackers on \(host)")
        } else {
            prefs.blockerAllowlist.insert(host)
            showToast("shield.slash", "Blocker paused on \(host)")
        }
        tab.controller?.applyContentBlocking()
        tab.controller?.webView.reload()
    }

    // MARK: Session persistence

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveSessionNow()
        }
    }

    func saveSessionNow() {
        func t(_ tab: Tab) -> SessionSnapshot.TabState { .init(id: tab.id, url: tab.url, title: tab.title) }
        let snap = SessionSnapshot(spaces: spaces.map {
            .init(id: $0.id, name: $0.name, symbol: $0.symbol, hue: $0.hue,
                  pinned: $0.pinnedTabs.map(t), tabs: $0.tabs.map(t), selectedTabID: $0.selectedTabID)
        }, selectedSpaceID: selectedSpaceID)
        SessionStore.save(snap)
        library.saveNow()
    }
}

enum PasswordSaveChoice { case save, never, notNow }

// MARK: - TabEventsDelegate

extension BrowserState: TabEventsDelegate {
    func openInNewTab(_ request: URLRequest, from tab: Tab, background: Bool) {
        guard let url = request.url else { return }
        newTab(url: url, in: space(of: tab), background: background, after: tab)
    }

    func openPopup(configuration: WKWebViewConfiguration, from opener: Tab) -> WKWebView? {
        let space = space(of: opener) ?? selectedSpace
        let tab = Tab(url: nil)
        let c = TabWebController(tab: tab, configuration: configuration, delegate: self)
        tab.controller = c
        withAnimation(Motion.snappy) {
            let i = space.tabs.firstIndex { $0 === opener }.map { $0 + 1 } ?? 0
            space.tabs.insert(tab, at: i)
        }
        select(tab)
        return c.webView
    }

    func tabDidClose(_ tab: Tab) { close(tab) }

    func tabDidFinishNavigation(_ tab: Tab) {
        if let url = tab.url { library.recordVisit(url: url, title: tab.title) }
        scheduleSave()
    }

    func tabTitleDidChange(_ tab: Tab) {
        if let url = tab.url { library.updateTitle(url: url, title: tab.title) }
    }
}
