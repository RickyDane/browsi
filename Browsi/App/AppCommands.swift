import SwiftUI

struct AppCommands: Commands {
    let browser: BrowserState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { browser.palette = .newTab }.keyboardShortcut("t")
            Button("Home") { browser.showHome() }.keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Open Location…") { browser.focusAddress() }.keyboardShortcut("l")
            Button("Command Palette…") { browser.palette = .newTab }.keyboardShortcut("k")
            Button("Reopen Closed Tab") { browser.reopenClosedTab() }.keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            Button("New Space") { browser.addSpace() }.keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Copy URL") { browser.copyURL() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(browser.selectedTab?.url == nil)
            Divider()
            Button("Close Tab"){ browser.closeSelectedTab() }.keyboardShortcut("w")
        }

        CommandGroup(replacing: .textEditing) {
            Button("Find…") { browser.openFind(.text) }.keyboardShortcut("f")
            Button("Ask the Page…") { browser.openFind(.ask) }.keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Find Next") { browser.findNext(forward: true) }.keyboardShortcut("g")
            Button("Find Previous") { browser.findNext(forward: false) }.keyboardShortcut("g", modifiers: [.command, .shift])
        }

        CommandMenu("Page") {
            Button(browser.selectedWebTab.map { browser.translator(for: $0).isTranslated } == true ? "Show Original" : "Translate Page") {
                browser.toggleTranslation()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            .disabled(browser.selectedWebTab == nil)
            Button(PageWatcher.shared.isWatching(browser.selectedTab?.url) ? "Edit Page Watch…" : "Watch Page for Changes…") {
                browser.showWatchSetup()
            }
            .disabled(browser.selectedWebTab == nil)
            Divider()
            Button("Add Event to Calendar") { browser.startPageAction(.calendar) }.disabled(browser.selectedWebTab == nil)
            Button("Extract Table as CSV") { browser.startPageAction(.table) }.disabled(browser.selectedWebTab == nil)
            Button("Compare Open Tabs") { browser.startPageAction(.compare) }.disabled(browser.selectedWebTab == nil)
        }

        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") { withAnimation(Motion.snappy) { browser.sidebarVisible.toggle() } }
                .keyboardShortcut("s")
            Button("Downloads") { browser.toggleDownloads() }.keyboardShortcut("j")
            Button("Summarize Page") { browser.togglePageAssistant(.summary) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Ask About Page") { browser.togglePageAssistant(.chat) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Divider()
            Button("Reload Page") { browser.selectedTab?.controller?.webView.reload() }.keyboardShortcut("r")
            Button("Reload Ignoring Cache") { browser.selectedTab?.controller?.webView.reloadFromOrigin() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Divider()
            Button("Actual Size") { browser.selectedTab?.controller?.setZoom(1) }.keyboardShortcut("0")
            Button("Zoom In") { zoom(0.1) }.keyboardShortcut("+")
            Button("Zoom Out") { zoom(-0.1) }.keyboardShortcut("-")
        }

        CommandMenu("History") {
            Button("Back") { browser.selectedTab?.controller?.webView.goBack() }.keyboardShortcut("[")
            Button("Forward") { browser.selectedTab?.controller?.webView.goForward() }.keyboardShortcut("]")
            Divider()
            Button("Search History…") { browser.palette = .newTab }.keyboardShortcut("y")
        }

        CommandMenu("Bookmarks") {
            Button("Bookmark This Page") { browser.toggleBookmarkForSelectedTab() }.keyboardShortcut("d")
            Button("Pin / Unpin Tab") { if let t = browser.selectedTab { browser.togglePin(t) } }
                .keyboardShortcut("p", modifiers: [.command, .shift])
        }

        CommandMenu("Tabs") {
            Button("Next Tab") { browser.selectAdjacentTab(1) }.keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Tab") { browser.selectAdjacentTab(-1) }.keyboardShortcut("[", modifiers: [.command, .shift])
            Button("Switch to Last Tab") { browser.selectPreviousTab() }.keyboardShortcut(.tab, modifiers: .control)
            Divider()
            ForEach(1..<10) { i in
                Button(i == 9 ? "Last Tab" : "Tab \(i)") { browser.selectTab(atIndex: i - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i)")))
            }
            Divider()
            ForEach(1..<10) { i in
                Button("Space \(i)") { browser.selectSpace(atIndex: i - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i)")), modifiers: .control)
            }
            Divider()
            Button("Next Space") { browser.switchSpace(offset: 1) }.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Previous Space") { browser.switchSpace(offset: -1) }.keyboardShortcut(.leftArrow, modifiers: [.command, .option])
        }
    }

    private func zoom(_ d: Double) {
        guard let t = browser.selectedTab else { return }
        t.controller?.setZoom(t.zoom + d)
    }
}
