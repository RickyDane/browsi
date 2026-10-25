import WebKit

/// WebKit delivers middle-clicks to the page (`auxclick`) but never turns them into a navigation,
/// so a tiny isolated-world script reports trusted middle-clicks on links and we open a tab.
final class LinkBridge: NSObject, WKScriptMessageHandler {
    static let shared = LinkBridge()
    static let handlerName = "browsiLinks"
    weak var browser: BrowserState?

    static let script = WKUserScript(source: """
    (() => {
      if (window.__browsiLinks) return; window.__browsiLinks = true;
      const post = m => window.webkit.messageHandlers.\(handlerName).postMessage(m);
      const linkFor = e => {
        const a = e.composedPath ? e.composedPath().find(n => n instanceof HTMLAnchorElement && n.href) : e.target.closest?.('a[href]');
        return a && /^https?:/i.test(a.href) ? a : null;
      };
      // Stop the page from treating the middle-press as a drag/scroll start on links.
      addEventListener('mousedown', e => { if (e.button === 1 && e.isTrusted && linkFor(e)) e.preventDefault(); }, true);
      addEventListener('auxclick', e => {
        if (e.button !== 1 || !e.isTrusted) return;
        const a = linkFor(e); if (!a) return;
        e.preventDefault(); e.stopPropagation();
        post({ href: a.href, shift: e.shiftKey });
      }, true);
    })();
    """, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient)

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let browser, let body = message.body as? [String: Any],
              let href = body["href"] as? String, let url = URL(string: href),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let webView = message.webView else { return }
        let source = browser.allTabs.first { $0.controller?.webView === webView }
            ?? (browser.peek?.tab.controller?.webView === webView ? browser.peek?.tab : nil)
        guard let source else { return }
        let shift = body["shift"] as? Bool ?? false
        let background = Preferences.shared.commandClickOpensInBackground != shift
        var request = URLRequest(url: url)
        if let referer = webView.url?.absoluteString { request.setValue(referer, forHTTPHeaderField: "Referer") }
        browser.openInNewTab(request, from: source, background: background)
    }
}
