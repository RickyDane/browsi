import SwiftUI
import WebKit
import Observation
import UniformTypeIdentifiers
@preconcurrency import Translation

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
    /// Link Peek preview (⇧-click), shown as a modal over the content.
    var peek: PeekState?
    /// The Apple Intelligence page summary / Q&A panel beside the web content (⌘⇧S).
    var pageAssistantVisible = false
    /// `.summary` (⌘⇧S) summarizes the page on open; `.chat` (⌘⇧E) opens an empty chat about it.
    var pageAssistantMode: PageAssistantMode = .summary
    @ObservationIgnored private var pageAssistants: [UUID: PageAssistant] = [:]
    /// Find bar (⌘F / ⌘⇧F) for the selected tab.
    let find = FindInPage()
    /// A page action from the command palette (calendar, table, compare), shown as a sheet.
    var pageAction: PageActionRun?
    /// The "Watch This Page" sheet (new watch or editing one), if shown.
    var watchSetup: WatchSetup?
    @ObservationIgnored var pageTranslators: [UUID: PageTranslator] = [:]
    /// Drives the window's `.translationTask`; changing or invalidating it starts a translation.
    var translationConfig: TranslationSession.Configuration?
    @ObservationIgnored weak var translationTab: Tab?
    /// "Sign in with Apple" shown in a native sheet instead of the tab or a popup window.
    var appleSignIn: AppleSignInState?
    /// The page whose "Sign in with Apple" button was just clicked (its next popup goes into the sheet).
    @ObservationIgnored private var appleIntent: (webView: ObjectIdentifier, at: Date)?
    let floatingPlayer = FloatingPlayer()
    /// Files currently flying from the click position to the downloads button.
    var downloadFlights: [DownloadFlight] = []
    /// Global frame of the sidebar's downloads button (nil while hidden).
    var downloadsButtonFrame: CGRect?
    /// Downloads queue panel (drops down from the floating downloads button).
    var downloadsVisible = false
    /// The floating downloads button (top right). Hidden by default; appears on download activity.
    var downloadsButtonShown = false
    var downloadsHovering = false {
        didSet { if !downloadsHovering { scheduleDownloadsAutoHide() } }
    }
    @ObservationIgnored private var downloadsHideTask: Task<Void, Never>?
    static let downloadsIdleTimeout: Duration = .seconds(30)
    /// Bumped to ask the home page to focus its search bar (⌘L on the home page).
    var homeSearchFocusRequest = 0
    /// Bumped when a flight lands, to bounce the button.
    var downloadsBounce = 0
    @ObservationIgnored private var lastClick: (point: CGPoint, time: Date)?
    @ObservationIgnored private var clickMonitor: Any?
    /// Page-scoped Native Cipher authentication treatment.
    var calmRipple: CalmRipple?

    let library: LibraryStore
    /// The tab that was selected before the current one (⌃Tab switches back to it).
    @ObservationIgnored private weak var previousTab: Tab?
    @ObservationIgnored private var closedTabs: [(url: URL, spaceID: UUID)] = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private(set) var suspender: TabSuspender!

    init(library: LibraryStore = LibraryStore(), restore: Bool = true) {
        self.library = library
        if restore, let snap = SessionStore.load(), !snap.spaces.isEmpty {
            spaces = snap.spaces.map { s in
                Space(id: s.id, name: s.name, symbol: s.symbol, hue: s.hue,
                      pinnedTabs: s.pinned.map {
                          let t = Tab(id: $0.id, url: $0.url, title: $0.title, isPinned: true)
                          t.pinnedURL = $0.pinnedURL ?? $0.url
                          t.restoreFavicon()
                          return t
                      },
                      tabs: s.tabs.filter { $0.url != Tab.homeURL }.map {
                          let t = Tab(id: $0.id, url: $0.url, title: $0.title)
                          t.restoreFavicon()
                          return t
                      },
                      selectedTabID: nil)   // always launch on the home page
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
        floatingPlayer.browser = self
        LinkBridge.shared.browser = self
        PasskeyAuthenticator.onNotice = { [weak self] symbol, text in self?.showToast(symbol, text) }
        PasskeyAuthenticator.onCeremony = { [weak self] started in self?.passkeyCeremony(started: started) }
        LoginImpactBridge.shared.browser = self
        MediaPlaybackBridge.shared.browser = self
        AppleSignInBridge.shared.browser = self
        HomeWebCache.shared.browser = self
        WebConfigFactory.passwordBridge.onOfferSave = { [weak self] offer in
            withAnimation(.bouncy) { self?.pendingPasswordSave = offer }
        }
    }

    func start() {
        suspender.start()
        MiddleClickCloser.shared.install(browser: self)
        LiveTextClickThrough.shared.install()
        installClickTracker()
        installNavigationButtons()
        ExtensionManager.shared.start(browser: self)
        DownloadManager.shared.browser = self
        PageWatcher.shared.start(browser: self)
        Task {
            _ = await ContentBlocker.shared.load()
            for tab in allTabs { tab.controller?.applyContentBlocking() }
        }
        if let tab = selectedTab { activate(tab) }

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
            } else if Preferences.shared.newTabPosition == .bottom {
                space.tabs.append(tab)
            } else {
                space.tabs.insert(tab, at: 0)
            }
        }
        if background && !tab.isHome {
            tab.controller = TabWebController(tab: tab, delegate: self)
            if let url { tab.controller?.load(url) }
        } else {
            select(tab)
        }
        scheduleSave()
        return tab
    }

    /// `closingPrevious`: the tab being left is about to close, so don't snapshot it or pop its video out.
    func select(_ tab: Tab, closingPrevious: Bool = false) {
        let previous = selectedTab
        if tab.isInFloatingPlayer { floatingPlayer.close(returnTo: tab) }
        if previous === tab { return }
        floatingPlayer.cancelPendingPopOut()
        if peek?.tab !== tab { closePeek() }
        if let space = space(of: tab), space.id != selectedSpaceID { switchSpace(to: space) }
        if !closingPrevious, let old = previous?.controller?.webView, old.window != nil {
            // Grab a snapshot while still on-screen; used if the tab is later suspended.
            Task { previous?.snapshot = try? await old.takeSnapshot(configuration: nil) }
        }
        previous?.lastActive = .now
        if let previous { previousTab = previous }
        withAnimation(Motion.snappy) { space(of: tab)?.selectedTabID = tab.id }
        activate(tab)
        ExtensionManager.shared.didActivate(tab.controller, previous: previous?.controller)
        if !closingPrevious, let previous, previous !== tab { floatingPlayer.considerPopOut(previous) }
        scheduleSave()
    }

    /// Ensures the tab has a live web view (reviving it if suspended).
    func activate(_ tab: Tab) {
        tab.lastActive = .now
        guard tab.controller == nil, !tab.isHome else { return }
        let c = TabWebController(tab: tab, delegate: self)
        tab.controller = c
        c.restore(interactionState: tab.interactionState, fallback: tab.url)
        tab.interactionState = nil
        guard tab.snapshot != nil else { return }
        // Show the snapshot while reviving; drop it once the page has loaded (max ~3 s).
        tab.showsSnapshot = true
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            for _ in 0..<30 where tab.isLoading || tab.progress < 0.5 {
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 0.2)) { tab.showsSnapshot = false }
        }
    }

    /// Closes a tab. Pinned tabs stay pinned: they are unloaded and reset to their pinned address,
    /// unless `removePinned` is set.
    func close(_ tab: Tab, removePinned: Bool = false) {
        guard let space = space(of: tab) else { return }
        if tab.isPinned && !removePinned { unloadPinned(tab, in: space); return }
        if let url = tab.url { closedTabs.append((url, space.id)); closedTabs = closedTabs.suffix(30) }
        // Closed pinned tiles stay in the sidebar, but must not be reopened as a fallback.
        let ordered = space.allTabs.filter { $0 === tab || !$0.isPinned || !$0.isSuspended }
        let wasSelected = space.selectedTabID == tab.id
        let idx = ordered.firstIndex { $0 === tab } ?? 0
        // Pick the next tab *before* removing this one. Removing it first leaves `selectedTab` nil for one
        // animated transaction, so the content card flashes to the home page and rebuilds its web view host;
        // a web view re-attached during that rebuild stays blank.
        if wasSelected {
            let remaining = ordered.filter { $0 !== tab }
            let next = Preferences.shared.closeTabSelection == .recent
                ? remaining.max(by: { $0.lastActive < $1.lastActive })
                : remaining.isEmpty ? nil : remaining[min(idx, remaining.count - 1)]
            if let next {
                let keepPrevious = previousTab
                select(next, closingPrevious: true)
                previousTab = keepPrevious
            } else {
                withAnimation(Motion.snappy) { space.selectedTabID = nil }   // shows the home page
            }
        }
        withAnimation(Motion.snappy) {
            space.tabs.removeAll { $0 === tab }
            space.pinnedTabs.removeAll { $0 === tab }
        }
        if tab.isInFloatingPlayer { floatingPlayer.close(returnTo: nil) }
        if peek?.tab === tab { peek = nil }
        if appleSignIn?.tab === tab || appleSignIn?.source === tab { cancelAppleSignIn() }
        tab.controller?.tearDown()
        tab.controller = nil
        pageAssistants.removeValue(forKey: tab.id)?.reset()
        SmartTitleService.shared.forget(tab)
        scheduleSave()
    }

    private func unloadPinned(_ tab: Tab, in space: Space) {
        let wasSelected = space.selectedTabID == tab.id
        if tab.isInFloatingPlayer { floatingPlayer.close(returnTo: nil) }
        if peek?.tab === tab { peek = nil }
        if appleSignIn?.tab === tab || appleSignIn?.source === tab { cancelAppleSignIn() }
        tab.controller?.tearDown()
        tab.controller = nil
        tab.interactionState = nil
        tab.snapshot = nil
        tab.showsSnapshot = false
        tab.isLoading = false
        tab.progress = 0
        if let home = tab.pinnedURL { tab.url = home; tab.restoreFavicon() }
        if wasSelected {
            let others = space.allTabs.filter { $0 !== tab }
            let loaded = others.filter { !$0.isSuspended || !$0.isPinned }
            if let next = Preferences.shared.closeTabSelection == .recent
                ? loaded.max(by: { $0.lastActive < $1.lastActive })
                : (space.tabs.first ?? loaded.first) {
                select(next)
            } else {
                withAnimation(Motion.snappy) { space.selectedTabID = nil }
            }
        }
        scheduleSave()
    }

    /// Opens a link chosen on the home page: replaces the selected home tab, otherwise opens a tab.
    func openFromHome(_ url: URL, background: Bool = false) {
        newTab(url: url, background: background)
    }

    /// ⌘L: edit the address, or focus the home search bar when the home page is showing.
    func focusAddress() {
        if selectedTab == nil {
            palette = .hidden
            homeSearchFocusRequest += 1
        } else {
            palette = .editCurrent
        }
    }

    /// Shows the space's home page (deselects the current tab; the tab keeps running).
    func showHome() {
        let space = selectedSpace
        guard let previous = space.selectedTab else { return }
        floatingPlayer.cancelPendingPopOut()
        closePeek()
        if let old = previous.controller?.webView, old.window != nil {
            Task { previous.snapshot = try? await old.takeSnapshot(configuration: nil) }
        }
        previous.lastActive = .now
        previousTab = previous
        withAnimation(Motion.snappy) { space.selectedTabID = nil }
        floatingPlayer.considerPopOut(previous)
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
                tab.pinnedURL = tab.url
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

    /// ⌃Tab: switches back to the previously selected tab (repeating toggles between the last two).
    /// Falls back to the most recently active other tab if the previous one was closed.
    func selectPreviousTab() {
        let current = selectedTab
        let candidates = allTabs.filter { $0 !== current }
        let target = previousTab.flatMap { p in candidates.first { $0 === p } }
            ?? candidates.max { $0.lastActive < $1.lastActive }
        guard let target else { return }
        select(target)
    }

    // MARK: Navigation

    func open(input: String, inNewTab: Bool) {
        guard let url = URLInputParser.url(for: input, engine: Preferences.shared.searchEngine) else { return }
        open(url: url, inNewTab: inNewTab)
    }

    func open(url: URL, inNewTab: Bool) {
        if !inNewTab, let tab = selectedTab {
            navigate(tab, to: url)
        } else {
            newTab(url: url)
        }
    }

    /// Loads `url` in `tab`, creating its web view if needed (home tabs, suspended tabs).
    func navigate(_ tab: Tab, to url: URL) {
        if let controller = tab.controller {
            controller.load(url)
        } else {
            tab.url = url
            tab.title = ""
            tab.interactionState = nil
            tab.snapshot = nil
            activate(tab)
        }
        scheduleSave()
    }

    // MARK: Spaces

    func switchSpace(to space: Space) {
        guard space.id != selectedSpaceID else { return }
        floatingPlayer.cancelPendingPopOut()
        let from = spaces.firstIndex { $0.id == selectedSpaceID } ?? 0
        let to = spaces.firstIndex { $0.id == space.id } ?? 0
        spaceSwitchDirection = to >= from ? 1 : -1
        let previous = selectedTab
        previous?.lastActive = .now
        if let previous { previousTab = previous }
        closePeek()
        withAnimation(Motion.smooth) { selectedSpaceID = space.id }
        if let tab = space.selectedTab ?? space.allTabs.first {
            if tab.isInFloatingPlayer { floatingPlayer.close(returnTo: tab) }
            space.selectedTabID = tab.id
            activate(tab)
        }
        if let previous, previous !== selectedTab { floatingPlayer.considerPopOut(previous) }
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
    }

    func delete(space: Space) {
        guard spaces.count > 1 else { return }
        if space.id == selectedSpaceID {
            switchSpace(to: spaces.first { $0.id != space.id }!)
        }
        if let t = floatingPlayer.tab, space.allTabs.contains(where: { $0 === t }) { floatingPlayer.close(returnTo: nil) }
        space.allTabs.forEach { $0.controller?.tearDown(); $0.controller = nil }
        withAnimation(Motion.snappy) { spaces.removeAll { $0.id == space.id } }
        scheduleSave()
    }

    // MARK: Downloads button

    /// A download started/finished: show the button and restart the 30 s idle timer.
    func noteDownloadActivity() {
        if !downloadsButtonShown { withAnimation(Motion.bouncy) { downloadsButtonShown = true } }
        scheduleDownloadsAutoHide()
    }

    /// ⌘J: open the queue (showing the button) or close it and hide the button.
    func toggleDownloads() {
        if downloadsVisible {
            withAnimation(Motion.snappy) { downloadsVisible = false; downloadsButtonShown = false }
            downloadsHideTask?.cancel()
        } else {
            withAnimation(Motion.bouncy) { downloadsButtonShown = true; downloadsVisible = true }
        }
    }

    func closeDownloadsPanel() {
        withAnimation(Motion.snappy) { downloadsVisible = false }
        scheduleDownloadsAutoHide()
    }

    /// Hides the button after 30 s without activity. Never while downloading, open or hovered.
    func scheduleDownloadsAutoHide(after delay: Duration = BrowserState.downloadsIdleTimeout) {
        downloadsHideTask?.cancel()
        guard downloadsButtonShown else { return }
        downloadsHideTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            if DownloadManager.shared.activeCount > 0 || self.downloadsVisible || self.downloadsHovering {
                self.scheduleDownloadsAutoHide(after: delay)
                return
            }
            withAnimation(Motion.smooth) { self.downloadsButtonShown = false }
        }
    }

    // MARK: Download flights

    /// Remembers where the user last clicked in the browser window (top-left origin), so a download
    /// that starts shortly after can fly from there.
    private func installClickTracker() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .otherMouseDown, .rightMouseDown]) { [weak self] event in
            guard let window = event.window, !(window is NSPanel), let content = window.contentView else { return event }
            let p = CGPoint(x: event.locationInWindow.x, y: content.bounds.height - event.locationInWindow.y)
            MainActor.assumeIsolated { self?.lastClick = (p, .now) }
            return event
        }
    }

    func recordClick(at point: CGPoint) { lastClick = (point, .now) }

    // MARK: Mouse back/forward buttons

    @ObservationIgnored private var navButtonMonitor: Any?

    /// Thumb buttons (3 = back, 4 = forward) navigate the page under the pointer's context:
    /// the peek if open, otherwise the selected tab.
    private func installNavigationButtons() {
        guard navButtonMonitor == nil else { return }
        navButtonMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .otherMouseUp]) { [weak self] event in
            let button = event.buttonNumber
            guard button == 3 || button == 4 else { return event }
            if event.type == .otherMouseUp {
                MainActor.assumeIsolated { _ = self?.navigateHistory(forward: button == 4) }
            }
            return nil
        }
    }

    /// Returns false when there was nowhere to go.
    @discardableResult
    func navigateHistory(forward: Bool) -> Bool {
        guard let webView = peek?.tab.controller?.webView ?? selectedTab?.controller?.webView else { return false }
        if forward, webView.canGoForward { webView.goForward(); return true }
        if !forward, webView.canGoBack { webView.goBack(); return true }
        return false
    }

    func launchDownloadFlight(for fileName: String) {
        noteDownloadActivity()
        let from: CGPoint
        if let click = lastClick, Date.now.timeIntervalSince(click.time) < 10 {
            from = click.point
        } else if let size = NSApp.mainWindow?.contentView?.bounds.size {
            from = CGPoint(x: size.width / 2, y: size.height / 2)
        } else {
            from = CGPoint(x: 600, y: 400)
        }
        let type = UTType(filenameExtension: (fileName as NSString).pathExtension) ?? .data
        let icon = NSWorkspace.shared.icon(for: type)
        downloadFlights.append(DownloadFlight(from: from, icon: icon, fileName: fileName))
    }

    func landDownloadFlight(_ id: UUID) {
        downloadFlights.removeAll { $0.id == id }
        downloadsBounce += 1
    }

    // MARK: Login impact

    func playLoginImpact(_ kind: LoginImpact.Kind, at point: CGPoint, in webView: WKWebView) {
        guard Preferences.shared.loginImpactAnimation else { return }
        // "Sign in with Apple" and passkey buttons share the exact same cipher-grid wave.
        playCalmRipple(at: point, in: webView)
    }

    /// Passkey requests currently being handled by Browsi's authenticator.
    @ObservationIgnored private var activePasskeyCeremonies = 0

    /// One shallow page impact with a white grid that holds for the authentication ceremony.
    func playCalmRipple(at pagePoint: CGPoint, in webView: WKWebView) {
        guard let content = webView.window?.contentView,
              let tab = selectedTab, tab.controller?.webView === webView else { return }
        // Page coordinates (top-left) → window content coordinates (top-left).
        let flippedY = webView.isFlipped ? pagePoint.y : webView.bounds.height - pagePoint.y
        var p = webView.convert(CGPoint(x: pagePoint.x, y: flippedY), to: content)
        if !content.isFlipped { p.y = content.bounds.height - p.y }
        let ripple = CalmRipple(origin: p, tabID: tab.id, pageOrigin: pagePoint)
        calmRipple = ripple
        if !Motion.reduceMotion {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            Task { [weak self, weak webView] in
                guard let self, let webView else { return }
                let configuration = WKSnapshotConfiguration()
                configuration.afterScreenUpdates = false
                let snapshot = try? await webView.takeSnapshot(configuration: configuration)
                guard calmRipple?.id == ripple.id, selectedTab?.id == tab.id,
                      Date().timeIntervalSince(ripple.start) < NativeCipher.settlingDuration(origin: pagePoint, size: webView.bounds.size) else { return }
                calmRipple?.snapshot = snapshot
                do {
                    let duration = NativeCipher.settlingDuration(origin: pagePoint, size: webView.bounds.size)
                    try await Task.sleep(for: .seconds(max(0, duration - Date().timeIntervalSince(ripple.start))))
                    if calmRipple?.id == ripple.id { calmRipple?.snapshot = nil }
                } catch { /* The effect was replaced. */ }
            }
        }
        Task {
            // The button may not start a passkey request at all; then don't hold the grid.
            try? await Task.sleep(for: .seconds(CalmRipple.requestGrace))
            if calmRipple?.id == ripple.id, activePasskeyCeremonies == 0, appleSignIn == nil { releaseCalmRipple() }
            try? await Task.sleep(for: .seconds(CalmRipple.maximumHold))
            if calmRipple?.id == ripple.id { releaseCalmRipple() }
        }
    }

    /// Called when Browsi's passkey authenticator starts / finishes a request.
    func passkeyCeremony(started: Bool) {
        activePasskeyCeremonies = max(0, activePasskeyCeremonies + (started ? 1 : -1))
        if !started, activePasskeyCeremonies == 0, appleSignIn == nil { releaseCalmRipple() }
    }

    /// Fades the grid without triggering another impact or clearing ripple.
    func releaseCalmRipple() {
        guard let ripple = calmRipple, ripple.release == nil else { return }
        let at = max(Date(), ripple.start.addingTimeInterval(CalmRipple.minimumHold))
        calmRipple?.release = at
        Task {
            try? await Task.sleep(for: .seconds(at.timeIntervalSinceNow + CalmRipple.releaseDuration))
            if calmRipple?.id == ripple.id { calmRipple = nil }
        }
    }

    // MARK: Sign in with Apple

    /// Called when the user clicks a "Sign in with Apple" button on a page.
    func noteAppleSignInIntent(in webView: WKWebView) {
        appleIntent = (ObjectIdentifier(webView), .now)
    }

    private func hasRecentAppleIntent(_ tab: Tab) -> Bool {
        guard let intent = appleIntent, let webView = tab.controller?.webView,
              intent.webView == ObjectIdentifier(webView) else { return false }
        return Date.now.timeIntervalSince(intent.at) < 4
    }

    /// Sign in with Apple JS (`usePopup`) or a site's own Apple popup: host it in the sheet, not a tab.
    private func openAppleSignInPopup(configuration: WKWebViewConfiguration, for url: URL?, from opener: Tab) -> WKWebView? {
        guard Preferences.shared.appleSignInSheet, appleSignIn == nil,
              AppleSignIn.isAuthorizeURL(url) || hasRecentAppleIntent(opener) else { return nil }
        appleIntent = nil
        let tab = Tab(url: nil)
        let c = TabWebController(tab: tab, configuration: configuration, delegate: self)
        c.isPeek = true   // not a real tab: no history, no nested peeks
        tab.controller = c
        if selectedTab !== opener { select(opener) }
        withAnimation(Motion.bouncy) { appleSignIn = AppleSignInState(tab: tab, source: opener, mode: .popup) }
        return c.webView
    }

    func tab(_ tab: Tab, willNavigateMainFrameTo url: URL) async {
        if let sheet = appleSignIn, sheet.tab === tab {
            // In-place sign-in is done once the page heads back to the site (form_post / redirect).
            if sheet.mode == .inPlace, AppleSignIn.leavesApple(url) { endAppleSignIn() }
            return
        }
        guard Preferences.shared.appleSignInSheet, appleSignIn == nil, selectedTab === tab,
              tab.controller?.isPeek == false, AppleSignIn.isAuthorizeURL(url),
              let webView = tab.controller?.webView else { return }
        appleIntent = nil
        // Freeze the site as the backdrop before Apple's page replaces it.
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = false
        let background = try? await webView.takeSnapshot(configuration: config)
        guard appleSignIn == nil, selectedTab === tab else { return }
        withAnimation(Motion.bouncy) {
            appleSignIn = AppleSignInState(tab: tab, source: tab, mode: .inPlace, background: background)
        }
    }

    /// Sign-in finished: the sheet goes away (an in-place web view returns to the content card).
    func endAppleSignIn() {
        guard let sheet = appleSignIn else { return }
        withAnimation(Motion.snappy) { appleSignIn = nil }
        if activePasskeyCeremonies == 0 { releaseCalmRipple() }
        AppleSignInBridge.shared.sheetDidClose(sheet.id)
        if sheet.mode == .popup {
            let c = sheet.tab.controller
            Task {
                try? await Task.sleep(for: .milliseconds(400))   // let the dismiss transition finish
                c?.tearDown()
                sheet.tab.controller = nil
            }
        }
    }

    /// The user closed the sheet: tell the page sign-in was cancelled.
    func cancelAppleSignIn() {
        guard let sheet = appleSignIn else { return }
        let webView = sheet.tab.controller?.webView
        endAppleSignIn()
        switch sheet.mode {
        case .popup:
            // Closing from script lets Sign in with Apple JS see `popup.closed` and reject its promise.
            webView?.evaluateJavaScript("window.close()") { _, _ in }
        case .inPlace:
            if webView?.canGoBack == true { webView?.goBack() } else { webView?.stopLoading() }
        }
    }

    // MARK: Link Peek

    func closePeek() {
        guard let p = peek else { return }
        withAnimation(Motion.snappy) { peek = nil }
        // Silence right away; unload once the dismiss transition has finished.
        p.tab.controller?.silence()
        p.tab.controller?.webView.stopLoading()
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard self.peek?.tab !== p.tab, !self.allTabs.contains(where: { $0 === p.tab }) else { return }
            p.tab.controller?.tearDown()
            p.tab.controller = nil
        }
    }

    /// Turns the preview into a real tab next to the tab it was opened from.
    func promotePeek() {
        guard let p = peek else { return }
        let space = space(of: p.source) ?? selectedSpace
        p.tab.controller?.isPeek = false
        if let url = p.tab.url { library.recordVisit(url: url, title: p.tab.title) }
        peek = nil
        withAnimation(Motion.snappy) {
            let i = space.tabs.firstIndex { $0 === p.source }.map { $0 + 1 } ?? 0
            space.tabs.insert(p.tab, at: i)
        }
        select(p.tab)
    }

    // MARK: Library

    func toggleBookmarkForSelectedTab() {
        guard let tab = selectedTab, let url = tab.url else { return }
        let added = library.toggleBookmark(url: url, title: tab.displayTitle)
        showToast(added ? "star.fill" : "star.slash", added ? "Bookmarked" : "Bookmark removed")
    }

    /// Copies the tab's URL (the selected tab by default) to the pasteboard and confirms with a toast.
    func copyURL(of tab: Tab? = nil) {
        guard let url = (tab ?? selectedTab)?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        showToast("link", "Link copied")
    }

    // MARK: Page assistant

    /// Each tab keeps its own summary and conversation while it stays open.
    func pageAssistant(for tab: Tab) -> PageAssistant {
        if let a = pageAssistants[tab.id] { return a }
        let a = PageAssistant()
        pageAssistants[tab.id] = a
        return a
    }

    /// Opens the panel in `mode`; closes it if it is already open in that mode, else switches mode.
    func togglePageAssistant(_ mode: PageAssistantMode = .summary) {
        if pageAssistantVisible, pageAssistantMode == mode {
            closePageAssistant()
            return
        }
        pageAssistantMode = mode
        withAnimation(Motion.bouncy) { pageAssistantVisible = true }
    }

    func closePageAssistant() {
        withAnimation(Motion.bouncy) { pageAssistantVisible = false }
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
        guard !library.isInMemory else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveSessionNow()
        }
    }

    func saveSessionNow() {
        // Tests share the app's sandbox container; an in-memory library marks a non-persistent browser.
        guard !library.isInMemory else { return }
        func t(_ tab: Tab) -> SessionSnapshot.TabState {
            .init(id: tab.id, url: tab.url, title: tab.title, pinnedURL: tab.pinnedURL)
        }
        let snap = SessionSnapshot(spaces: spaces.map {
            .init(id: $0.id, name: $0.name, symbol: $0.symbol, hue: $0.hue,
                  pinned: $0.pinnedTabs.map(t), tabs: $0.tabs.map(t), selectedTabID: $0.selectedTabID)
        }, selectedSpaceID: selectedSpaceID)
        SessionStore.save(snap)
        library.saveNow()
    }
}

