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
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let browser: BrowserState = {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        return BrowserState(library: LibraryStore(inMemory: isTesting), restore: !isTesting)
    }()

    func applicationWillTerminate(_ notification: Notification) {
        Self.browser.saveSessionNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
