import Testing
import AppKit
import WebKit
@testable import Browsi

@MainActor
/// Live: a real relying party (webauthn.io) verifies Browsi passkey registration and sign-in.
struct WebAuthnIOLiveTests {
    @Test func registerAndAuthenticateOnWebAuthnIO() async throws {
        let prev = (PasskeyAuthenticator.store, PasskeyAuthenticator.verifyUser)
        PasskeyAuthenticator.store = PasskeyStore(service: "dev.perlick.browsi.passkey.probe")
        PasskeyAuthenticator.verifyUser = { _ in true }
        defer { PasskeyAuthenticator.store.deleteAll(); (PasskeyAuthenticator.store, PasskeyAuthenticator.verifyUser) = prev }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.orderFront(nil); defer { window.orderOut(nil) }
        let tab = Tab(url: nil)
        let c = TabWebController(tab: tab, delegate: nil)
        c.webView.frame = window.contentView!.bounds; window.contentView!.addSubview(c.webView)
        c.load(URL(string: "https://webauthn.io/")!)
        let end = ContinuousClock.now + .seconds(20)
        while (c.webView.isLoading || c.webView.url == nil), ContinuousClock.now < end { try? await Task.sleep(for: .milliseconds(100)) }
        let user = "browsi\(Int.random(in: 10000...99999))"
        let r = try await c.webView.callAsyncJavaScript("""
          const post = async (p, b) => { const r = await fetch(p, {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(b), credentials:'include'}); return [r.status, await r.json().catch(() => null)]; };
          const [s1, opts] = await post('/registration/options', { username: USER, user_verification: 'preferred', attestation: 'none', attachment: 'all', algorithms: ['es256'], discoverable_credential: 'preferred', hints: [] });
          const reg = await navigator.credentials.create({ publicKey: PublicKeyCredential.parseCreationOptionsFromJSON(opts) });
          const [s2, v1] = await post('/registration/verification', { username: USER, response: reg.toJSON() });
          const [s3, aopts] = await post('/authentication/options', { username: USER, user_verification: 'preferred' });
          const auth = await navigator.credentials.get({ publicKey: PublicKeyCredential.parseRequestOptionsFromJSON(aopts) });
          const [s4, v2] = await post('/authentication/verification', { username: USER, response: auth.toJSON() });
          return JSON.stringify({ s1, s2, v1, s3, s4, v2 });
        """, arguments: ["USER": user], contentWorld: .page)
        let json = r as? String ?? ""
        #expect(json.components(separatedBy: #""verified":true"#).count == 3, "webauthn.io verified both ceremonies: \(json)")
    }
}
