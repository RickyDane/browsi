import WebKit

struct PendingPasswordSave: Identifiable, Equatable {
    let id = UUID()
    let host: String
    let username: String
    let password: String
    let isUpdate: Bool
}

/// JS ↔ native bridge for password capture and autofill.
/// Secrets only ever flow to a frame whose secure origin host matches the stored item.
final class PasswordBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let handlerName = "browsiPasswords"

    var keychain: KeychainStore {
        KeychainStore(synchronizable: Preferences.shared.syncPasswordsWithICloud)
    }
    /// Called when a login form was submitted with new/changed credentials.
    var onOfferSave: ((PendingPasswordSave) -> Void)?

    static func userScript() -> WKUserScript? {
        guard let url = Bundle.main.url(forResource: "autofill", withExtension: "js"),
              let src = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return WKUserScript(source: src, injectionTime: .atDocumentEnd, forMainFrameOnly: false,
                            in: .defaultClient)
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        let origin = message.frameInfo.securityOrigin
        let host = origin.host.lowercased()
        let secure = origin.protocol == "https" || host == "localhost" || host == "127.0.0.1"
        guard secure, !host.isEmpty,
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            replyHandler(nil, "insecure origin"); return
        }

        switch type {
        case "accounts":
            let names = keychain.accounts(host: host).map(\.username)
            replyHandler(names, nil)

        case "fill":
            guard let username = body["username"] as? String else { replyHandler(nil, "bad request"); return }
            let store = keychain
            Task {
                guard await BiometricGate.shared.authenticate(reason: "fill your password for \(host)") else {
                    replyHandler(nil, "denied"); return
                }
                replyHandler(try? store.password(host: host, username: username), nil)
            }

        case "submit":
            replyHandler(nil, nil)
            let prefs = Preferences.shared
            guard prefs.offerToSavePasswords, !prefs.neverSavePasswordHosts.contains(host),
                  let username = (body["username"] as? String)?.trimmingCharacters(in: .whitespaces),
                  let password = body["password"] as? String, !password.isEmpty else { return }
            let existing = try? keychain.password(host: host, username: username)
            if existing == password { return }
            onOfferSave?(PendingPasswordSave(host: host, username: username, password: password,
                                             isUpdate: existing != nil))

        default:
            replyHandler(nil, "unknown")
        }
    }
}
