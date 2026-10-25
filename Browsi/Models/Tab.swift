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
    var lastActive = Date()
    var zoom: Double = 1

    /// Snapshot shown while a suspended tab is waking up.
    var snapshot: NSImage?
    /// Back/forward list + scroll position saved when suspending.
    @ObservationIgnored var interactionState: Any?
    var controller: TabWebController?

    var isSuspended: Bool { controller == nil }

    var displayTitle: String {
        if !title.isEmpty { return title }
        return url?.host() ?? "New Tab"
    }

    init(id: UUID = UUID(), url: URL?, title: String = "", isPinned: Bool = false) {
        self.id = id
        self.url = url
        self.title = title
        self.isPinned = isPinned
    }
}
