import Testing
import Foundation
@testable import Browsi

@MainActor
struct BrowserFeatureTests {
    @Test func safariUserAgentMatchesEngineVersion() {
        #expect(UserAgent.safari.contains("Version/\(UserAgent.safariVersion) Safari/605.1.15"))
        #expect(!UserAgent.safariVersion.isEmpty)
    }

    /// Tests run inside the app's sandbox container; they must never overwrite the user's session (and its pinned tabs).
    @Test func inMemoryBrowserDoesNotWriteSessionFile() {
        let url = SessionStore.fileURL
        let before = try? Data(contentsOf: url)
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        browser.togglePin(browser.newTab(url: URL(string: "about:blank#pin")))
        browser.saveSessionNow()
        #expect((try? Data(contentsOf: url)) == before)
    }

    @Test func peekPromotesIntoTabNextToSource() {
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        let source = browser.newTab(url: URL(string: "about:blank"))
        browser.peek(url: URL(string: "about:blank#peek")!, from: source)
        let peekTab = try! #require(browser.peek?.tab)
        #expect(peekTab.controller?.isPeek == true)
        #expect(!browser.selectedSpace.tabs.contains { $0 === peekTab })

        browser.promotePeek()
        #expect(browser.peek == nil)
        #expect(browser.selectedTab === peekTab)
        #expect(peekTab.controller?.isPeek == false)
        let tabs = browser.selectedSpace.tabs
        #expect(tabs.firstIndex { $0 === peekTab } == (tabs.firstIndex { $0 === source } ?? -9) + 1)
    }

    @Test func closePeekDoesNotAddTab() {
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        let source = browser.newTab(url: URL(string: "about:blank"))
        browser.peek(url: URL(string: "about:blank#p")!, from: source)
        browser.closePeek()
        #expect(browser.peek == nil)
        #expect(browser.selectedSpace.tabs.count == 1)
        #expect(browser.selectedTab === source)
    }

    @Test func floatingTabIsNeverSuspended() {
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        let tab = Tab(url: nil)
        tab.controller = TabWebController(tab: tab, delegate: nil)
        tab.isInFloatingPlayer = true
        #expect(!browser.suspender.shouldSuspend(tab, selected: nil, force: true, threshold: 0, now: .now))
    }

    @Test func controlTabTogglesBetweenLastTwoTabs() {
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        let a = browser.newTab(url: URL(string: "https://a.example")!)
        let b = browser.newTab(url: URL(string: "https://b.example")!)
        let c = browser.newTab(url: URL(string: "https://c.example")!)
        browser.select(a)
        browser.selectPreviousTab()
        #expect(browser.selectedTab === c)
        browser.selectPreviousTab()
        #expect(browser.selectedTab === a)
        browser.close(c)
        browser.select(b)
        browser.selectPreviousTab()
        #expect(browser.selectedTab === a)
    }
}
