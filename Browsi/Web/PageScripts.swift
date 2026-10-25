import AppKit
import WebKit

/// JavaScript helpers shared by find, translation, page actions and page watching.
/// Everything runs in the isolated `.defaultClient` content world, so the page can't see or tamper with it.
enum PageScripts {
    /// The page's visible text (main content when the page marks it).
    static let mainTextJS = """
    const main = document.querySelector('article, main, [role=main]');
    const root = (main && main.innerText.trim().length > 600) ? main : document.body;
    return root ? root.innerText.slice(0, 120000) : '';
    """

    static func mainText(of webView: WKWebView) async -> String? {
        try? await webView.callAsyncJavaScript(mainTextJS, contentWorld: .defaultClient) as? String
    }

    static func mainText(of tab: Tab) async -> String? {
        guard let webView = tab.controller?.webView else { return nil }
        return await mainText(of: webView)
    }

    /// Finds `snippet` on the page, scrolls its block into the centre and draws a soft glow box around it.
    @discardableResult
    static func highlight(_ snippet: String, in webView: WKWebView, tint: NSColor) async -> Bool {
        let c = tint.usingColorSpace(.sRGB) ?? .systemBlue
        let rgb = "\(Int(c.redComponent * 255)),\(Int(c.greenComponent * 255)),\(Int(c.blueComponent * 255))"
        let js = """
        const old = document.getElementById('__browsi_glow'); if (old) old.remove();
        const sel = window.getSelection(); sel.removeAllRanges();
        if (!snippet || !window.find(snippet, false, false, true)) return false;
        const r = sel.rangeCount ? sel.getRangeAt(0) : null;
        if (!r) return false;
        const el = r.startContainer.nodeType === 1 ? r.startContainer : r.startContainer.parentElement;
        let target = el && el.closest('p,li,td,th,dd,dt,blockquote,pre,h1,h2,h3,h4,h5,h6,figcaption,tr') || el;
        let rect = target ? target.getBoundingClientRect() : r.getBoundingClientRect();
        if (rect.height > innerHeight * 0.6 || rect.width === 0) rect = r.getBoundingClientRect();
        const top = rect.top + scrollY, left = rect.left + scrollX;
        window.scrollTo({ top: Math.max(0, top - innerHeight / 2 + rect.height / 2), behavior: 'smooth' });
        const box = document.createElement('div');
        box.id = '__browsi_glow';
        Object.assign(box.style, {
          position: 'absolute', left: (left - 6) + 'px', top: (top - 4) + 'px',
          width: (rect.width + 12) + 'px', height: (rect.height + 8) + 'px',
          borderRadius: '8px', border: '2px solid rgba(' + rgb + ',0.85)',
          background: 'rgba(' + rgb + ',0.12)', boxShadow: '0 0 0 5px rgba(' + rgb + ',0.16)',
          pointerEvents: 'none', zIndex: '2147483647', transition: 'opacity .6s', opacity: '0'
        });
        document.documentElement.appendChild(box);
        requestAnimationFrame(() => { box.style.opacity = '1'; });
        return true;
        """
        let found = try? await webView.callAsyncJavaScript(js, arguments: ["snippet": snippet, "rgb": rgb],
                                                         contentWorld: .defaultClient)
        return found as? Bool ?? false
    }

    /// Removes the glow box and the selection left by find.
    static func clearHighlight(in webView: WKWebView) {
        let js = """
        const old = document.getElementById('__browsi_glow'); if (old) old.remove();
        window.getSelection().removeAllRanges();
        """
        Task { _ = try? await webView.callAsyncJavaScript(js, contentWorld: .defaultClient) }
    }

    /// Case-insensitive number of occurrences of `query` in the page's visible text.
    static func countMatches(_ query: String, in webView: WKWebView) async -> Int {
        let js = """
        const text = (document.body ? document.body.innerText : '').toLowerCase();
        const q = query.toLowerCase();
        if (!q) return 0;
        let n = 0, i = 0;
        while ((i = text.indexOf(q, i)) !== -1 && n < 9999) { n++; i += q.length; }
        return n;
        """
        let n = try? await webView.callAsyncJavaScript(js, arguments: ["query": query], contentWorld: .defaultClient)
        return (n as? Int) ?? (n as? NSNumber)?.intValue ?? 0
    }
}
