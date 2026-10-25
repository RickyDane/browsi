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
        // Live Text on paused videos lays a text-selection overlay over the frame that swallows clicks,
        // so a video paused on a frame with text can't be resumed by clicking it (or its controls).
        setFeature("TextRecognitionInVideosEnabled", enabled: false, in: config.preferences)
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
        ucc.addUserScript(AppleSignInBridge.script)
        ucc.addScriptMessageHandler(AppleSignInBridge.shared, contentWorld: .defaultClient,
                                    name: AppleSignInBridge.handlerName)
        ucc.add(LoginImpactBridge.shared, contentWorld: .defaultClient, name: LoginImpactBridge.handlerName)
        ucc.add(LinkBridge.shared, contentWorld: .defaultClient, name: LinkBridge.handlerName)
        if let list = ContentBlocker.shared.ruleList, ContentBlocker.shared.isEnabled(for: nil) { ucc.add(list) }
        config.userContentController = ucc
        return config
    }

    /// Toggles a WebKit feature flag through WKPreferences' SPI (`_features`, `_setEnabled:forFeature:`).
    /// Does nothing when the SPI or the flag isn't there.
    private static func setFeature(_ key: String, enabled: Bool, in preferences: WKPreferences) {
        let featuresSel = NSSelectorFromString("_features"), setSel = NSSelectorFromString("_setEnabled:forFeature:")
        guard let cls = WKPreferences.self as AnyObject as? NSObject, cls.responds(to: featuresSel),
              preferences.responds(to: setSel),
              let features = cls.perform(featuresSel)?.takeUnretainedValue() as? [NSObject],
              let feature = features.first(where: { ($0.value(forKey: "key") as? String) == key }) else { return }
        typealias SetEnabled = @convention(c) (AnyObject, Selector, Bool, AnyObject) -> Void
        unsafeBitCast(preferences.method(for: setSel), to: SetEnabled.self)(preferences, setSel, enabled, feature)
    }
}
