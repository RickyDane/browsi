import WebKit

enum WebConfigFactory {
    static let passwordBridge = PasswordBridge()
    private static let autofillScript = PasswordBridge.userScript()

    /// Each tab gets its own user content controller so blocking can be toggled per tab.
    static func make() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.isTextInteractionEnabled = true
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        config.upgradeKnownHostsToHTTPS = true

        let ucc = WKUserContentController()
        if let autofillScript { ucc.addUserScript(autofillScript) }
        ucc.addScriptMessageHandler(passwordBridge, contentWorld: .defaultClient, name: PasswordBridge.handlerName)
        if let list = ContentBlocker.shared.ruleList, ContentBlocker.shared.isEnabled(for: nil) { ucc.add(list) }
        config.userContentController = ucc
        return config
    }
}
