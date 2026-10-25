import WebKit

enum WebConfigFactory {
    static let passwordBridge = PasswordBridge()
    private static let autofillScript = PasswordBridge.userScript()

    /// Each tab gets its own user content controller so blocking can be toggled per tab.
    static func make() -> WKWebViewConfiguration {
        let prefs = Preferences.shared
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.isTextInteractionEnabled = true
        config.preferences.isFraudulentWebsiteWarningEnabled = prefs.fraudWarnings
        config.preferences.javaScriptCanOpenWindowsAutomatically = !prefs.blockPopups
        config.preferences.minimumFontSize = prefs.minimumFontSize
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = switch prefs.autoplay {
        case .allowAll: []
        case .blockAudio: .audio
        case .blockAll: .all
        }
        config.defaultWebpagePreferences.allowsContentJavaScript = prefs.javaScriptEnabled
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        config.upgradeKnownHostsToHTTPS = prefs.upgradeToHTTPS
        config.webExtensionController = ExtensionManager.shared.controller

        let ucc = WKUserContentController()
        if let autofillScript { ucc.addUserScript(autofillScript) }
        ucc.addScriptMessageHandler(passwordBridge, contentWorld: .defaultClient, name: PasswordBridge.handlerName)
        ucc.addUserScript(LinkBridge.script)
        if PasskeyBridge.isActive, let script = PasskeyBridge.script {
            ucc.addUserScript(script)
            ucc.addScriptMessageHandler(PasskeyBridge.shared, contentWorld: .page, name: PasskeyBridge.handlerName)
        }
        ucc.addUserScript(LoginImpactBridge.script)
        ucc.add(LoginImpactBridge.shared, contentWorld: .defaultClient, name: LoginImpactBridge.handlerName)
        ucc.add(LinkBridge.shared, contentWorld: .defaultClient, name: LinkBridge.handlerName)
        if let list = ContentBlocker.shared.ruleList, ContentBlocker.shared.isEnabled(for: nil) { ucc.add(list) }
        config.userContentController = ucc
        return config
    }
}
