import AppKit

/// Closes the tab under the pointer on a middle-mouse click.
/// SwiftUI has no middle-click gesture, so tab views report hover and one app-wide monitor acts on it.
final class MiddleClickCloser {
    static let shared = MiddleClickCloser()
    private(set) var hoveredTabID: UUID?
    private var monitor: Any?
    private var downOnTab: UUID?

    func hover(_ id: UUID, _ inside: Bool) {
        if inside { hoveredTabID = id } else if hoveredTabID == id { hoveredTabID = nil }
    }

    func install(browser: BrowserState) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .otherMouseUp]) { [weak self, weak browser] event in
            let isMiddle = event.buttonNumber == 2
            let isUp = event.type == .otherMouseUp
            let x = event.locationInWindow.x
            let consumed = MainActor.assumeIsolated {
                guard let self, let browser else { return false }
                return self.handle(isMiddle: isMiddle, isUp: isUp, x: x, browser: browser)
            }
            return consumed ? nil : event
        }
    }

    /// Returns true when the event was used to close a tab.
    func handle(isMiddle: Bool, isUp: Bool, x: CGFloat, browser: BrowserState) -> Bool {
        // Only over the sidebar (guards against a stale hover id when the pointer is over a page).
        guard isMiddle, let id = hoveredTabID, x <= Preferences.shared.sidebarWidth + 16 else { return false }
        if !isUp { downOnTab = id; return true }
        // Require press and release on the same tab, like a normal click.
        defer { downOnTab = nil }
        guard downOnTab == id, let tab = browser.allTabs.first(where: { $0.id == id }) else { return false }
        hoveredTabID = nil
        browser.close(tab)
        return true
    }
}
