import Testing
import Foundation
@testable import Browsi

@MainActor
struct TabSuspenderTests {
    @Test func suspendsOnlyIdleBackgroundTabs() {
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        let suspender = TabSuspender(browser: browser)
        let now = Date()
        let selected = Tab(url: URL(string: "https://a.com"))
        let idle = Tab(url: URL(string: "https://b.com"))
        let fresh = Tab(url: URL(string: "https://c.com"))
        for t in [selected, idle, fresh] { t.controller = TabWebController(tab: t, delegate: nil) }
        idle.lastActive = now.addingTimeInterval(-3600)
        fresh.lastActive = now.addingTimeInterval(-10)
        selected.lastActive = now.addingTimeInterval(-3600)

        #expect(!suspender.shouldSuspend(selected, selected: selected, force: true, threshold: 600, now: now))
        #expect(suspender.shouldSuspend(idle, selected: selected, force: false, threshold: 600, now: now))
        #expect(!suspender.shouldSuspend(fresh, selected: selected, force: false, threshold: 600, now: now))
        #expect(suspender.shouldSuspend(fresh, selected: selected, force: true, threshold: 600, now: now))
    }

    @Test func suspendAndReviveKeepsURL() async {
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        let a = browser.newTab(url: URL(string: "about:blank"))
        let b = browser.newTab(url: URL(string: "about:blank#b"))
        #expect(browser.selectedTab === b)
        #expect(!a.isSuspended)

        await browser.suspender.suspend(a)
        #expect(a.isSuspended)
        #expect(a.url != nil)

        browser.select(a)
        #expect(!a.isSuspended)
        #expect(browser.selectedTab === a)
    }

    @Test func closingSelectsNeighbour() {
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        let a = browser.newTab(url: nil)
        let b = browser.newTab(url: nil)
        browser.close(b)
        #expect(browser.selectedTab === a)
        browser.reopenClosedTab() // b had no URL → nothing to reopen
        #expect(browser.selectedSpace.tabs.count == 1)
    }
}
