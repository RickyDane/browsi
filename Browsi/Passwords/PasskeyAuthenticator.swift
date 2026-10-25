import AppKit
import CryptoKit
import LocalAuthentication
import Security
import WebKit

// Browsi's built-in passkey authenticator (WebAuthn "platform authenticator").
//
// Used when the build lacks Apple's browser passkey entitlement: a page-world script replaces
// navigator.credentials.create/get for `publicKey` requests and forwards them here. Keys are P-256,
// stored in the macOS Keychain, and every ceremony requires Touch ID / the login password.
// The origin always comes from WebKit (WKFrameInfo.securityOrigin), never from the page.

nonisolated enum B64URL {
    static func encode(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }
}

/// Minimal canonical CBOR encoder (only what WebAuthn needs).
nonisolated enum CBOR {
    static func head(_ major: UInt8, _ n: Int) -> Data {
        let m = major << 5
        switch n {
        case 0..<24: return Data([m | UInt8(n)])
        case 24..<256: return Data([m | 24, UInt8(n)])
        case 256..<65536: return Data([m | 25, UInt8(n >> 8), UInt8(n & 0xff)])
        default: return Data([m | 26, UInt8((n >> 24) & 0xff), UInt8((n >> 16) & 0xff), UInt8((n >> 8) & 0xff), UInt8(n & 0xff)])
        }
    }
    static func int(_ v: Int) -> Data { v >= 0 ? head(0, v) : head(1, -1 - v) }
    static func bytes(_ d: Data) -> Data { head(2, d.count) + d }
    static func text(_ s: String) -> Data { let u = Data(s.utf8); return head(3, u.count) + u }
    static func map(_ pairs: [(Data, Data)]) -> Data { pairs.reduce(head(5, pairs.count)) { $0 + $1.0 + $1.1 } }
}

nonisolated struct WebOrigin: Sendable, Equatable {
    var scheme: String
    var host: String
    var port: Int

    var serialized: String {
        let defaultPort = (scheme == "https" && port == 443) || (scheme == "http" && port == 80)
        return port == 0 || defaultPort ? "\(scheme)://\(host)" : "\(scheme)://\(host):\(port)"
    }
    var isSecure: Bool { scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1"].contains(host)) }
}

nonisolated struct Passkey: Identifiable, Codable, Sendable, Equatable, Hashable {
    var credentialID: Data
    var rpID: String
    var userHandle: Data
    var userName: String
    var displayName: String
    var created: Date
    var id: String { B64URL.encode(credentialID) }
    var label: String { userName.isEmpty ? (displayName.isEmpty ? "Passkey" : displayName) : userName }
}

nonisolated enum WebAuthnError: String, Error {
    case notAllowed = "NotAllowedError", invalidState = "InvalidStateError", security = "SecurityError"
    case notSupported = "NotSupportedError", unknown = "UnknownError"

    var message: String {
        switch self {
        case .notAllowed: "The operation either timed out or was not allowed."
        case .invalidState: "A passkey for this account already exists in Browsi."
        case .security: "The relying party ID is not valid for this origin."
        case .notSupported: "Browsi passkeys support ES256 (-7) only."
        case .unknown: "The passkey could not be saved."
        }
    }
}

/// WebAuthn data structures (pure, unit tested).
nonisolated enum WebAuthn {
    static let flagUP: UInt8 = 0x01, flagUV: UInt8 = 0x04, flagAT: UInt8 = 0x40
    static let aaguid = Data(repeating: 0, count: 16)

    /// Domains a site may not use as its RP ID (small built-in public-suffix list).
    static let publicSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "com.au", "net.au", "co.jp", "co.nz", "com.br", "co.in", "com.cn",
        "github.io", "gitlab.io", "vercel.app", "netlify.app", "pages.dev", "workers.dev", "herokuapp.com",
        "web.app", "firebaseapp.com", "appspot.com", "azurewebsites.net", "cloudfront.net", "blogspot.com",
    ]

    static func validRPID(_ rpID: String, for host: String) -> Bool {
        let r = rpID.lowercased(), h = host.lowercased()
        guard !r.isEmpty, h == r || h.hasSuffix("." + r) else { return false }
        if r == "localhost" { return true }
        return r.contains(".") && !publicSuffixes.contains(r)
    }

    /// Serialised in the exact member order the spec mandates.
    static func clientDataJSON(type: String, challenge: Data, origin: String) -> Data {
        Data(#"{"type":"\#(type)","challenge":"\#(B64URL.encode(challenge))","origin":"\#(origin)","crossOrigin":false}"#.utf8)
    }

    static func authenticatorData(rpID: String, flags: UInt8, attested: Data? = nil) -> Data {
        var d = Data(SHA256.hash(data: Data(rpID.utf8)))
        d.append(flags)
        d.append(contentsOf: [0, 0, 0, 0])   // signature counter (always 0, like synced passkeys)
        if let attested { d.append(attested) }
        return d
    }

    static func coseKey(_ key: P256.Signing.PublicKey) -> Data {
        let raw = key.rawRepresentation   // x ‖ y
        return CBOR.map([
            (CBOR.int(1), CBOR.int(2)),    // kty: EC2
            (CBOR.int(3), CBOR.int(-7)),   // alg: ES256
            (CBOR.int(-1), CBOR.int(1)),   // crv: P-256
            (CBOR.int(-2), CBOR.bytes(raw.prefix(32))),
            (CBOR.int(-3), CBOR.bytes(raw.suffix(32))),
        ])
    }

    static func attestedCredentialData(credentialID: Data, publicKey: P256.Signing.PublicKey) -> Data {
        aaguid + Data([UInt8(credentialID.count >> 8), UInt8(credentialID.count & 0xff)]) + credentialID + coseKey(publicKey)
    }

    static func attestationObject(authData: Data) -> Data {
        CBOR.map([
            (CBOR.text("fmt"), CBOR.text("none")),
            (CBOR.text("attStmt"), CBOR.map([])),
            (CBOR.text("authData"), CBOR.bytes(authData)),
        ])
    }
}

/// Passkeys in the Keychain: private key as the secret, metadata in the generic attribute.
nonisolated struct PasskeyStore: Sendable {
    var service = "dev.perlick.browsi.passkey"

    private func base(_ id: String? = nil) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if KeychainStore.useDataProtection { q[kSecUseDataProtectionKeychain as String] = true }
        if let id { q[kSecAttrAccount as String] = id }
        return q
    }

    func save(_ p: Passkey, privateKey: Data) throws {
        SecItemDelete(base(p.id) as CFDictionary)
        var q = base(p.id)
        q[kSecAttrGeneric as String] = try JSONEncoder().encode(p)
        q[kSecAttrLabel as String] = "Browsi passkey – \(p.rpID)"
        q[kSecAttrDescription as String] = "Browsi passkey"
        q[kSecValueData as String] = privateKey
        if KeychainStore.useDataProtection { q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly }
        let s = SecItemAdd(q as CFDictionary, nil)
        guard s == errSecSuccess else { throw KeychainError.status(s) }
    }

    func all() -> [Passkey] {
        var q = base()
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        q[kSecReturnAttributes as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let items = out as? [[String: Any]] else { return [] }
        return items.compactMap { ($0[kSecAttrGeneric as String] as? Data).flatMap { try? JSONDecoder().decode(Passkey.self, from: $0) } }
            .sorted { ($0.rpID, $0.userName) < ($1.rpID, $1.userName) }
    }

    func passkeys(rpID: String) -> [Passkey] { all().filter { $0.rpID == rpID } }

    func privateKey(id: String) throws -> Data {
        var q = base(id)
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecReturnData as String] = true
        var out: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &out)
        guard s == errSecSuccess, let data = out as? Data else { throw KeychainError.status(s) }
        return data
    }

    func delete(id: String) { SecItemDelete(base(id) as CFDictionary) }
    func deleteAll() { SecItemDelete(base() as CFDictionary) }
}

