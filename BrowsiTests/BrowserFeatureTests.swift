import Testing
import Foundation
@testable import Browsi

@MainActor
struct BrowserFeatureTests {
    @Test func safariUserAgentMatchesEngineVersion() {
        #expect(UserAgent.safari.contains("Version/\(UserAgent.safariVersion) Safari/605.1.15"))
        #expect(!UserAgent.safariVersion.isEmpty)
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
}
