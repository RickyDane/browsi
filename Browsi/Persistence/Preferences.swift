import AppKit
import Observation

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Alternate app icons (Design/galaxy). macOS has no alternate-icon API, so the choice is applied
/// to the running app's Dock icon via `NSApp.applicationIconImage`.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case nebulaSparkle, boldViolet, goldBlue, dustLane, minimalSwirl
    var id: String { rawValue }
    var name: String {
        switch self {
        case .nebulaSparkle: "Nebula sparkle"
        case .boldViolet: "Bold violet"
        case .goldBlue: "Gold and blue"
        case .dustLane: "Dust lane"
        case .minimalSwirl: "Minimal swirl"
        }
    }
    var assetName: String {
        switch self {
        case .boldViolet: "AppIconR1"
        case .goldBlue: "AppIconR2"
        case .dustLane: "AppIconR3"
        case .minimalSwirl: "AppIconR4"
        case .nebulaSparkle: "AppIconR5"
        }
    }
    var image: NSImage? { NSImage(named: assetName) }

    /// Sets the Dock icon. The default icon resets to the bundle's own icon.
    func apply() {
        NSApp?.applicationIconImage = self == .nebulaSparkle ? nil : image
    }
}

enum TabDensity: String, CaseIterable, Identifiable {
    case compact, comfortable, spacious
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var rowHeight: CGFloat {
        switch self {
        case .compact: 28
        case .comfortable: 34
        case .spacious: 40
        }
    }
}

enum NewTabPosition: String, CaseIterable, Identifiable {
    case top, bottom
    var id: String { rawValue }
    var name: String { self == .top ? "Top of list" : "Bottom of list" }
}

enum CloseTabSelection: String, CaseIterable, Identifiable {
    case next, recent
    var id: String { rawValue }
    var name: String { self == .next ? "Next tab in list" : "Most recently used tab" }
}

enum AutoplayPolicy: String, CaseIterable, Identifiable {
    case allowAll, blockAudio, blockAll
    var id: String { rawValue }
    var name: String {
        switch self {
        case .allowAll: "Allow all autoplay"
        case .blockAudio: "Stop media with sound"
        case .blockAll: "Never autoplay"
        }
    }
}

enum UserAgentMode: String, CaseIterable, Identifiable {
    case safari, chrome, firefox, custom
    var id: String { rawValue }
    var name: String {
        switch self {
        case .safari: "Safari (recommended)"
        case .chrome: "Google Chrome"
        case .firefox: "Firefox"
        case .custom: "Custom"
        }
    }
}

/// User settings persisted in UserDefaults.
@Observable
final class Preferences {
    static let shared = Preferences()
    @ObservationIgnored private let d = UserDefaults.standard

    // MARK: General
    var searchEngine: SearchEngine { didSet { d.set(searchEngine.rawValue, forKey: "searchEngine") } }
    var homeSmartAnswers: Bool { didSet { d.set(homeSmartAnswers, forKey: "homeSmartAnswers") } }
    var restoreSession: Bool { didSet { d.set(restoreSession, forKey: "restoreSession") } }
    var confirmQuit: Bool { didSet { d.set(confirmQuit, forKey: "confirmQuit") } }
    /// Name shown on the Profile card; empty means the macOS account's full name.
    var profileName: String { didSet { d.set(profileName, forKey: "profileName") } }

    // MARK: Appearance
    var theme: AppTheme { didSet { d.set(theme.rawValue, forKey: "theme"); NSApp?.appearance = effectiveAppearance } }
    /// Space theme: starry night sky everywhere, shooting stars on the home page (always dark).
    var spaceTheme: Bool { didSet { d.set(spaceTheme, forKey: "spaceTheme"); NSApp?.appearance = effectiveAppearance } }
    var effectiveAppearance: NSAppearance? { spaceTheme ? NSAppearance(named: .darkAqua) : theme.appearance }
    var appIcon: AppIconChoice { didSet { d.set(appIcon.rawValue, forKey: "appIcon"); appIcon.apply() } }
    var sidebarWidth: Double { didSet { d.set(sidebarWidth, forKey: "sidebarWidth") } }
    var tabDensity: TabDensity { didSet { d.set(tabDensity.rawValue, forKey: "tabDensity") } }
    var animatedBackground: Bool { didSet { d.set(animatedBackground, forKey: "animatedBackground") } }
    var backgroundIntensity: Double { didSet { d.set(backgroundIntensity, forKey: "backgroundIntensity") } }
    var edgeToEdgeContent: Bool { didSet { d.set(edgeToEdgeContent, forKey: "edgeToEdgeContent") } }
    var loginImpactAnimation: Bool { didSet { d.set(loginImpactAnimation, forKey: "loginImpactAnimation") } }
    var appleSignInSheet: Bool { didSet { d.set(appleSignInSheet, forKey: "appleSignInSheet") } }
    var reduceAnimations: Bool { didSet { d.set(reduceAnimations, forKey: "reduceAnimations") } }
    var showFullURL: Bool { didSet { d.set(showFullURL, forKey: "showFullURL") } }
    var showSuspendedIndicator: Bool { didSet { d.set(showSuspendedIndicator, forKey: "showSuspendedIndicator") } }
    var smartTabTitles: Bool { didSet { d.set(smartTabTitles, forKey: "smartTabTitles") } }

