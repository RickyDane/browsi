import WebKit

/// Keeps `Tab.isPlayingMedia` current. Media events don't bubble, so an isolated-world script listens for
/// them in the capture phase (every frame) and pings Swift, which then asks WebKit for the page's real
/// playback state. Used to pause the animated window background while a video plays: redrawing the
/// full-window background behind a playing video makes the video stutter/flicker on large, high-refresh displays.
final class MediaPlaybackBridge: NSObject, WKScriptMessageHandler {
    static let shared = MediaPlaybackBridge()
    nonisolated static let handlerName = "browsiMedia"
    weak var browser: BrowserState?

    nonisolated static let source = """
    (() => {
      if (window.__browsiMedia) return; window.__browsiMedia = true;
      let pending = 0;
      const ping = () => { clearTimeout(pending); pending = setTimeout(() =>
        window.webkit.messageHandlers.\(handlerName).postMessage(0), 150); };
      for (const type of ['playing', 'pause', 'ended', 'emptied'])
        document.addEventListener(type, ping, true);
    })();
    """

    static let script = WKUserScript(source: source, injectionTime: .atDocumentStart,
                                     forMainFrameOnly: false, in: .defaultClient)

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let webView = message.webView,
              let tab = browser?.allTabs.first(where: { $0.controller?.webView === webView }) else { return }
        Task { await Self.refresh(tab, webView: webView) }
    }

    static func refresh(_ tab: Tab, webView: WKWebView) async {
        let playing = await webView.requestMediaPlaybackState() == .playing
        guard tab.controller?.webView === webView, tab.isPlayingMedia != playing else { return }
        tab.isPlayingMedia = playing
    }
}