enum PasswordSaveChoice { case save, never, notNow }

struct PeekState: Identifiable {
    let tab: Tab
    let source: Tab
    var id: UUID { tab.id }
}

// MARK: - TabEventsDelegate

extension BrowserState: TabEventsDelegate {
    func openInNewTab(_ request: URLRequest, from tab: Tab, background: Bool) {
        guard let url = request.url else { return }
        newTab(url: url, in: space(of: tab), background: background, after: tab)
    }

    func openPopup(configuration: WKWebViewConfiguration, for url: URL?, from opener: Tab) -> WKWebView? {
        if let webView = openAppleSignInPopup(configuration: configuration, for: url, from: opener) { return webView }
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

    func tabDidClose(_ tab: Tab) {
        if appleSignIn?.tab === tab, appleSignIn?.mode == .popup { endAppleSignIn(); return }
        if peek?.tab === tab { closePeek() } else { close(tab) }
    }

    func peek(url: URL, from tab: Tab) {
        closePeek()
        let peekTab = Tab(url: url)
        let c = TabWebController(tab: peekTab, delegate: self)
        c.isPeek = true
        peekTab.controller = c
        c.load(url)
        withAnimation(Motion.bouncy) { peek = PeekState(tab: peekTab, source: tab) }
    }

    func tabDidFinishNavigation(_ tab: Tab) {
        if tab.controller?.isPeek == true { return }
        if let url = tab.url { library.recordVisit(url: url, title: tab.title) }
        if tab === selectedTab { find.pageChanged(tab); PageWatcher.shared.markSeen(tab.url) }
        detectLanguage(of: tab)
        scheduleSave()
    }

    func tabTitleDidChange(_ tab: Tab) {
        if let url = tab.url { library.updateTitle(url: url, title: tab.title) }
    }
}

struct DownloadFlight: Identifiable {
    let id = UUID()
    let from: CGPoint
    let icon: NSImage
    let fileName: String
}
