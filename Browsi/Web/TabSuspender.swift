import AppKit
import WebKit

/// Frees memory by tearing down the WKWebViews of background tabs.
/// A suspended tab keeps its snapshot + interaction state and is revived on selection.
final class TabSuspender {
    private weak var browser: BrowserState?
    private var timer: Timer?
    private var pressureSource: DispatchSourceMemoryPressure?

    init(browser: BrowserState) {
        self.browser = browser
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sweep() }
        }
        timer?.tolerance = 10
        let src = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.sweep(force: true) }
        }
        src.resume()
        pressureSource = src
    }

    func stop() {
        timer?.invalidate()
        pressureSource?.cancel()
    }

    /// Suspends tabs that have been idle longer than the preference (or all background tabs if forced).
    func sweep(force: Bool = false, now: Date = .now) {
        guard let browser else { return }
        let minutes = Preferences.shared.suspendAfterMinutes
        guard force || minutes > 0 else { return }
        let threshold = TimeInterval(minutes * 60)
        for tab in browser.allTabs where shouldSuspend(tab, selected: browser.selectedTab, force: force,
                                                         threshold: threshold, now: now) {
            Task { await suspend(tab) }
        }
    }

    func shouldSuspend(_ tab: Tab, selected: Tab?, force: Bool, threshold: TimeInterval, now: Date) -> Bool {
        guard tab !== selected, !tab.isSuspended else { return false }
        return force || now.timeIntervalSince(tab.lastActive) >= threshold
    }

    func suspend(_ tab: Tab) async {
        guard let controller = tab.controller else { return }
        let webView = controller.webView
        let playback = await webView.requestMediaPlaybackState()
        if playback == .playing { return }
        if webView.cameraCaptureState == .active || webView.microphoneCaptureState == .active { return }
        guard tab !== browser?.selectedTab, tab.controller === controller else { return }

        if tab.snapshot == nil {
            tab.snapshot = try? await webView.takeSnapshot(configuration: nil)
        }
        tab.interactionState = webView.interactionState
        webView.stopLoading()
        tab.controller = nil
        tab.isLoading = false
    }
}
