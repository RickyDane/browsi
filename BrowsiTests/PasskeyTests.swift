import Testing
import Foundation
import AppKit
import CryptoKit
import WebKit
@testable import Browsi

struct WebAuthnFormatTests {
    @Test func rpIDRules() {
        #expect(WebAuthn.validRPID("github.com", for: "github.com"))
        #expect(WebAuthn.validRPID("google.com", for: "accounts.google.com"))
        #expect(!WebAuthn.validRPID("evil.com", for: "github.com"))
        #expect(!WebAuthn.validRPID("com", for: "github.com"))
        #expect(!WebAuthn.validRPID("github.io", for: "me.github.io"))
        #expect(!WebAuthn.validRPID("ub.com", for: "github.com"), "suffix must be on a label boundary")
    }

    @Test func clientDataIsSpecOrdered() {
        let json = String(decoding: WebAuthn.clientDataJSON(type: "webauthn.get", challenge: Data([1, 2, 3]),
                                                             origin: "https://example.com"), as: UTF8.self)
        #expect(json == #"{"type":"webauthn.get","challenge":"AQID","origin":"https://example.com","crossOrigin":false}"#)
    }

    @Test func coseKeyLayout() {
        let cose = WebAuthn.coseKey(P256.Signing.PrivateKey().publicKey)
        #expect(cose.count == 77)
        #expect(Array(cose.prefix(7)) == [0xA5, 0x01, 0x02, 0x03, 0x26, 0x20, 0x01])
        #expect(Array(cose[7...9]) == [0x21, 0x58, 0x20])
    }

    @Test func originSerialisation() {
        #expect(WebOrigin(scheme: "https", host: "a.com", port: 0).serialized == "https://a.com")
        #expect(WebOrigin(scheme: "https", host: "a.com", port: 443).serialized == "https://a.com")
        #expect(WebOrigin(scheme: "http", host: "localhost", port: 3000).serialized == "http://localhost:3000")
        #expect(!WebOrigin(scheme: "http", host: "a.com", port: 0).isSecure)
    }
}

@MainActor
@Suite(.serialized)
struct PasskeyCeremonyTests {
    let origin = WebOrigin(scheme: "https", host: "login.example.com", port: 0)

    private func withTestStore(approve: Bool = true, _ body: () async throws -> Void) async rethrows {
        let previous = (PasskeyAuthenticator.store, PasskeyAuthenticator.verifyUser)
        PasskeyAuthenticator.store = PasskeyStore(service: "dev.perlick.browsi.passkey.tests.\(UUID().uuidString.prefix(8))")
        PasskeyAuthenticator.verifyUser = { _ in approve }
        defer {
            PasskeyAuthenticator.store.deleteAll()
            (PasskeyAuthenticator.store, PasskeyAuthenticator.verifyUser) = previous
        }
        try await body()
    }

    @Test func registerThenSignInWithValidSignature() async throws {
        try await withTestStore {
            let challenge = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
            let created = await PasskeyAuthenticator.handle([
                "type": "create", "challenge": B64URL.encode(challenge), "rpId": "example.com",
                "userId": B64URL.encode(Data("user-42".utf8)), "userName": "alice", "algs": [-8, -7],
            ], origin: origin, sameOriginAsTop: true)
            #expect(created["error"] == nil, "\(created)")
            let id = try #require(created["id"] as? String)
            let spki = try #require((created["publicKey"] as? String).flatMap(B64URL.decode))
            let publicKey = try P256.Signing.PublicKey(derRepresentation: spki)

            // authData: rpIdHash ‖ flags(UP|UV|AT) ‖ counter ‖ attested credential data
            let authData = try #require((created["authenticatorData"] as? String).flatMap(B64URL.decode))
            #expect(authData.prefix(32) == Data(SHA256.hash(data: Data("example.com".utf8))))
            #expect(authData[32] == 0x45)
            #expect(authData.subdata(in: 55..<71) == B64URL.decode(id))
            let attestation = try #require((created["attestationObject"] as? String).flatMap(B64URL.decode))
            #expect(attestation.prefix(1) == Data([0xA3]))

            let challenge2 = Data("sign-in".utf8)
            let got = await PasskeyAuthenticator.handle([
                "type": "get", "challenge": B64URL.encode(challenge2), "rpId": "example.com", "allow": [id],
            ], origin: origin, sameOriginAsTop: true)
            #expect(got["error"] == nil, "\(got)")
            let ad = try #require((got["authenticatorData"] as? String).flatMap(B64URL.decode))
            let cdj = try #require((got["clientDataJSON"] as? String).flatMap(B64URL.decode))
            let sig = try #require((got["signature"] as? String).flatMap(B64URL.decode))
            #expect(String(decoding: cdj, as: UTF8.self).contains(#""origin":"https://login.example.com""#))
            #expect(ad[32] == 0x05)
            let signature = try P256.Signing.ECDSASignature(derRepresentation: sig)
            #expect(publicKey.isValidSignature(signature, for: ad + Data(SHA256.hash(data: cdj))), "relying party can verify")
            #expect((got["userHandle"] as? String).flatMap(B64URL.decode) == Data("user-42".utf8))
        }
    }

