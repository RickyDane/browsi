import Testing
import Foundation
@testable import Browsi

struct PageFindTests {
    @Test func questionsAreRecognized() {
        #expect(PageFind.looksLikeQuestion("refund policy?"))
        #expect(PageFind.looksLikeQuestion("where do they mention refunds"))
        #expect(PageFind.looksLikeQuestion("how long is the warranty"))
        #expect(!PageFind.looksLikeQuestion("refund"))
        #expect(!PageFind.looksLikeQuestion("how"))
        #expect(!PageFind.looksLikeQuestion("shipping costs"))
    }

    @Test func keywordHitsPreferPassagesWithMoreDistinctTerms() {
        let passages = [
            PagePassage(number: 1, text: "Welcome to our shop. We sell shoes."),
            PagePassage(number: 2, text: "Refunds are possible within 30 days of delivery."),
            PagePassage(number: 3, text: "Refunds refunds refunds."),
            PagePassage(number: 4, text: "Delivery takes 3 days."),
        ]
        let hits = PageFind.keywordHits(passages, question: "Where do they mention refunds after delivery?")
        #expect(hits.map(\.number) == [2, 3, 4])
        #expect(PageFind.keywordHits(passages, question: "what is this?").isEmpty)
    }

    @Test func validHitsDropUnknownAndDuplicateNumbers() {
        let passages = (1...3).map { PagePassage(number: $0, text: "p\($0)") }
        #expect(PageFind.validHits([2, 9, 2, 1], in: passages).map(\.number) == [2, 1])
    }
}

struct TranslationLanguageTests {
    @Test func baseCodes() {
        #expect(TranslationLanguages.base("en-US") == "en")
        #expect(TranslationLanguages.base("de_DE") == "de")
        #expect(TranslationLanguages.base("zh-Hant-TW") == "zh-Hant")
        #expect(TranslationLanguages.base("FR") == "fr")
    }

    @Test func foreignComparedWithPreferredLanguages() {
        #expect(TranslationLanguages.isForeign("fr", preferred: ["en-US", "de-DE"]))
        #expect(!TranslationLanguages.isForeign("de", preferred: ["en-US", "de-DE"]))
        #expect(!TranslationLanguages.isForeign("en-GB", preferred: ["en-US"]))
    }

    @Test func whitespaceAroundTextNodesIsKept() {
        #expect(TranslationLanguages.preservingWhitespace(original: "  Bonjour\n", translated: "Hello ") == "  Hello\n")
        #expect(TranslationLanguages.preservingWhitespace(original: "Oui", translated: "Yes") == "Yes")
    }

    @Test func detectsLanguageFromText() {
        let french = "Bonjour et bienvenue sur notre site. Nous vendons des chaussures faites à la main en France depuis 1950, avec beaucoup d’amour."
        #expect(TranslationLanguages.detect(sample: french, langAttribute: "en") == "fr")
        #expect(TranslationLanguages.detect(sample: "", langAttribute: "ja-JP") == "ja")
        #expect(TranslationLanguages.detect(sample: "", langAttribute: nil) == nil)
    }
}

struct PageActionTests {
    @Test func csvQuotesOnlyWhenNeededAndPadsRows() {
        let csv = CSV.make([["Name", "Price"], ["Widget, large", "9"], ["Say \"hi\""]])
        #expect(csv == "Name,Price\r\n\"Widget, large\",9\r\n\"Say \"\"hi\"\"\",\r\n")
    }

    @Test func icsForTimedEvent() throws {
        let start = try #require(ICS.date("2026-11-03", time: "14:30"))
        let event = CalendarEvent(title: "Launch; Party", start: start, end: start.addingTimeInterval(5400), allDay: false,
                                  location: "Berlin, DE", notes: "", url: URL(string: "https://example.com/e"))
        let ics = ICS.make(event, uid: "x", now: start)
        #expect(ics.contains("BEGIN:VEVENT\r\n"))
        #expect(ics.contains("SUMMARY:Launch\\; Party\r\n"))
        #expect(ics.contains("LOCATION:Berlin\\, DE\r\n"))
        #expect(ics.contains("URL:https://example.com/e\r\n"))
        #expect(ics.contains("DTSTART:2026"))
        #expect(ics.hasSuffix("END:VCALENDAR\r\n"))
    }

    @Test func icsForAllDayEventEndsNextDay() throws {
        let day = try #require(ICS.date("2026-12-24", time: ""))
        let ics = ICS.make(CalendarEvent(title: "Eve", start: day, end: day, allDay: true, location: "", notes: "", url: nil))
        #expect(ics.contains("DTSTART;VALUE=DATE:20261224"))
        #expect(ics.contains("DTEND;VALUE=DATE:20261225"))
    }

    @Test func longICSLinesAreFolded() {
        let folded = ICS.fold(String(repeating: "a", count: 160))
        let lines = folded.components(separatedBy: "\r\n")
        #expect(lines.count == 3)
        #expect(lines.allSatisfy { $0.utf8.count <= 75 })
        #expect(lines.dropFirst().allSatisfy { $0.hasPrefix(" ") })
    }

