import AppKit
import AuthenticationServices
import Security

/// Passkeys (WebAuthn) for web pages.
///
/// WebKit performs the actual WebAuthn ceremonies (create/get, conditional UI, hybrid/QR via iPhone,
/// security keys) inside WKWebView — but only for a browser app that
///  1. is signed with Apple's `com.apple.developer.web-browser.public-key-credential` entitlement, and
///  2. has been allowed by the user to use their passkeys
///     (System Settings › Privacy & Security › Passkeys Access for Web Browsers).
/// This type checks both and drives the authorization prompt.
@Observable
final class PasskeySupport {
    static let shared = PasskeySupport()
    nonisolated static let entitlement = "com.apple.developer.web-browser.public-key-credential"

    enum Status: Equatable {
        /// The running binary isn't signed with the entitlement (see README › Passkeys).
        case missingEntitlement
        case notDetermined
        case authorized
        case denied

        var summary: String {
            switch self {
            case .missingEntitlement: "Using Browsi’s built-in passkeys"
            case .notDetermined: "Waiting for your permission"
            case .authorized: "Passkeys are ready"
            case .denied: "Access was denied"
            }
        }
    }

    private(set) var status: Status = .missingEntitlement
    @ObservationIgnored private let manager = ASAuthorizationWebBrowserPublicKeyCredentialManager()
    @ObservationIgnored private var requesting = false
    /// Passkeys stored by Browsi's built-in authenticator.
    private(set) var saved: [Passkey] = []

    init() { refresh(); reloadSaved() }

    func reloadSaved() { saved = PasskeyAuthenticator.store.all() }

    func delete(_ passkey: Passkey) {
        PasskeyAuthenticator.store.delete(id: passkey.id)
        reloadSaved()
    }

    /// True when the running process carries the browser passkey entitlement.
    nonisolated static var hasEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil) else { return false }
        return (value as? Bool) == true
    }

    nonisolated static func map(entitled: Bool,
                                _ state: ASAuthorizationWebBrowserPublicKeyCredentialManager.AuthorizationState) -> Status {
        guard entitled else { return .missingEntitlement }
        switch state {
        case .authorized: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    func refresh() {
        status = Self.map(entitled: Self.hasEntitlement, manager.authorizationStateForPlatformCredentials)
    }

    /// Shows the system "Allow Browsi to use your passkeys?" prompt if the user hasn't decided yet.
    func requestAuthorizationIfNeeded() async {
        refresh()
        guard status == .notDetermined, !requesting else { return }
        requesting = true
        defer { requesting = false }
        let state = await withCheckedContinuation { (cont: CheckedContinuation<ASAuthorizationWebBrowserPublicKeyCredentialManager.AuthorizationState, Never>) in
            manager.requestAuthorizationForPublicKeyCredentials { cont.resume(returning: $0) }
        }
        status = Self.map(entitled: true, state)
    }

    /// Called when the user clicks a passkey button on a page.
    func userIntendsToUsePasskey(browser: BrowserState?) {
        refresh()
        switch status {
        case .notDetermined:
            Task { await requestAuthorizationIfNeeded() }
        case .denied:
            browser?.showToast("person.badge.key.fill", "Allow passkeys in Settings › Passwords")
        default:
            break
        }
    }

    func openSystemSettings() {
        // Privacy & Security pane; the passkey list lives there.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}
