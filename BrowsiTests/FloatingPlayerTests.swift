import Testing
import AppKit
import WebKit
@testable import Browsi

private final class BundleToken {}

/// End-to-end: a real WKWebView in a real window plays a video with sound,
/// then switching tabs must move it into the floating panel.
@MainActor
@Suite(.serialized)
struct FloatingPlayerTests {
    private func until(_ timeout: Duration = .seconds(8), _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private func fixtureURL() throws -> URL {
        try #require(Bundle(for: BundleToken.self).url(forResource: "video", withExtension: "html"))
    }

    @Test func switchingAwayFromPlayingTabPopsOut() async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        let videoTab = browser.newTab(url: nil)
        let webView = try #require(videoTab.controller?.webView)
        webView.frame = window.contentView!.bounds
        window.contentView!.addSubview(webView)
        let url = try fixtureURL()
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())

        let playing = await until { await webView.requestMediaPlaybackState() == .playing }
        try #require(playing, "fixture video never started playing")

        browser.newTab(url: URL(string: "about:blank"))   // selects the new tab → previous should float
        webView.removeFromSuperview()                      // what WebViewHost does on tab switch

        let floated = await until { browser.floatingPlayer.tab === videoTab }
        #expect(floated)
        #expect(videoTab.isInFloatingPlayer)
        #expect(webView.window != nil && webView.window !== window, "web view should live in the panel")

        // Only the video may be visible in the floating window — no masthead, controls or page.
        let extracted = await until(.seconds(3)) {
            (try? await webView.evaluateJavaScript(FloatingPlayer.isExtractedJS, contentWorld: .defaultClient)) as? Bool == true
        }
        #expect(extracted, "video must be extracted above all page content")

        browser.select(videoTab)
        #expect(!videoTab.isInFloatingPlayer)
        #expect(browser.floatingPlayer.tab == nil)
        #expect(await webView.requestMediaPlaybackState() == .playing, "returning must keep playback going")
        let restored = await until(.seconds(2)) {
            (try? await webView.evaluateJavaScript(
                "!document.querySelector('[data-browsi-float]') && !document.querySelector(':popover-open') && !document.getElementById('browsi-float-style')",
                contentWorld: .defaultClient)) as? Bool == true
        }
        #expect(restored, "page must be restored when the video returns to its tab")
    }

    /// Regression: media in a closed Link Peek kept playing.
    @Test func closingPeekStopsMedia() async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        let source = browser.newTab(url: URL(string: "about:blank"))
        browser.peek(url: URL(string: "about:blank")!, from: source)
        let peekTab = try #require(browser.peek?.tab)
        let webView = try #require(peekTab.controller?.webView)
        webView.frame = window.contentView!.bounds
        window.contentView!.addSubview(webView)
        let url = try fixtureURL()
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        try #require(await until { await webView.requestMediaPlaybackState() == .playing })

        browser.closePeek()
        #expect(await until(.seconds(2)) { await webView.requestMediaPlaybackState() != .playing },
                "media must stop as soon as the peek closes")
        #expect(await until(.seconds(2)) { peekTab.controller == nil })
    }

    /// Clicking another tab while a peek is open must also stop it.
    @Test func selectingTabDismissesAndSilencesPeek() async throws {
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        let a = browser.newTab(url: URL(string: "about:blank"))
        let b = browser.newTab(url: URL(string: "about:blank#b"))
        browser.peek(url: URL(string: "about:blank#peek")!, from: b)
        let peekTab = try #require(browser.peek?.tab)
        browser.select(a)
        #expect(browser.peek == nil)
        #expect(await until(.seconds(2)) { peekTab.controller == nil })
    }
}
