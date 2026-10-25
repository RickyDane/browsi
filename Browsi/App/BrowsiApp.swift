import SwiftUI

@main
struct BrowsiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var browser = AppDelegate.browser

    var body: some Scene {
        Window("Browsi", id: "main") {
            MainWindowView()
                .environment(browser)
                .onAppear { browser.start() }
                .onOpenURL { browser.open(url: $0, inNewTab: true) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1360, height: 860)
        .commands { AppCommands(browser: browser) }

        Settings {
            SettingsView()
                .environment(browser)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let browser: BrowserState = {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        return BrowserState(library: LibraryStore(inMemory: isTesting),
                            restore: !isTesting && Preferences.shared.restoreSession)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = Preferences.shared.theme.appearance
        #if DEBUG
        if let url = ProcessInfo.processInfo.environment["BROWSI_DEBUG_FLOAT_URL"].flatMap(URL.init(string:)) {
            Task { await Self.debugFloatingScenario(url) }
        }
        #endif
    }

    #if DEBUG
    /// Opens `url`, waits for its video to play, then switches to a new tab (manual QA aid).
    private static func debugFloatingScenario(_ url: URL) async {
        try? await Task.sleep(for: .seconds(1))
        for w in NSApp.windows {
            debugLog("window \(w.className) visible=\(w.isVisible) occl=\(w.occlusionState.rawValue) frame=\(NSStringFromRect(w.frame))")
        }
        let tab = browser.newTab(url: url)
        for _ in 0..<30 {
            try? await Task.sleep(for: .seconds(1))
            if await tab.controller?.webView.requestMediaPlaybackState() == .playing { break }
        }
        try? await Task.sleep(for: .seconds(3))
        browser.newTab(url: URL(string: "https://example.com"))
    }
    #endif

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let count = Self.browser.allTabs.count
        guard Preferences.shared.confirmQuit, count > 1 else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit Browsi?"
        alert.informativeText = "You have \(count) tabs open."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don’t ask again"
        let quit = alert.runModal() == .alertFirstButtonReturn
        if alert.suppressionButton?.state == .on { Preferences.shared.confirmQuit = false }
        return quit ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        if Preferences.shared.clearHistoryOnQuit { Self.browser.library.clearHistory() }
        Self.browser.saveSessionNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
