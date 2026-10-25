import Observation
import Sparkle

/// Sparkle-based updater. Reads `SUFeedURL` (the appcast attached to the latest GitHub release)
/// and verifies each archive against `SUPublicEDKey` before installing it through Sparkle's
/// sandbox-safe installer XPC service.
@Observable
final class AppUpdater {
    static let shared = AppUpdater()

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    /// False while a check or install is already running.
    private(set) var canCheckForUpdates = false

    var automaticallyChecksForUpdates: Bool {
        get { access(keyPath: \.automaticallyChecksForUpdates); return updater.automaticallyChecksForUpdates }
        set { withMutation(keyPath: \.automaticallyChecksForUpdates) { updater.automaticallyChecksForUpdates = newValue } }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { access(keyPath: \.automaticallyDownloadsUpdates); return updater.automaticallyDownloadsUpdates }
        set { withMutation(keyPath: \.automaticallyDownloadsUpdates) { updater.automaticallyDownloadsUpdates = newValue } }
    }

    var lastCheck: Date? { updater.lastUpdateCheckDate }

    private var updater: SPUUpdater { controller.updater }

    private init() {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        controller = SPUStandardUpdaterController(startingUpdater: !isTesting, updaterDelegate: nil, userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}
