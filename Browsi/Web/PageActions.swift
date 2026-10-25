import AppKit
import FoundationModels
import Observation
import UniformTypeIdentifiers
import WebKit

// MARK: - Pure helpers (unit tested)

nonisolated struct CalendarEvent: Equatable, Sendable {
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
    var location: String
    var notes: String
    var url: URL?
}

nonisolated struct PageTable: Equatable, Sendable {
    var caption: String
    var rows: [[String]]
    var columnCount: Int { rows.map(\.count).max() ?? 0 }
}

nonisolated enum CSV {
    static func field(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// RFC 4180 CSV; short rows are padded so every row has the same number of columns.
    static func make(_ rows: [[String]]) -> String {
        let width = rows.map(\.count).max() ?? 0
        return rows.map { row in
            (row + Array(repeating: "", count: max(0, width - row.count))).map(field).joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
    }
}

nonisolated enum ICS {
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Folds lines longer than 75 octets as RFC 5545 requires.
    static func fold(_ line: String) -> String {
        var out: [String] = []
        var current = ""
        for ch in line {
            if current.utf8.count + String(ch).utf8.count > (out.isEmpty ? 75 : 74) {
                out.append(current)
                current = ""
            }
            current.append(ch)
        }
        out.append(current)
        return out.joined(separator: "\r\n ")
    }

    static func make(_ e: CalendarEvent, uid: String = UUID().uuidString, now: Date = .now) -> String {
        let utc = DateFormatter()
        utc.locale = Locale(identifier: "en_US_POSIX")
        utc.timeZone = TimeZone(identifier: "UTC")
        utc.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = .current
        day.dateFormat = "yyyyMMdd"
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Browsi//Page Actions//EN", "CALSCALE:GREGORIAN",
                     "BEGIN:VEVENT", "UID:\(uid)@browsi", "DTSTAMP:\(utc.string(from: now))"]
        if e.allDay {
            let endDay = Calendar.current.date(byAdding: .day, value: 1, to: max(e.start, e.end)) ?? e.end
            lines.append("DTSTART;VALUE=DATE:\(day.string(from: e.start))")
            lines.append("DTEND;VALUE=DATE:\(day.string(from: endDay))")
        } else {
            lines.append("DTSTART:\(utc.string(from: e.start))")
            lines.append("DTEND:\(utc.string(from: max(e.end, e.start)))")
        }
        lines.append("SUMMARY:\(escape(e.title))")
        if !e.location.isEmpty { lines.append("LOCATION:\(escape(e.location))") }
        var notes = e.notes
        if let url = e.url { notes += (notes.isEmpty ? "" : "\n\n") + url.absoluteString; lines.append("URL:\(url.absoluteString)") }
        if !notes.isEmpty { lines.append("DESCRIPTION:\(escape(notes))") }
        lines += ["END:VEVENT", "END:VCALENDAR"]
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    /// Parses the model's "yyyy-MM-dd" date and optional "HH:mm" time in the user's time zone.
    static func date(_ day: String, time: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        let t = time.trimmingCharacters(in: .whitespaces)
        f.dateFormat = t.isEmpty ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm"
        return f.date(from: t.isEmpty ? day.trimmingCharacters(in: .whitespaces) : "\(day.trimmingCharacters(in: .whitespaces)) \(t)")
    }

    static func event(from d: EventDraft, url: URL?) -> CalendarEvent? {
        guard d.found, let start = date(d.startDate, time: d.startTime) else { return nil }
        let allDay = d.startTime.trimmingCharacters(in: .whitespaces).isEmpty
        var end = date(d.endDate.isEmpty ? d.startDate : d.endDate, time: d.endTime.isEmpty && !allDay ? d.startTime : d.endTime) ?? start
        if !allDay, end <= start { end = start.addingTimeInterval(3600) }
        let title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return CalendarEvent(title: title.isEmpty ? "Event" : title, start: start, end: end, allDay: allDay,
                             location: d.location, notes: d.notes, url: url)
    }
}

nonisolated enum PageCompare {
    /// Pads or trims every row to `count` values so the table lines up with the pages.
    static func normalize(_ rows: [ComparisonRow], count: Int) -> [ComparisonRow] {
        rows.filter { !$0.criterion.trimmingCharacters(in: .whitespaces).isEmpty }.map { r in
            var r = r
            r.values = Array((r.values + Array(repeating: "—", count: max(0, count - r.values.count))).prefix(count))
            return r
        }
    }
}

// MARK: - Model output

@Generable(description: "An event found on a web page")
nonisolated struct EventDraft {
    @Guide(description: "True if the page describes a specific event, appointment, deadline or date to put in a calendar")
    var found: Bool
    @Guide(description: "Short event title, like 'WWDC Keynote' or 'Dentist appointment'")
    var title: String
    @Guide(description: "Start date as yyyy-MM-dd")
    var startDate: String
    @Guide(description: "Start time as 24-hour HH:mm in the event's local time, or empty for an all-day event")
    var startTime: String
    @Guide(description: "End date as yyyy-MM-dd, or empty if the same day")
    var endDate: String
    @Guide(description: "End time as 24-hour HH:mm, or empty if unknown")
    var endTime: String
    @Guide(description: "Venue or address, or 'Online', or empty")
    var location: String
    @Guide(description: "One or two sentences of useful details, or empty")
    var notes: String
}

@Generable(description: "A table extracted from a web page")
nonisolated struct TableDraft {
    @Guide(description: "Column headers", .maximumCount(8))
    var columns: [String]
    @Guide(description: "Rows of the table; each has one cell per column, in column order", .maximumCount(40))
    var rows: [TableDraftRow]
}

@Generable
nonisolated struct TableDraftRow {
    var cells: [String]
}

@Generable(description: "One row of a comparison table")
nonisolated struct ComparisonRow: Equatable {
    @Guide(description: "What is compared, like 'Price', 'Battery life' or 'Main argument'")
    var criterion: String
    @Guide(description: "One short value per page (at most 8 words each), in the order the pages were given")
    var values: [String]
}

@Generable(description: "A side-by-side comparison of web pages")
nonisolated struct ComparisonDraft {
    @Guide(description: "4 to 7 rows with the most useful criteria for comparing these pages", .maximumCount(8))
    var rows: [ComparisonRow]
    @Guide(description: "One or two sentences on the key difference or which fits which need")
    var verdict: String
}

// MARK: - Runner

/// A page action started from the command palette; shown as a glass sheet over the page.
@Observable
final class PageActionRun: Identifiable {
    enum Kind: Equatable { case calendar, table, compare }

    enum Phase {
        case working(String)
        case failed(String)
        case event(CalendarEvent)
        case tables([PageTable])
        case comparison(pages: [String], rows: [ComparisonRow], verdict: String)
    }

    let id = UUID()
    let kind: Kind
    var phase: Phase
    @ObservationIgnored private var task: Task<Void, Never>?

    var title: String {
        switch kind {
        case .calendar: "Add to Calendar"
        case .table: "Extract Table"
        case .compare: "Compare Tabs"
        }
    }

    var symbol: String {
        switch kind {
        case .calendar: "calendar.badge.plus"
        case .table: "tablecells"
        case .compare: "rectangle.split.3x1"
        }
    }

    init(kind: Kind) {
        self.kind = kind
        phase = .working("Reading the page…")
    }

    func cancel() { task?.cancel() }

    func start(tab: Tab, others: [Tab] = []) {
        task = Task { [weak self] in
            guard let self else { return }
            switch kind {
            case .calendar: await self.findEvent(tab)
            case .table: await self.extractTables(tab)
            case .compare: await self.compare([tab] + others)
            }
        }
    }

    private static let unavailable = "Turn on Apple Intelligence in System Settings to use this action."

    // MARK: Calendar

    private func findEvent(_ tab: Tab) async {
        guard SmartSearch.isAvailable else { phase = .failed(Self.unavailable); return }
        let text = await PageScripts.mainText(of: tab) ?? ""
        let passages = PageText.passages(from: text)
        guard !passages.isEmpty else { phase = .failed("This page has no text to read."); return }
        phase = .working("Looking for an event…")
        let today = Date.now.formatted(.iso8601.year().month().day())
        let weekday = Date.now.formatted(.dateTime.weekday(.wide))
        let instructions = """
        You extract a calendar event from a web page. Today is \(weekday), \(today); resolve relative dates \
        like 'next Friday' from that. Use only facts on the page. If the page mentions several events, pick \
        the main one. If there is no specific event or date, set found to false.
        """
        var budget = 3600
        while true {
            let picked = PageText.select(passages, budget: budget)
            let session = LanguageModelSession(model: PageAssistant.model(), instructions: instructions)
            do {
                let r = try await session.respond(
                    to: "Page title: \(tab.displayTitle.prefix(200))\n\nPage text:\n\(picked.map(\.text).joined(separator: "\n\n"))",
                    generating: EventDraft.self, options: GenerationOptions(temperature: 0.1))
                guard !Task.isCancelled else { return }
                if let e = ICS.event(from: r.content, url: tab.url) { phase = .event(e) }
                else { phase = .failed("No event or date found on this page.") }
                return
            } catch LanguageModelSession.GenerationError.exceededContextWindowSize where budget > 1500 {
                budget /= 2
            } catch {
                if !Task.isCancelled { phase = .failed(PageAssistant.describe(error)) }
                return
            }
        }
    }

    /// Saves the event as an .ics file and opens it, so Calendar asks which calendar to add it to.
    static func addToCalendar(_ e: CalendarEvent) throws {
        let name = e.title.replacingOccurrences(of: "/", with: "-").prefix(60)
        let file = FileManager.default.temporaryDirectory.appending(path: "\(name).ics")
        try ICS.make(e).write(to: file, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(file)
    }

    // MARK: Tables

    /// Reads real <table>s (largest first); falls back to the model for lists and cards.
    static let tablesJS = """
    const out = [];
    for (const t of document.querySelectorAll('table')) {
      const rows = [];
      for (const tr of t.rows) {
        const cells = Array.from(tr.cells).map(c => c.innerText.replace(/\\s+/g, ' ').trim());
        if (cells.some(c => c)) rows.push(cells);
        if (rows.length >= 2000) break;
      }
      const width = Math.max(0, ...rows.map(r => r.length));
      if (rows.length >= 2 && width >= 2) {
        const cap = t.caption ? t.caption.innerText.trim() : (t.getAttribute('aria-label') || '');
        out.push({ caption: cap, rows });
      }
    }
    out.sort((a, b) => b.rows.length * b.rows[0].length - a.rows.length * a.rows[0].length);
    return out.slice(0, 12);
    """

    private func extractTables(_ tab: Tab) async {
        guard let webView = tab.controller?.webView else { phase = .failed("This page isn’t loaded."); return }
        let raw = (try? await webView.callAsyncJavaScript(Self.tablesJS, contentWorld: .defaultClient)) as? [[String: Any]] ?? []
        let tables = raw.compactMap { t -> PageTable? in
            guard let rows = t["rows"] as? [[String]] else { return nil }
            return PageTable(caption: t["caption"] as? String ?? "", rows: rows)
        }
        if !tables.isEmpty { phase = .tables(tables); return }
        guard SmartSearch.isAvailable else { phase = .failed("No table found on this page."); return }
        phase = .working("Building a table from the page…")
        let passages = PageText.passages(from: await PageScripts.mainText(of: tab) ?? "")
        guard !passages.isEmpty else { phase = .failed("This page has no text to read."); return }
        let instructions = """
        You turn the structured information on a web page (lists of products, people, prices, specs, \
        schedules…) into one table. Choose clear column headers. Copy values exactly; never invent rows.
        """
        let session = LanguageModelSession(model: PageAssistant.model(), instructions: instructions)
        do {
            let picked = PageText.select(passages, budget: 3200)
            let r = try await session.respond(to: "Page text:\n\(picked.map(\.text).joined(separator: "\n\n"))",
                                              generating: TableDraft.self, options: GenerationOptions(temperature: 0.1))
            guard !Task.isCancelled else { return }
            let rows = r.content.rows.map(\.cells).filter { $0.contains { !$0.isEmpty } }
            guard !rows.isEmpty, !r.content.columns.isEmpty else { phase = .failed("No table-like data found on this page."); return }
            phase = .tables([PageTable(caption: "Built by Apple Intelligence", rows: [r.content.columns] + rows)])
        } catch {
            if !Task.isCancelled { phase = .failed(PageAssistant.describe(error)) }
        }
    }

    static func saveCSV(_ table: PageTable, suggestedName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = suggestedName.replacingOccurrences(of: "/", with: "-").prefix(60) + ".csv"
        panel.directoryURL = .downloadsDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? CSV.make(table.rows).write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Compare

    private func compare(_ tabs: [Tab]) async {
        guard SmartSearch.isAvailable else { phase = .failed(Self.unavailable); return }
        guard tabs.count >= 2 else { phase = .failed("Open at least two web pages in this space to compare."); return }
        phase = .working("Reading \(tabs.count) pages…")
        let budget = 3400 / tabs.count
        var blocks: [String] = []
        for (i, tab) in tabs.enumerated() {
            var text = await PageScripts.mainText(of: tab) ?? ""
            if text.isEmpty, let url = tab.url {
                text = await Self.fetchText(url).replacingOccurrences(of: ". ", with: ".\n")
            }
            let picked = PageText.select(PageText.passages(from: text), budget: budget)
            blocks.append("Page \(i + 1): \(tab.displayTitle.prefix(120))\n\(picked.map(\.text).joined(separator: "\n"))")
            guard !Task.isCancelled else { return }
        }
        phase = .working("Comparing…")
        let instructions = """
        You compare web pages side by side for someone deciding between them. Use only facts from the pages. \
        Every row has exactly \(tabs.count) values, one per page, in page order. Write "—" when a page doesn't say.
        """
        let session = LanguageModelSession(model: PageAssistant.model(), instructions: instructions)
        do {
            let r = try await session.respond(to: blocks.joined(separator: "\n\n---\n\n"),
                                              generating: ComparisonDraft.self, options: GenerationOptions(temperature: 0.2))
            guard !Task.isCancelled else { return }
            let rows = PageCompare.normalize(r.content.rows, count: tabs.count)
            guard !rows.isEmpty else { phase = .failed("Couldn’t find anything to compare."); return }
            phase = .comparison(pages: tabs.map { $0.smartTitle ?? $0.displayTitle }, rows: rows, verdict: r.content.verdict)
        } catch {
            if !Task.isCancelled { phase = .failed(PageAssistant.describe(error)) }
        }
    }

    nonisolated static func fetchText(_ url: URL) async -> String {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(UserAgent.safari, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return "" }
        return HTMLText.plain(String(decoding: data.prefix(400_000), as: UTF8.self))
    }
}