    @Test func refusals() async throws {
        await withTestStore {
            let base: [String: Any] = ["type": "create", "challenge": "AQID", "userId": "AQ", "userName": "bob"]
            var wrongRP = base; wrongRP["rpId"] = "evil.com"
            #expect(await PasskeyAuthenticator.handle(wrongRP, origin: origin, sameOriginAsTop: true)["error"] as? String == "SecurityError")
            var rsaOnly = base; rsaOnly["algs"] = [-257]
            #expect(await PasskeyAuthenticator.handle(rsaOnly, origin: origin, sameOriginAsTop: true)["error"] as? String == "NotSupportedError")
            let insecure = WebOrigin(scheme: "http", host: "login.example.com", port: 0)
            #expect(await PasskeyAuthenticator.handle(base, origin: insecure, sameOriginAsTop: true)["error"] as? String == "SecurityError")
            #expect(await PasskeyAuthenticator.handle(base, origin: origin, sameOriginAsTop: false)["error"] as? String == "NotAllowedError")

            let first = await PasskeyAuthenticator.handle(base, origin: origin, sameOriginAsTop: true)
            var again = base; again["exclude"] = [first["id"] as? String ?? ""]
            #expect(await PasskeyAuthenticator.handle(again, origin: origin, sameOriginAsTop: true)["error"] as? String == "InvalidStateError")
            let get = await PasskeyAuthenticator.handle(["type": "get", "challenge": "AQID", "rpId": "other.example.com"],
                                                        origin: WebOrigin(scheme: "https", host: "other.example.com", port: 0),
                                                        sameOriginAsTop: true)
            #expect(get["error"] as? String == "NotAllowedError", "no passkey for that site")
        }
        await withTestStore(approve: false) {
            let r = await PasskeyAuthenticator.handle(["type": "create", "challenge": "AQID", "userId": "AQ"],
                                                      origin: origin, sameOriginAsTop: true)
            #expect(r["error"] as? String == "NotAllowedError", "Touch ID cancelled")
            #expect(PasskeyAuthenticator.store.all().isEmpty)
        }
    }

    /// Full round trip through a real page: navigator.credentials.create → get.
    @Test func pageRegistersAndSignsIn() async throws {
        try await withTestStore {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled],
                                  backing: .buffered, defer: false)
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            let tab = Tab(url: nil)
            let controller = TabWebController(tab: tab, delegate: nil)
            controller.webView.frame = window.contentView!.bounds
            window.contentView!.addSubview(controller.webView)
            controller.webView.loadHTMLString("<p>login</p>", baseURL: URL(string: "https://login.example.com/"))
            let end = ContinuousClock.now + .seconds(5)
            while controller.webView.isLoading || controller.webView.url == nil, ContinuousClock.now < end {
                try? await Task.sleep(for: .milliseconds(50))
            }
            let result = try await controller.webView.callAsyncJavaScript("""
              const enc = new TextEncoder();
              const reg = await navigator.credentials.create({ publicKey: {
                challenge: crypto.getRandomValues(new Uint8Array(32)), rp: { name: 'Example', id: 'example.com' },
                user: { id: enc.encode('u1'), name: 'carol', displayName: 'Carol' },
                pubKeyCredParams: [{ type: 'public-key', alg: -7 }], authenticatorSelection: { residentKey: 'required' },
                extensions: { credProps: true } } });
              const auth = await navigator.credentials.get({ publicKey: {
                challenge: crypto.getRandomValues(new Uint8Array(32)), rpId: 'example.com' } });
              return JSON.stringify({
                regIsPKC: reg instanceof PublicKeyCredential, regType: reg.type, alg: reg.response.getPublicKeyAlgorithm(),
                rk: reg.getClientExtensionResults().credProps.rk, sameId: auth.id === reg.id,
                user: new TextDecoder().decode(auth.response.userHandle),
                sigLen: auth.response.signature.byteLength, json: JSON.stringify(auth).length > 50,
                cdType: JSON.parse(new TextDecoder().decode(auth.response.clientDataJSON)).type });
            """, contentWorld: .page) as? String
            let r = try JSONSerialization.jsonObject(with: Data(try #require(result).utf8)) as? [String: Any] ?? [:]
            #expect(r["regIsPKC"] as? Bool == true)
            #expect(r["regType"] as? String == "public-key")
            #expect(r["alg"] as? Int == -7)
            #expect(r["rk"] as? Bool == true)
            #expect(r["sameId"] as? Bool == true)
            #expect(r["user"] as? String == "u1")
            #expect((r["sigLen"] as? Int ?? 0) >= 64)
            #expect(r["json"] as? Bool == true)
            #expect(r["cdType"] as? String == "webauthn.get")
        }
    }
}
