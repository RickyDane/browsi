import AppKit
import Testing
@testable import Browsi

struct PinnedTabStateTests {
    @Test func closedPinnedTabDoesNotLookAsleep() {
        let pinned = Tab(url: URL(string: "https://example.com"), isPinned: true)
        #expect(pinned.isSuspended)
        #expect(!pinned.showsAsleep, "restored / ⌘W-closed pinned tabs look normal")
        pinned.snapshot = NSImage(size: NSSize(width: 1, height: 1))
        #expect(pinned.showsAsleep, "a pinned tab put to sleep by the suspender still shows it")
    }

    @Test func unloadedRegularTabLooksAsleep() {
        #expect(Tab(url: URL(string: "https://example.com")).showsAsleep)
    }
}
