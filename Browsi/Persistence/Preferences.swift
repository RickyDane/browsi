import Foundation
import Observation

/// User settings persisted in UserDefaults.
@Observable
final class Preferences {
    static let shared = Preferences()
    private let d = UserDefaults.standard

    var searchEngine: SearchEngine {
        didSet { d.set(searchEngine.rawValue, forKey: "searchEngine") }
    }
    /// Minutes of inactivity before a background tab is suspended (0 = never).
    var suspendAfterMinutes: Int {
        didSet { d.set(suspendAfterMinutes, forKey: "suspendAfterMinutes") }
    }
    var contentBlockingEnabled: Bool {
        didSet { d.set(contentBlockingEnabled, forKey: "contentBlockingEnabled") }
    }
    var blockerAllowlist: Set<String> {
        didSet { d.set(Array(blockerAllowlist), forKey: "blockerAllowlist") }
    }
    var offerToSavePasswords: Bool {
        didSet { d.set(offerToSavePasswords, forKey: "offerToSavePasswords") }
    }
    var neverSavePasswordHosts: Set<String> {
        didSet { d.set(Array(neverSavePasswordHosts), forKey: "neverSavePasswordHosts") }
    }
    var syncPasswordsWithICloud: Bool {
        didSet { d.set(syncPasswordsWithICloud, forKey: "syncPasswordsWithICloud") }
    }
    var animatedBackground: Bool {
        didSet { d.set(animatedBackground, forKey: "animatedBackground") }
    }

    private init() {
        searchEngine = SearchEngine(rawValue: d.string(forKey: "searchEngine") ?? "") ?? .duckDuckGo
        suspendAfterMinutes = d.object(forKey: "suspendAfterMinutes") as? Int ?? 10
        contentBlockingEnabled = d.object(forKey: "contentBlockingEnabled") as? Bool ?? true
        blockerAllowlist = Set(d.stringArray(forKey: "blockerAllowlist") ?? [])
        offerToSavePasswords = d.object(forKey: "offerToSavePasswords") as? Bool ?? true
        neverSavePasswordHosts = Set(d.stringArray(forKey: "neverSavePasswordHosts") ?? [])
        syncPasswordsWithICloud = d.bool(forKey: "syncPasswordsWithICloud")
        animatedBackground = d.object(forKey: "animatedBackground") as? Bool ?? true
    }
}
