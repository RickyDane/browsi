import AppKit
import WebKit

/// "Sign in with Apple" on websites.
///
/// Safari's Touch ID sheet for website Apple sign-in relies on private Apple entitlements, so no
/// third-party browser can mint a site's Apple token natively. Browsi gets as close as the public
/// APIs allow: Apple's authorize page never takes over the tab or opens a popup window. It is shown
/// in a native glass sheet over the dimmed site, and the Apple ID saved in Browsi's keychain is
/// filled in after Touch ID or the login password (system dialog via `BiometricGate`).
nonisolated enum AppleSignIn {
    /// Hosts that serve Apple's sign-in UI. While the sheet's page stays on these, the sheet stays open.
    static func isAppleHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "apple.com" || host.hasSuffix(".apple.com")
    }

    /// The Sign in with Apple authorization endpoint (`/auth/authorize` on appleid/account.apple.com).
    static func isAuthorizeURL(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https",
              let host = url.host()?.lowercased() else { return false }
        return ["appleid.apple.com", "account.apple.com"].contains(host) && url.path.hasPrefix("/auth/authorize")
    }

    /// Frames allowed to receive the Apple ID secret (Apple's sign-in widget and its host page).
    static let fillHosts: Set<String> = ["idmsa.apple.com", "appleid.apple.com", "account.apple.com"]

    /// Keychain servers an Apple ID may be saved under (imports from Passwords use different ones).
    static let credentialHosts = ["idmsa.apple.com", "appleid.apple.com", "account.apple.com",
                                  "apple.com", "www.apple.com", "icloud.com", "www.icloud.com"]

    /// A main-frame navigation that leaves Apple's sign-in (e.g. the form_post back to the site).
    static func leavesApple(_ url: URL?) -> Bool {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return !isAppleHost(url.host())
    }
}

/// The Apple sign-in sheet currently shown over a tab.
struct AppleSignInState: Identifiable {
    enum Mode {
        /// The page opened Apple in a popup (Sign in with Apple JS `usePopup`): the popup's web view
        /// lives only in the sheet and closes itself after posting the result to its opener.
        case popup
        /// The tab itself navigated to Apple: its own web view moves into the sheet (cookies,
        /// the form_post callback and history stay intact) and returns to the card when it leaves Apple.
        case inPlace
    }

    let id = UUID()
    /// The tab whose web view is shown in the sheet.
    let tab: Tab
    /// The tab under the sheet (same as `tab` for `.inPlace`).
    let source: Tab
    let mode: Mode
    /// The site as it looked when sign-in started, shown dimmed under the sheet (`.inPlace` only).
    var background: NSImage?
    /// An Apple ID is saved, so the sheet offers "Fill with Touch ID".
    var canFill = false
    var isFilling = false
}

