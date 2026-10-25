import Testing
import Foundation
@testable import Browsi

struct SmartTitleTests {
    @Test func shortCleanTitlesAreLeftAlone() {
        #expect(!SmartTitler.needsShortening("Hacker News"))
        #expect(!SmartTitler.needsShortening(""))
        #expect(SmartTitler.needsShortening("Docs | Site"))
        #expect(SmartTitler.needsShortening("A really rather long page title without separators"))
    }

    @Test func siteNameFromHost() {
        #expect(SmartTitler.siteName(of: "developer.apple.com") == "apple")
        #expect(SmartTitler.siteName(of: "www.github.com") == "github")
        #expect(SmartTitler.siteName(of: "www.bbc.co.uk") == "bbc")
        #expect(SmartTitler.siteName(of: nil) == nil)
    }

    @Test func heuristicDropsSiteNameSegments() {
        #expect(SmartTitler.heuristic("Swift Concurrency | Apple Developer Documentation",
                                      host: "developer.apple.com") == "Swift Concurrency")
        #expect(SmartTitler.heuristic("GitHub - apple/swift: The Swift Programming Language", host: "github.com")
                .hasPrefix("apple/swift"))
        // The unread counter survives.
        #expect(SmartTitler.heuristic("(3) Inbox - me@example.com - Gmail", host: "mail.google.com") == "(3) Inbox")
        // Every segment names the site: keep the first.
        #expect(SmartTitler.heuristic("YouTube Premium - YouTube", host: "www.youtube.com") == "YouTube Premium")
    }

    @Test func clipCutsAtWordBoundary() {
        let s = SmartTitler.clip("How to bake sourdough bread at home in a cast iron pot", to: 30)
        #expect(s.hasSuffix("…"))
        #expect(s.count <= 31)
        #expect(!s.contains("  "))
        #expect(SmartTitler.clip("Short", to: 30) == "Short")
    }

    @Test func validatesModelSuggestions() {
        let original = "Amazon.com: Logitech MX Master 3S Wireless Performance Mouse : Electronics"
        #expect(SmartTitler.validate("  \"Logitech MX Master 3S\"\n", original: original) == "Logitech MX Master 3S")
        #expect(SmartTitler.validate("", original: original) == nil)
        #expect(SmartTitler.validate(original, original: original) == nil)
        #expect(SmartTitler.validate(String(repeating: "word ", count: 12), original: original + original) == nil)
    }

    @MainActor @Test func sidebarTitleFallsBackToPageTitle() {
        let tab = Tab(url: URL(string: "https://example.com")!, title: "A Long Title | Example")
        #expect(tab.sidebarTitle == tab.displayTitle)
        tab.smartTitle = "A Long Title"
        #expect(tab.sidebarTitle == (Preferences.shared.smartTabTitles ? "A Long Title" : tab.displayTitle))
    }
}

struct PageAssistantTextTests {
    static let page = """
    Home
    About
    Sourdough is bread leavened by wild yeast and lactic acid bacteria rather than baker's yeast.
    The starter must be fed with flour and water every day to stay active.
    Baking
    Bake at 250 °C for 20 minutes covered, then 25 minutes uncovered until the crust is deep brown.
    Storage tips: keep the loaf cut side down on a board for up to three days.
    """

    @Test func passagesSkipNavigationCrumbs() {
        let ps = PageText.passages(from: Self.page, target: 120)
        #expect(!ps.isEmpty)
        #expect(ps.map(\.number) == Array(1...ps.count))
        #expect(ps.allSatisfy { $0.text != "Home\nAbout" })
        #expect(ps.contains { $0.text.contains("250 °C") })
    }

    @Test func selectionPrefersPassagesMatchingTheQuestion() {
        let ps = (1...10).map { PagePassage(number: $0, text: String(repeating: "filler text ", count: 30)) }
            + [PagePassage(number: 11, text: "The oven temperature is 250 degrees for sourdough.")]
        let picked = PageText.select(ps, budget: 1200, question: "What oven temperature?")
        #expect(picked.contains { $0.number == 11 })
        #expect(picked.contains { $0.number == 1 })     // the opening is always kept
        #expect(picked.map(\.number) == picked.map(\.number).sorted())
        #expect(PageText.select(Array(ps.prefix(2)), budget: 10_000) == Array(ps.prefix(2)))
    }

    /// Regression: stop words used to dominate ("the" counted on every occurrence) and "launch" didn't match
    /// "launched", so the passages that answer these questions were dropped.
    @Test func relevanceIgnoresStopWordsAndStemsWords() {
        let theHeavy = PagePassage(number: 2, text: String(repeating: "The history of the design of the telescope and the way the team worked on the project. ", count: 4))
        let mirror = PagePassage(number: 3, text: "Webb's primary mirror consists of 18 hexagonal mirror segments, a 6.5-meter-diameter mirror.")
        let launch = PagePassage(number: 4, text: "The Webb was launched on 25 December 2021 on an Ariane 5 rocket from Kourou, French Guiana.")
        let names = PagePassage(number: 5, text: "Names: Next Generation Space Telescope (NGST; 1996–2002).")
        let ps = [PagePassage(number: 1, text: "Intro."), theHeavy, mirror, launch, names]

        #expect(PageFind.keywordHits(ps, question: "How big is the primary mirror?").first?.number == 3)
        #expect(PageFind.keywordHits(ps, question: "When did it launch and where from?").first?.number == 4)
        let picked = PageText.select(ps + (6...30).map { PagePassage(number: $0, text: theHeavy.text) },
                                     budget: 900, question: "When did it launch?")
        #expect(picked.contains { $0.number == 4 })
        #expect(PageText.stem("launched") == "launch")
        #expect(PageText.stem("mirrors") == "mirror")
        #expect(PageText.stem("batteries") == "battery")
    }

    @Test func citationsBecomeLinksAndInvalidOnesDisappear() {
        let out = PageText.linkCitations("Bake hot [2]. Feed daily [1, 3]. Made up [9].", valid: [1, 2, 3])
        #expect(out.contains("[\\[2\\]](browsi-cite:2)"))
        #expect(out.contains("(browsi-cite:1)[\\[3\\]](browsi-cite:3)"))
        #expect(!out.contains("9"))
    }

    @Test func bulletsAndFindSnippet() {
        #expect(PageText.bulletize("Intro\n- one\n* two") == "Intro\n•  one\n•  two")
        let snippet = PageText.findSnippet(String(repeating: "longword ", count: 20) + "\nsecond line")
        #expect(snippet.count <= 70)
        #expect(!snippet.hasSuffix(" "))
        #expect(PageText.findSnippet("Short line\nNext") == "Short line")
    }
}

@MainActor
struct PageAssistantPanelStateTests {
    @Test func shortcutsOpenSwitchAndCloseThePanel() {
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        browser.togglePageAssistant(.chat)                 // ⌘⇧E opens an empty chat
        #expect(browser.pageAssistantVisible && browser.pageAssistantMode == .chat)
        browser.togglePageAssistant(.summary)              // ⌘⇧S while chatting switches to the summary
        #expect(browser.pageAssistantVisible && browser.pageAssistantMode == .summary)
        browser.togglePageAssistant(.summary)              // same shortcut again closes it
        #expect(!browser.pageAssistantVisible)
        browser.togglePageAssistant(.chat)
        browser.closePageAssistant()
        #expect(!browser.pageAssistantVisible)
    }
}