/// Runs WebAuthn ceremonies for pages.
enum PasskeyAuthenticator {
    static var store = PasskeyStore()

    /// Touch ID / login password before every ceremony (WebAuthn user verification). Replaced in tests.
    static var verifyUser: @MainActor (String) async -> Bool = { reason in
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    /// Picks one of several passkeys for a site. Replaced in tests.
    static var chooseAccount: @MainActor ([Passkey], String) async -> Passkey? = { list, rpID in
        let alert = NSAlert()
        alert.messageText = "Sign in to \(rpID)"
        alert.informativeText = "Choose a passkey saved in Browsi."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
        list.forEach { popup.addItem(withTitle: $0.label) }
        alert.accessoryView = popup
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        let response = if let window = NSApp.keyWindow { await alert.beginSheetModal(for: window) } else { alert.runModal() }
        return response == .alertFirstButtonReturn ? list[popup.indexOfSelectedItem] : nil
    }

    static var onNotice: ((String, String) -> Void)?

    static func handle(_ body: [String: Any], origin: WebOrigin, sameOriginAsTop: Bool) async -> [String: Any] {
        do {
            guard origin.isSecure else { throw WebAuthnError.security }
            guard sameOriginAsTop else { throw WebAuthnError.notAllowed }
            switch body["type"] as? String {
            case "create": return try await create(body, origin)
            case "get": return try await get(body, origin)
            default: throw WebAuthnError.notSupported
            }
        } catch let e as WebAuthnError {
            return ["error": e.rawValue, "message": e.message]
        } catch {
            return ["error": WebAuthnError.unknown.rawValue, "message": WebAuthnError.unknown.message]
        }
    }

    private static func rpID(_ body: [String: Any], key: String, _ origin: WebOrigin) throws -> String {
        let id = ((body[key] as? String) ?? origin.host).lowercased()
        guard WebAuthn.validRPID(id, for: origin.host) else { throw WebAuthnError.security }
        return id
    }

    static func create(_ b: [String: Any], _ origin: WebOrigin) async throws -> [String: Any] {
        guard let challenge = (b["challenge"] as? String).flatMap(B64URL.decode),
              let userHandle = (b["userId"] as? String).flatMap(B64URL.decode) else { throw WebAuthnError.notSupported }
        let rp = try rpID(b, key: "rpId", origin)
        let algs = b["algs"] as? [Int] ?? []
        guard algs.isEmpty || algs.contains(-7) else { throw WebAuthnError.notSupported }
        let userName = b["userName"] as? String ?? ""
        let existing = store.passkeys(rpID: rp)
        let exclude = Set(b["exclude"] as? [String] ?? [])

        let who = userName.isEmpty ? rp : "\(userName) on \(rp)"
        guard await verifyUser("save a passkey for \(who)") else { throw WebAuthnError.notAllowed }
        if existing.contains(where: { exclude.contains($0.id) }) { throw WebAuthnError.invalidState }
        // One passkey per account and site: replace an older one for the same user handle.
        for old in existing where old.userHandle == userHandle { store.delete(id: old.id) }

        let key = P256.Signing.PrivateKey()
        var credID = Data(count: 16)
        _ = credID.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let passkey = Passkey(credentialID: credID, rpID: rp, userHandle: userHandle, userName: userName,
                              displayName: b["displayName"] as? String ?? "", created: .now)
        do { try store.save(passkey, privateKey: key.rawRepresentation) } catch { throw WebAuthnError.unknown }

        let authData = WebAuthn.authenticatorData(
            rpID: rp, flags: WebAuthn.flagUP | WebAuthn.flagUV | WebAuthn.flagAT,
            attested: WebAuthn.attestedCredentialData(credentialID: credID, publicKey: key.publicKey))
        let cdj = WebAuthn.clientDataJSON(type: "webauthn.create", challenge: challenge, origin: origin.serialized)
        PasskeySupport.shared.reloadSaved()
        onNotice?("person.badge.key.fill", "Passkey saved for \(rp)")
        return [
            "id": passkey.id,
            "clientDataJSON": B64URL.encode(cdj),
            "attestationObject": B64URL.encode(WebAuthn.attestationObject(authData: authData)),
            "authenticatorData": B64URL.encode(authData),
            "publicKey": B64URL.encode(key.publicKey.derRepresentation),
            "credProps": b["credProps"] as? Bool ?? false,
        ]
    }

    static func get(_ b: [String: Any], _ origin: WebOrigin) async throws -> [String: Any] {
        guard let challenge = (b["challenge"] as? String).flatMap(B64URL.decode) else { throw WebAuthnError.notSupported }
        let rp = try rpID(b, key: "rpId", origin)
        let allow = Set(b["allow"] as? [String] ?? [])
        var candidates = store.passkeys(rpID: rp)
        if !allow.isEmpty { candidates = candidates.filter { allow.contains($0.id) } }
        guard !candidates.isEmpty else {
            onNotice?("person.badge.key", "No Browsi passkey for \(rp)")
            throw WebAuthnError.notAllowed
        }
        guard let chosen = candidates.count == 1 ? candidates[0] : await chooseAccount(candidates, rp),
              await verifyUser("sign in to \(rp) as \(chosen.label)") else { throw WebAuthnError.notAllowed }

        let key: P256.Signing.PrivateKey
        do { key = try P256.Signing.PrivateKey(rawRepresentation: store.privateKey(id: chosen.id)) }
        catch { throw WebAuthnError.notAllowed }
        let authData = WebAuthn.authenticatorData(rpID: rp, flags: WebAuthn.flagUP | WebAuthn.flagUV)
        let cdj = WebAuthn.clientDataJSON(type: "webauthn.get", challenge: challenge, origin: origin.serialized)
        let signature = try key.signature(for: authData + Data(SHA256.hash(data: cdj))).derRepresentation
        return [
            "id": chosen.id,
            "clientDataJSON": B64URL.encode(cdj),
            "authenticatorData": B64URL.encode(authData),
            "signature": B64URL.encode(signature),
            "userHandle": B64URL.encode(chosen.userHandle),
        ]
    }
}

/// Page ↔ native bridge for the built-in authenticator.
final class PasskeyBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let shared = PasskeyBridge()
    static let handlerName = "browsiWebAuthn"

    /// The built-in authenticator is used only when system passkeys (Apple's entitlement) aren't available.
    static var isActive: Bool { !PasskeySupport.isEntitled }

    static let script: WKUserScript? = {
        guard let url = Bundle.main.url(forResource: "webauthn", withExtension: "js"),
              let src = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return WKUserScript(source: src, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)
    }()

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        let o = message.frameInfo.securityOrigin
        let origin = WebOrigin(scheme: o.protocol.lowercased(), host: o.host.lowercased(), port: o.port)
        let topHost = message.webView?.url?.host()?.lowercased()
        let sameOrigin = message.frameInfo.isMainFrame || topHost == origin.host
        let body = message.body as? [String: Any] ?? [:]
        Task {
            let result = await PasskeyAuthenticator.handle(body, origin: origin, sameOriginAsTop: sameOrigin)
            replyHandler(result, nil)
        }
    }
}