    // MARK: Tabs
    /// Minutes of inactivity before a background tab is suspended (0 = never).
    var suspendAfterMinutes: Int { didSet { d.set(suspendAfterMinutes, forKey: "suspendAfterMinutes") } }
    var newTabPosition: NewTabPosition { didSet { d.set(newTabPosition.rawValue, forKey: "newTabPosition") } }
    var commandClickOpensInBackground: Bool { didSet { d.set(commandClickOpensInBackground, forKey: "commandClickOpensInBackground") } }
    var closeTabSelection: CloseTabSelection { didSet { d.set(closeTabSelection.rawValue, forKey: "closeTabSelection") } }
    var linkPeekEnabled: Bool { didSet { d.set(linkPeekEnabled, forKey: "linkPeekEnabled") } }
    var floatingVideoEnabled: Bool { didSet { d.set(floatingVideoEnabled, forKey: "floatingVideoEnabled") } }

    // MARK: Privacy & Security
    var contentBlockingEnabled: Bool { didSet { d.set(contentBlockingEnabled, forKey: "contentBlockingEnabled") } }
    var blockerAllowlist: Set<String> { didSet { d.set(Array(blockerAllowlist), forKey: "blockerAllowlist") } }
    var upgradeToHTTPS: Bool { didSet { d.set(upgradeToHTTPS, forKey: "upgradeToHTTPS") } }
    var fraudWarnings: Bool { didSet { d.set(fraudWarnings, forKey: "fraudWarnings") } }
    var blockPopups: Bool { didSet { d.set(blockPopups, forKey: "blockPopups") } }
    var clearHistoryOnQuit: Bool { didSet { d.set(clearHistoryOnQuit, forKey: "clearHistoryOnQuit") } }

    // MARK: Translation
    var offerTranslation: Bool { didSet { d.set(offerTranslation, forKey: "offerTranslation") } }
    /// Base language codes ("fr", "ja") that are translated automatically.
    var alwaysTranslate: Set<String> { didSet { d.set(Array(alwaysTranslate), forKey: "alwaysTranslate") } }

    // MARK: Passwords
    var offerToSavePasswords: Bool { didSet { d.set(offerToSavePasswords, forKey: "offerToSavePasswords") } }
    var autofillPasswords: Bool { didSet { d.set(autofillPasswords, forKey: "autofillPasswords") } }
    var requireAuthToFill: Bool { didSet { d.set(requireAuthToFill, forKey: "requireAuthToFill") } }
    /// Seconds a Touch ID unlock stays valid.
    var authGracePeriod: Int { didSet { d.set(authGracePeriod, forKey: "authGracePeriod") } }
    var neverSavePasswordHosts: Set<String> { didSet { d.set(Array(neverSavePasswordHosts), forKey: "neverSavePasswordHosts") } }
    var syncPasswordsWithICloud: Bool { didSet { d.set(syncPasswordsWithICloud, forKey: "syncPasswordsWithICloud") } }

    // MARK: Websites
    var defaultZoom: Double { didSet { d.set(defaultZoom, forKey: "defaultZoom") } }
    var javaScriptEnabled: Bool { didSet { d.set(javaScriptEnabled, forKey: "javaScriptEnabled") } }
    var autoplay: AutoplayPolicy { didSet { d.set(autoplay.rawValue, forKey: "autoplay") } }
    var minimumFontSize: Double { didSet { d.set(minimumFontSize, forKey: "minimumFontSize") } }