/// Fills the saved Apple ID into Apple's sign-in widget after Touch ID / the login password.
/// Runs in the isolated `.defaultClient` world and answers only Apple identity frames that are
/// shown in the sign-in sheet.
final class AppleSignInBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let shared = AppleSignInBridge()
    static let handlerName = "browsiAppleID"
    weak var browser: BrowserState?
    /// The frame holding Apple's account field, per sheet, so the sheet's button can start a fill.
    private var readyFrame: (sheet: UUID, frame: WKFrameInfo)?
    /// Sheets that already prompted automatically (once per sheet; the button can retry).
    private var autoPrompted: Set<UUID> = []

    nonisolated static let source = """
    (() => {
      if (window.__browsiAppleID) return; window.__browsiAppleID = true;
      if (location.protocol !== 'https:' || !/(^|\\.)(idmsa|appleid|account)\\.apple\\.com$/.test(location.hostname)) return;
      const bridge = window.webkit.messageHandlers.browsiAppleID;
      const visible = el => !!(el && el.offsetParent !== null && !el.disabled && !el.readOnly);
      const q = sel => [...document.querySelectorAll(sel)].find(visible);
      const ACCOUNT = '#account_name_text_field, input[autocomplete~="username"], input[type="email"]';
      const PASSWORD = '#password_text_field, input[type="password"]';
      const sleep = ms => new Promise(r => setTimeout(r, ms));
      const waitFor = async (sel, ms) => {
        for (const end = Date.now() + ms; Date.now() < end; await sleep(150)) { const el = q(sel); if (el) return el; }
        return null;
      };
      const setValue = (el, v) => {
        el.focus();
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(el, v);
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
      };
      const submit = el => {
        const button = q('#sign-in, button[type="submit"]');
        if (button) { button.click(); return; }
        if (el.form && el.form.requestSubmit) { el.form.requestSubmit(); return; }
        for (const type of ['keydown', 'keypress', 'keyup'])
          el.dispatchEvent(new KeyboardEvent(type, { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true }));
      };
      let busy = false;
      const run = async manual => {
        if (busy) return; busy = true;
        try {
          const account = q(ACCOUNT); if (!account) return;
          let cred; try { cred = await bridge.postMessage({ type: manual ? 'fill' : 'ready' }); } catch { return; }
          if (!cred || !cred.username) return;
          setValue(account, cred.username);
          let password = q(PASSWORD);
          if (!password) { await sleep(80); submit(account); password = await waitFor(PASSWORD, 15000); }
          if (!password) return;
          setValue(password, cred.password);
          await sleep(120);
          submit(password);
        } finally { busy = false; }
      };
      window.__browsiAppleFill = () => run(true);
      waitFor(ACCOUNT, 30000).then(el => { if (el) run(false); });
    })();
    """

    static let script = WKUserScript(source: source, injectionTime: .atDocumentEnd,
                                     forMainFrameOnly: false, in: .defaultClient)

    /// The saved Apple ID (username only), if any.
    func savedAccount() -> Credential? {
        let store = WebConfigFactory.passwordBridge.keychain
        for host in AppleSignIn.credentialHosts {
            if let c = store.accounts(host: host).first { return c }
        }
        return nil
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        let origin = message.frameInfo.securityOrigin
        guard origin.protocol == "https", AppleSignIn.fillHosts.contains(origin.host.lowercased()),
              let browser, let sheet = browser.appleSignIn,
              let webView = message.webView, sheet.tab.controller?.webView === webView,
              let type = (message.body as? [String: Any])?["type"] as? String else {
            replyHandler(nil, nil); return
        }
        let account = Preferences.shared.autofillPasswords ? savedAccount() : nil
        browser.appleSignIn?.canFill = account != nil
        guard let account else { replyHandler(nil, nil); return }

        switch type {
        case "ready":
            readyFrame = (sheet.id, message.frameInfo)
            guard !autoPrompted.contains(sheet.id) else { replyHandler(nil, nil); return }
            autoPrompted.insert(sheet.id)
            fill(account, sheet: sheet.id, replyHandler: replyHandler)
        case "fill":
            fill(account, sheet: sheet.id, replyHandler: replyHandler)
        default:
            replyHandler(nil, nil)
        }
    }

    private func fill(_ account: Credential, sheet: UUID,
                      replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard let browser else { replyHandler(nil, nil); return }
        browser.appleSignIn?.isFilling = true
        Task {
            defer { if browser.appleSignIn?.id == sheet { browser.appleSignIn?.isFilling = false } }
            let ok = await BiometricGate.shared.authenticate(reason: "sign in with your Apple ID", force: true)
            // The sheet may have been closed while the system dialog was up.
            guard ok, browser.appleSignIn?.id == sheet,
                  let password = try? WebConfigFactory.passwordBridge.keychain.password(host: account.host,
                                                                                       username: account.username)
            else { replyHandler(nil, nil); return }
            replyHandler(["username": account.username, "password": password], nil)
        }
    }

    /// "Fill with Touch ID" in the sheet: asks Apple's widget to request the credentials again.
    func fillFromSheet() {
        guard let sheet = browser?.appleSignIn, let ready = readyFrame, ready.sheet == sheet.id,
              let webView = sheet.tab.controller?.webView else { return }
        webView.evaluateJavaScript("window.__browsiAppleFill && window.__browsiAppleFill(); 0",
                                   in: ready.frame, in: .defaultClient) { _ in }
    }

    func sheetDidClose(_ id: UUID) {
        autoPrompted.remove(id)
        if readyFrame?.sheet == id { readyFrame = nil }
    }
}
