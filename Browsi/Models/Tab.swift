import AppKit
import Observation

/// A single browser tab. The `controller` (and its WKWebView) is nil while the tab is suspended.
@Observable
final class Tab: Identifiable {
    let id: UUID
    var url: URL?
    var title: String
    var favicon: NSImage?
    var isLoading = false
    var progress: Double = 0
    var canGoBack = false
    var canGoForward = false
    var isSecure = false
    var isPinned: Bool
    /// The address a pinned tab returns to when it is closed (⌘W keeps pinned tabs, unloaded).
    var pinnedURL: URL?
    /// True while the tab's web view lives in the floating video window.
    var isInFloatingPlayer = false
    /// True while a page element (e.g. a video) is in fullscreen: WebKit has moved the web view into
    /// its own fullscreen window and will put it back itself on exit.
    var isInElementFullscreen = false
    /// True while the page plays audio/video (kept current by `MediaPlaybackBridge`).
    var isPlayingMedia = false
    var lastActive = Date()
    var zoom: Double = Preferences.shared.defaultZoom
    /// Shortened title for the sidebar (Smart Tab Titles); nil when the real title is short enough.
    var smartTitle: String?

    /// Snapshot shown while a suspended tab is waking up.
    var snapshot: NSImage?
    /// True while a revived tab is still painting and the snapshot covers it.
    var showsSnapshot = false
    /// Back/forward list + scroll position saved when suspending.
    @ObservationIgnored var interactionState: Any?
    var controller: TabWebController?

    var isSuspended: Bool { controller == nil }
    /// Shown as sleeping (dimmed / moon). A pinned tab without a web view is simply closed
    /// (after ⌘W or an app restart) and looks normal; it only sleeps when the suspender put it to sleep.
    var showsAsleep: Bool { controller == nil && (!isPinned || snapshot != nil) }

    /// Internal address of the Browsi home page.
    static let homeURL = URL(string: "browsi:home")!
    var isHome: Bool { url == Tab.homeURL }

    /// Shows the last known favicon for the tab's site while it isn't loaded (e.g. after a relaunch).
    func restoreFavicon() {
        if let host = url?.host(), let icon = FaviconLoader.shared.cached(host: host) { favicon = icon }
    }

    var displayTitle: String {
        if isHome { return "Home" }
        if !title.isEmpty { return title }
        return url?.host() ?? "New Tab"
    }

    /// Title shown in the sidebar: the smart title when enabled, otherwise the page title.
    var sidebarTitle: String {
        guard Preferences.shared.smartTabTitles, !isHome, let smartTitle, !title.isEmpty else { return displayTitle }
        return smartTitle
    }

    init(id: UUID = UUID(), url: URL?, title: String = "", isPinned: Bool = false) {
        self.id = id
        self.url = url
        self.title = title
        self.isPinned = isPinned
    }
}