    // MARK: Downloads
    var downloadFolderBookmark: Data? { didSet { d.set(downloadFolderBookmark, forKey: "downloadFolderBookmark") } }
    var askWhereToSave: Bool { didSet { d.set(askWhereToSave, forKey: "askWhereToSave") } }
    var revealDownloads: Bool { didSet { d.set(revealDownloads, forKey: "revealDownloads") } }
    var smartRenameDownloads: Bool { didSet { d.set(smartRenameDownloads, forKey: "smartRenameDownloads") } }

    // MARK: Advanced
    var userAgentMode: UserAgentMode { didSet { d.set(userAgentMode.rawValue, forKey: "userAgentMode") } }
    var customUserAgent: String { didSet { d.set(customUserAgent, forKey: "customUserAgent") } }
    var webInspectorEnabled: Bool { didSet { d.set(webInspectorEnabled, forKey: "webInspectorEnabled") } }

    private init() {
        let d = UserDefaults.standard
        func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }
        func int(_ k: String, _ def: Int) -> Int { d.object(forKey: k) as? Int ?? def }
        func dbl(_ k: String, _ def: Double) -> Double { d.object(forKey: k) as? Double ?? def }
        func raw<T: RawRepresentable>(_ k: String, _ def: T) -> T where T.RawValue == String {
            d.string(forKey: k).flatMap { T(rawValue: $0) } ?? def
        }
        func set(_ k: String) -> Set<String> { Set(d.stringArray(forKey: k) ?? []) }

        searchEngine = raw("searchEngine", .duckDuckGo)
        restoreSession = bool("restoreSession", true)
        homeSmartAnswers = bool("homeSmartAnswers", true)
        confirmQuit = bool("confirmQuit", false)
        profileName = d.string(forKey: "profileName") ?? ""
        offerTranslation = bool("offerTranslation", true)
        alwaysTranslate = set("alwaysTranslate")

        theme = raw("theme", .system)
        spaceTheme = bool("spaceTheme", true)
        appIcon = raw("appIcon", .nebulaSparkle)
        sidebarWidth = dbl("sidebarWidth", 252)
        tabDensity = raw("tabDensity", .comfortable)
        animatedBackground = bool("animatedBackground", true)
        backgroundIntensity = dbl("backgroundIntensity", 0.85)
        edgeToEdgeContent = bool("edgeToEdgeContent", false)
        reduceAnimations = bool("reduceAnimations", false)
        loginImpactAnimation = bool("loginImpactAnimation", true)
        appleSignInSheet = bool("appleSignInSheet", true)
        showFullURL = bool("showFullURL", false)
        showSuspendedIndicator = bool("showSuspendedIndicator", true)
        smartTabTitles = bool("smartTabTitles", true)

        suspendAfterMinutes = int("suspendAfterMinutes", 10)
        newTabPosition = raw("newTabPosition", .top)
        commandClickOpensInBackground = bool("commandClickOpensInBackground", true)
        closeTabSelection = raw("closeTabSelection", .next)
        linkPeekEnabled = bool("linkPeekEnabled", true)
        floatingVideoEnabled = bool("floatingVideoEnabled", true)

        contentBlockingEnabled = bool("contentBlockingEnabled", true)
        blockerAllowlist = set("blockerAllowlist")
        upgradeToHTTPS = bool("upgradeToHTTPS", true)
        fraudWarnings = bool("fraudWarnings", true)
        blockPopups = bool("blockPopups", true)
        clearHistoryOnQuit = bool("clearHistoryOnQuit", false)

        offerToSavePasswords = bool("offerToSavePasswords", true)
        autofillPasswords = bool("autofillPasswords", true)
        requireAuthToFill = bool("requireAuthToFill", true)
        authGracePeriod = int("authGracePeriod", 300)
        neverSavePasswordHosts = set("neverSavePasswordHosts")
        syncPasswordsWithICloud = bool("syncPasswordsWithICloud", false)

        defaultZoom = dbl("defaultZoom", 1)
        javaScriptEnabled = bool("javaScriptEnabled", true)
        autoplay = raw("autoplay", .allowAll)
        minimumFontSize = dbl("minimumFontSize", 0)