    @Test func eventFromDraft() throws {
        var draft = EventDraft(found: true, title: "Keynote", startDate: "2026-06-08", startTime: "10:00", endDate: "",
                               endTime: "", location: "Cupertino", notes: "")
        let e = try #require(ICS.event(from: draft, url: nil))
        #expect(!e.allDay)
        #expect(e.end.timeIntervalSince(e.start) == 3600)
        draft.startTime = ""
        #expect(ICS.event(from: draft, url: nil)?.allDay == true)
        draft.found = false
        #expect(ICS.event(from: draft, url: nil) == nil)
    }

    @Test func comparisonRowsAreAlignedToPageCount() {
        let rows = PageCompare.normalize([ComparisonRow(criterion: "Price", values: ["$1"]),
                                          ComparisonRow(criterion: " ", values: ["x", "y"]),
                                          ComparisonRow(criterion: "Size", values: ["S", "M", "L"])], count: 2)
        #expect(rows.map(\.criterion) == ["Price", "Size"])
        #expect(rows[0].values == ["$1", "—"])
        #expect(rows[1].values == ["S", "M"])
    }
}

struct PageWatchTests {
    @Test func diffFindsAddedAndRemovedLinesInOrder() {
        let old = "Title\nPrice: $129\nIn stock\nFooter"
        let new = "Title\nPrice: $99\nIn stock\nNew colour: blue\nFooter"
        let c = PageDiff.compare(old: old, new: new)
        #expect(c.added == ["Price: $99", "New colour: blue"])
        #expect(c.removed == ["Price: $129"])
        #expect(PageDiff.compare(old: "A  b\n\nC", new: "A b\nC ").isEmpty)
    }

    @Test func diffCountsRepeatedLines() {
        let c = PageDiff.compare(old: "Item\nItem", new: "Item\nItem\nItem")
        #expect(c.added == ["Item"])
        #expect(c.removed.isEmpty)
    }

    @Test func dueAfterInterval() {
        var w = PageWatch(url: URL(string: "https://example.com")!, title: "Example")
        #expect(w.isDue(at: .now))
        w.lastChecked = Date(timeIntervalSinceNow: -30 * 60)
        w.intervalMinutes = 60
        #expect(!w.isDue(at: .now))
        w.intervalMinutes = 15
        #expect(w.isDue(at: .now))
    }

    @Test func sameURLIgnoresFragmentSlashAndWWW() {
        let a = URL(string: "https://www.example.com/item/")!
        #expect(PageWatcher.same(a, URL(string: "https://example.com/item#reviews")!))
        #expect(!PageWatcher.same(a, URL(string: "https://example.com/other")!))
    }

    @Test func watchesSavedBeforeFocusExistedStillLoad() throws {
        let json = #"[{"id":"6F1C2A8E-2B1D-4C1E-9A0B-111111111111","url":"https://example.com","title":"Ex","intervalMinutes":60,"created":0,"baseline":"","unseen":false}]"#
        let watches = try JSONDecoder().decode([PageWatch].self, from: Data(json.utf8))
        #expect(watches.first?.focus == nil)
        #expect(watches.first?.trimmedFocus == nil)
    }

    @Test func focusNarrowsTheChangeCheck() {
        var w = PageWatch(url: URL(string: "https://example.com")!, title: "Shop")
        w.focus = "  "
        #expect(w.trimmedFocus == nil)
        w.focus = " Price below $100 "
        #expect(w.trimmedFocus == "Price below $100")
        let focused = PageWatch.judgeInstructions(focus: w.trimmedFocus)
        #expect(focused.contains("\"Price below $100\""))
        #expect(focused.contains("only about this"))
        #expect(!PageWatch.judgeInstructions(focus: nil).contains("only about this"))
    }

    @Test func watcherPersistsWatches() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "watches-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let w = PageWatch(url: URL(string: "https://example.com")!, title: "Example", baseline: "Hello")
        try JSONEncoder().encode([w]).write(to: file)
        let watcher = PageWatcher(file: file)
        #expect(watcher.watches == [w])
        #expect(watcher.isWatching(URL(string: "https://www.example.com/")))
        watcher.remove(w.id)
        #expect(PageWatcher(file: file).watches.isEmpty)
    }
}

struct PaletteKeywordTests {
    @Test func naturalPhrasingMatchesCommandKeywords() {
        #expect(PaletteSearch.keywordScore(query: "add this to my calendar", title: "Add Event to Calendar",
                                           keywords: "event meeting date") != nil)
        #expect(PaletteSearch.keywordScore(query: "export spreadsheet", title: "Extract Table as CSV",
                                           keywords: "export spreadsheet csv") != nil)
        #expect(PaletteSearch.keywordScore(query: "buy shoes", title: "Add Event to Calendar", keywords: "event") == nil)
        #expect(PaletteSearch.keywordScore(query: "calendar", title: "Add Event to Calendar", keywords: "") == nil)
    }

    @Test func commandSubtitlesDontMatchLikeAddresses() {
        let candidates = [
            PaletteSearch.Candidate(id: "cmd", kind: .command, title: "Extract Table as CSV", subtitle: "Copy or save a table"),
            PaletteSearch.Candidate(id: "hist", kind: .history, title: "Coffee", subtitle: "https://coffee.example"),
        ]
        #expect(PaletteSearch.rank(candidates, query: "co").first == "hist")
    }
}
