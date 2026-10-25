import Testing
import AppKit
import WebKit
import VisionKit
@testable import Browsi

@MainActor
struct LiveTextClickThroughTests {
    /// The real VisionKit overlay WebKit installs over a paused fullscreen video.
    private func makeOverlay() throws -> NSView {
        _ = ImageAnalysisOverlayView.self   // loads VisionKit's private classes
        let cls = try #require(NSClassFromString("VKCImageAnalysisOverlayView") as? NSView.Type)
        return cls.init(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
    }

    @Test func findsOverlayHostedByWebView() throws {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let overlay = try makeOverlay()
        let inner = NSView(frame: overlay.bounds)
        overlay.addSubview(inner)
        webView.addSubview(overlay)
        #expect(LiveTextClickThrough.isLiveTextOverlay(overlay))
        #expect(LiveTextClickThrough.liveTextOverlay(containing: inner) === overlay)
        #expect(LiveTextClickThrough.liveTextOverlay(containing: overlay) === overlay)
        #expect(LiveTextClickThrough.liveTextOverlay(containing: webView) == nil)
    }

    @Test func ignoresOverlayOutsideWebViewAndOrdinaryViews() throws {
        let container = NSView()
        let overlay = try makeOverlay()
        container.addSubview(overlay)
        #expect(LiveTextClickThrough.liveTextOverlay(containing: overlay) == nil)
        #expect(!LiveTextClickThrough.isLiveTextOverlay(NSView()))
    }

    /// The Live Text button must stay clickable, which relies on it being an NSControl.
    @Test func liveTextButtonIsAControl() throws {
        _ = ImageAnalysisOverlayView.self
        let cls: AnyClass = try #require(NSClassFromString("VKImageAnalysisButton"))
        #expect(cls is NSControl.Type)
    }
}

@MainActor
struct MediaPlaybackBridgeTests {
    @Test func scriptWatchesMediaEventsInEveryFrame() {
        let script = MediaPlaybackBridge.script
        #expect(!script.isForMainFrameOnly)
        #expect(script.injectionTime == .atDocumentStart)
        for event in ["playing", "pause", "ended", "emptied"] { #expect(script.source.contains("'\(event)'")) }
        #expect(script.source.contains(MediaPlaybackBridge.handlerName))
    }

    @Test func newTabIsNotPlaying() {
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        #expect(!browser.newTab(url: URL(string: "about:blank")).isPlayingMedia)
    }
}