        downloadFolderBookmark = d.data(forKey: "downloadFolderBookmark")
        askWhereToSave = bool("askWhereToSave", false)
        // Downloads no longer open Finder by default (one-time reset of the old default).
        if !d.bool(forKey: "migrated.revealDownloadsOff") {
            d.set(false, forKey: "revealDownloads")
            d.set(true, forKey: "migrated.revealDownloadsOff")
        }
        revealDownloads = bool("revealDownloads", false)
        smartRenameDownloads = bool("smartRenameDownloads", true)

        userAgentMode = raw("userAgentMode", .safari)
        customUserAgent = d.string(forKey: "customUserAgent") ?? ""
        webInspectorEnabled = bool("webInspectorEnabled", true)
    }

    /// Removes every stored setting and reloads defaults.
    func resetAll() {
        for key in d.dictionaryRepresentation().keys where !key.hasPrefix("NS") && !key.hasPrefix("Apple") {
            d.removeObject(forKey: key)
        }
        let fresh = Preferences()
        searchEngine = fresh.searchEngine; restoreSession = fresh.restoreSession; homeSmartAnswers = fresh.homeSmartAnswers; confirmQuit = fresh.confirmQuit
        profileName = fresh.profileName
        offerTranslation = fresh.offerTranslation; alwaysTranslate = fresh.alwaysTranslate
        theme = fresh.theme; spaceTheme = fresh.spaceTheme; appIcon = fresh.appIcon; sidebarWidth = fresh.sidebarWidth; tabDensity = fresh.tabDensity
        animatedBackground = fresh.animatedBackground; backgroundIntensity = fresh.backgroundIntensity
        edgeToEdgeContent = fresh.edgeToEdgeContent; reduceAnimations = fresh.reduceAnimations
        loginImpactAnimation = fresh.loginImpactAnimation
        appleSignInSheet = fresh.appleSignInSheet
        showFullURL = fresh.showFullURL; showSuspendedIndicator = fresh.showSuspendedIndicator
        suspendAfterMinutes = fresh.suspendAfterMinutes; newTabPosition = fresh.newTabPosition
        commandClickOpensInBackground = fresh.commandClickOpensInBackground
        closeTabSelection = fresh.closeTabSelection; linkPeekEnabled = fresh.linkPeekEnabled
        floatingVideoEnabled = fresh.floatingVideoEnabled
        contentBlockingEnabled = fresh.contentBlockingEnabled; blockerAllowlist = []
        upgradeToHTTPS = fresh.upgradeToHTTPS; fraudWarnings = fresh.fraudWarnings
        blockPopups = fresh.blockPopups; clearHistoryOnQuit = fresh.clearHistoryOnQuit
        offerToSavePasswords = fresh.offerToSavePasswords; autofillPasswords = fresh.autofillPasswords
        requireAuthToFill = fresh.requireAuthToFill; authGracePeriod = fresh.authGracePeriod
        neverSavePasswordHosts = []; syncPasswordsWithICloud = false
        defaultZoom = fresh.defaultZoom; javaScriptEnabled = fresh.javaScriptEnabled
        autoplay = fresh.autoplay; minimumFontSize = fresh.minimumFontSize
        downloadFolderBookmark = nil; askWhereToSave = fresh.askWhereToSave; revealDownloads = fresh.revealDownloads
        smartRenameDownloads = fresh.smartRenameDownloads
        userAgentMode = fresh.userAgentMode; customUserAgent = ""; webInspectorEnabled = fresh.webInspectorEnabled
    }
}

// MARK: - User agent

enum UserAgent {
    /// Version of the system Safari — the WebKit we run *is* that Safari's engine, so claiming
    /// exactly that version keeps the UA consistent with feature detection (Google sign-in checks this).
    nonisolated static let safariVersion: String = {
        if let v = Bundle(path: "/Applications/Safari.app")?.infoDictionary?["CFBundleShortVersionString"] as? String {
            return v
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "\(os.majorVersion).\(os.minorVersion)"
    }()

    nonisolated static let safari = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(safariVersion) Safari/605.1.15"
    static let chrome = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"
    static let firefox = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:144.0) Gecko/20100101 Firefox/144.0"

    static var current: String {
        let p = Preferences.shared
        switch p.userAgentMode {
        case .safari: return safari
        case .chrome: return chrome
        case .firefox: return firefox
        case .custom: return p.customUserAgent.isEmpty ? safari : p.customUserAgent
        }
    }
}
