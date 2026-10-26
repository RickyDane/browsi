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

    @Test(arguments: [false, true])
    func switchingAwayFromPlayingTabPopsOut(muted: Bool) async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        let videoTab = browser.newTab(url: nil)
        let webView = try #require(videoTab.controller?.webView)
        let host = WebViewHost.HostView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(host)
        host.attach(webView)
        let url = try fixtureURL()
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())

        let playing = await until { await webView.requestMediaPlaybackState() == .playing }
        try #require(playing, "fixture video never started playing")
        if muted { _ = try await webView.evaluateJavaScript("document.querySelector('video').muted = true") }

        let other = browser.newTab(url: URL(string: "about:blank"))
        browser.select(other) // a no-op selection must not cancel the outgoing video's handoff
        host.attach(try #require(other.controller?.webView)) // the real WebViewHost tab-switch path

        let floated = await until { browser.floatingPlayer.tab === videoTab }
        #expect(floated)
        #expect(videoTab.isInFloatingPlayer)
        #expect(webView.window != nil && webView.window !== window, "web view should live in the panel")
        #expect(await until(.seconds(2)) {
            (try? await webView.evaluateJavaScript("document.querySelector('video')?.paused === false")) as? Bool == true
        }, "the extracted video must actually be playing, not just report stale native playback state")

        // Only the video may be visible in the floating window — no masthead, controls or page.
        let extracted = await until(.seconds(3)) {
            (try? await webView.evaluateJavaScript(FloatingPlayer.isExtractedJS, contentWorld: .defaultClient)) as? Bool == true
        }
        #expect(extracted, "video must be extracted above all page content")

        browser.select(videoTab)
        host.attach(webView)
        #expect(!videoTab.isInFloatingPlayer)
        #expect(browser.floatingPlayer.tab == nil)
        #expect(await webView.requestMediaPlaybackState() == .playing, "returning must keep playback going")
        let restored = await until(.seconds(2)) {
            (try? await webView.evaluateJavaScript(
                "!document.querySelector('[data-browsi-float]') && !document.querySelector(':popover-open') && !document.getElementById('browsi-float-style')",
                contentWorld: .defaultClient)) as? Bool == true
        }
        #expect(restored, "page must be restored when the video returns to its tab")

        // A queued evaluation must not float or restyle the selected tab after a rapid return.
        browser.showHome()
        browser.select(videoTab)
        host.attach(webView)
        _ = try await webView.evaluateJavaScript("0", contentWorld: .defaultClient)
        #expect(browser.floatingPlayer.tab == nil)
        #expect(!videoTab.isInFloatingPlayer)
        #expect(try await webView.evaluateJavaScript(
            "!document.querySelector('[data-browsi-float]')", contentWorld: .defaultClient) as? Bool == true)

        // Stale cleanup must not restore the page after a newer attempt extracts it.
        browser.showHome()
        await Task.yield()
        browser.select(videoTab)
        host.attach(webView)
        browser.showHome()
        try #require(await until { browser.floatingPlayer.tab === videoTab })
        #expect(await until(.seconds(3)) {
            (try? await webView.evaluateJavaScript(FloatingPlayer.isExtractedJS, contentWorld: .defaultClient)) as? Bool == true
        })
        #expect(await until(.seconds(2)) {
            webView.window?.isVisible == true && (webView.window?.alphaValue ?? 0) > 0.99
        }, "an earlier close animation must not hide a reopened panel")
        browser.floatingPlayer.close(returnTo: nil)
        #expect(await until(.seconds(2)) { await webView.requestMediaPlaybackState() != .playing })
    }

    @Test func pausedVideoDoesNotPopOut() async throws {
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
        try #require(await until {
            (try? await webView.evaluateJavaScript("document.querySelector('video')?.readyState >= 2")) as? Bool == true
        })
        _ = try await webView.evaluateJavaScript("document.querySelector('video').pause()")
        browser.showHome()
        // Let the asynchronous extraction attempt finish before asserting its negative result.
        try await Task.sleep(for: .milliseconds(500))
        #expect(browser.floatingPlayer.tab == nil)
        #expect(try await webView.evaluateJavaScript(
            "!document.querySelector('[data-browsi-float]')", contentWorld: .defaultClient) as? Bool == true)
    }

    @Test func pendingMediaRefreshSurvivesTabRelease() async {
        var tab: Tab? = Tab(url: nil)
        let controller = TabWebController(tab: tab!, delegate: nil)
        let isReleased = { [weak tab] in tab == nil }
        controller.webView(controller.webView, didCommit: nil)
        tab = nil
        #expect(isReleased())
        // Regression: the deferred refresh captured a controller with an unowned, dead tab.
        await Task.yield()
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
