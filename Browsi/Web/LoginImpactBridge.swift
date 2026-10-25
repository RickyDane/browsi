import AppKit
import WebKit

/// Detects clicks on "Sign in with Apple" and passkey buttons (isolated world, trusted clicks only)
/// and asks the browser to play the wave-impact animation.
final class LoginImpactBridge: NSObject, WKScriptMessageHandler {
    static let shared = LoginImpactBridge()
    static let handlerName = "browsiImpact"
    weak var browser: BrowserState?

    nonisolated static let source = """
    (() => {
      if (window.__browsiImpact) return; window.__browsiImpact = true;
      const APPLE = /\\b(sign|log)\\s*(in|on|up)\\s*(with|via|using)\\s*apple\\b|\\bcontinue\\s*with\\s*apple\\b|mit\\s*apple\\s*(anmelden|fortfahren|einloggen|registrieren)|\\bappleid[-_ ]?sign|sign[-_ ]?in[-_ ]?with[-_ ]?apple|\\bapple[-_ ]?(sign[-_ ]?in|login|auth)\\b/i;
      const PASSKEY = /pass\\s?-?keys?\\b|passkey|passschl[üu]ssel|security\\s*key|sicherheitsschl[üu]ssel|webauthn/i;
      const CLICKABLE = 'button, a[href], [role="button"], input[type="submit"], input[type="button"], #appleid-signin';
      const describe = el => {
        const text = (el.innerText || '').trim();
        const parts = [text.length <= 120 ? text : '', el.value, el.getAttribute('aria-label'), el.title, el.id,
          typeof el.className === 'string' ? el.className : '', el.getAttribute('data-provider'), el.name,
          ...[...el.querySelectorAll('img[alt], [aria-label]')].slice(0, 5).map(n => n.getAttribute('alt') || n.getAttribute('aria-label'))];
        return parts.filter(Boolean).join(' ').slice(0, 400);
      };
      const classify = el => { const t = describe(el); return APPLE.test(t) ? 'apple' : PASSKEY.test(t) ? 'passkey' : null; };
      window.__browsiClassify = classify;
      let last = 0;
      addEventListener('click', e => {
        if (!e.isTrusted) return;
        const path = e.composedPath ? e.composedPath() : [e.target];
        const el = path.find(n => n instanceof Element && n.matches(CLICKABLE));
        if (!el) return;
        const kind = classify(el); if (!kind) return;
        const now = Date.now(); if (now - last < 500) return; last = now;
        const r = el.getBoundingClientRect();
        window.webkit.messageHandlers.browsiImpact.postMessage({
          kind, pointer: e.detail > 0, cx: e.clientX, cy: e.clientY,
          x: r.left + r.width / 2, y: r.top + r.height / 2, w: r.width, h: r.height });
      }, true);
    })();
    """

    static let script = WKUserScript(source: source, injectionTime: .atDocumentStart,
                                     forMainFrameOnly: false, in: .defaultClient)

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let browser, let webView = message.webView,
              let body = message.body as? [String: Any],
              let kind = (body["kind"] as? String).flatMap(LoginImpact.Kind.init(rawValue:)) else { return }
        if kind == .passkey { PasskeySupport.shared.userIntendsToUsePasskey(browser: browser) }
        guard browser.selectedTab?.controller?.webView === webView else { return }

        // Where to center the wave (web view coordinates, top-left origin).
        var point = CGPoint(x: webView.bounds.midX, y: webView.bounds.midY)
        var buttonSize = CGSize(width: 220, height: 44)
        if let w = body["w"] as? Double, let h = body["h"] as? Double {
            let scale = webView.pageZoom * webView.magnification
            buttonSize = CGSize(width: w * scale, height: h * scale)
        }
        let scale = webView.pageZoom * webView.magnification
        let pointer = body["pointer"] as? Bool == true
        if message.frameInfo.isMainFrame {
            // Exact page coordinates: the click itself, or the button centre for keyboard activation.
            let (kx, ky) = pointer ? ("cx", "cy") : ("x", "y")
            if let x = body[kx] as? Double, let y = body[ky] as? Double {
                point = CGPoint(x: x * scale, y: y * scale)
            }
        } else if pointer, let window = webView.window {
            // Inside an iframe the frame offset is unknown; use where the cursor is.
            let p = webView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if webView.bounds.contains(p) {
                point = CGPoint(x: p.x, y: webView.isFlipped ? p.y : webView.bounds.height - p.y)
            }
        }
        browser.playLoginImpact(kind, at: point, buttonSize: buttonSize, in: webView)
    }
}

struct LoginImpact: Identifiable {
    enum Kind: String { case apple, passkey }
    let id = UUID()
    let kind: Kind
    let origin: CGPoint
    let buttonSize: CGSize
    let start = Date()
    var snapshot: NSImage?
}
