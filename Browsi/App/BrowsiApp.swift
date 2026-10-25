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
    }

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
