import SwiftUI

/// Glass sheet showing the result of a page action from the command palette
/// (an event to add to Calendar, a table to export, or a side-by-side comparison).
struct PageActionSheet: View {
    @Environment(BrowserState.self) private var browser
    let run: PageActionRun

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { browser.closePageAction() }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: run.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(browser.selectedSpace.color)
                    Text(run.title).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button { browser.closePageAction() } label: { Image(systemName: "xmark").frame(width: 14, height: 14) }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)
                        .help("Close (Esc)")
                }
                .padding(.horizontal, 18)
                .frame(height: 52)
                Divider().opacity(0.5)
                content
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: width)
            .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 40, y: 18)
            .padding(.leading, browser.sidebarVisible ? Preferences.shared.sidebarWidth : 0)
            .transition(BlurScaleTransition(scale: 0.9, blur: 8))
        }
    }

    private var width: CGFloat {
        switch run.phase {
        case .tables, .comparison: 760
        default: 480
        }
    }

    @ViewBuilder private var content: some View {
        switch run.phase {
        case .working(let message):
            VStack(alignment: .leading, spacing: 12) {
                Label(message, systemImage: "apple.intelligence")
                    .font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
                    .symbolEffect(.pulse)
                ShimmerLines()
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        case .event(let event):
            EventEditor(event: event)
        case .tables(let tables):
            TablePreview(tables: tables, pageTitle: browser.selectedTab?.displayTitle ?? "Table")
        case .comparison(let pages, let rows, let verdict):
            ComparisonView(pages: pages, rows: rows, verdict: verdict)
        }
    }
}

private struct EventEditor: View {
    @Environment(BrowserState.self) private var browser
    @State var event: CalendarEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Form {
                TextField("Title", text: $event.title)
                Toggle("All day", isOn: $event.allDay)
                DatePicker("Starts", selection: $event.start,
                           displayedComponents: event.allDay ? [.date] : [.date, .hourAndMinute])
                DatePicker("Ends", selection: $event.end, in: event.start...,
                           displayedComponents: event.allDay ? [.date] : [.date, .hourAndMinute])
                TextField("Location", text: $event.location)
                TextField("Notes", text: $event.notes, axis: .vertical).lineLimit(1...4)
            }
            .formStyle(.columns)
            HStack {
                Text("Calendar opens so you can pick the calendar.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Add to Calendar") {
                    do {
                        try PageActionRun.addToCalendar(event)
                        browser.closePageAction()
                    } catch {
                        browser.showToast("exclamationmark.triangle.fill", "Couldn’t create the event")
                    }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct TablePreview: View {
    @Environment(BrowserState.self) private var browser
    let tables: [PageTable]
    let pageTitle: String
    @State private var index = 0

    var body: some View {
        let table = tables[min(index, tables.count - 1)]
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if tables.count > 1 {
                    Picker("Table", selection: $index) {
                        ForEach(tables.indices, id: \.self) { i in
                            Text(label(tables[i], i)).tag(i)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                } else {
                    Text(label(table, 0)).font(.system(size: 12.5, weight: .medium))
                }
                Spacer()
                Text("\(table.rows.count) rows × \(table.columnCount) columns")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    ForEach(Array(table.rows.prefix(60).enumerated()), id: \.offset) { r, row in
                        GridRow {
                            ForEach(0..<table.columnCount, id: \.self) { c in
                                Text(c < row.count ? row[c] : "")
                                    .font(.system(size: 12, weight: r == 0 ? .semibold : .regular))
                                    .lineLimit(2)
                                    .frame(maxWidth: 220, alignment: .leading)
                            }
                        }
                        if r == 0 { Divider().gridCellUnsizedAxes(.horizontal) }
                    }
                }
                .padding(12)
                .textSelection(.enabled)
            }
            .frame(maxHeight: 340)
            .background(.primary.opacity(0.04), in: .rect(cornerRadius: 12, style: .continuous))
            HStack {
                if table.rows.count > 60 {
                    Text("Showing 60 of \(table.rows.count) rows; the export has all of them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save CSV…") { PageActionRun.saveCSV(table, suggestedName: pageTitle) }
                    .buttonStyle(.glass)
                Button("Copy CSV") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(CSV.make(table.rows), forType: .string)
                    browser.closePageAction()
                    browser.showToast("tablecells", "Table copied as CSV")
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func label(_ t: PageTable, _ i: Int) -> String {
        let cap = t.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        return cap.isEmpty ? "Table \(i + 1) (\(t.rows.count) rows)" : String(cap.prefix(50))
    }
}

private struct ComparisonView: View {
    @Environment(BrowserState.self) private var browser
    let pages: [String]
    let rows: [ComparisonRow]
    let verdict: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 9) {
                    GridRow {
                        Text("")
                        ForEach(pages.indices, id: \.self) { i in
                            Text(pages[i]).font(.system(size: 12.5, weight: .semibold)).lineLimit(2)
                                .frame(width: 150, alignment: .leading)
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            Text(row.criterion).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                                .frame(width: 120, alignment: .leading)
                            ForEach(row.values.indices, id: \.self) { i in
                                Text(row.values[i]).font(.system(size: 12.5))
                                    .frame(width: 150, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(12)
                .textSelection(.enabled)
            }
            .frame(maxHeight: 360)
            .background(.primary.opacity(0.04), in: .rect(cornerRadius: 12, style: .continuous))
            if !verdict.isEmpty {
                Label { Text(verdict).textSelection(.enabled) } icon: {
                    Image(systemName: "sparkle").foregroundStyle(browser.selectedSpace.color)
                }
                .font(.system(size: 13))
            }
            HStack {
                Text("From the pages’ text by Apple Intelligence; check details before deciding.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy as CSV") {
                    let table = [[""] + pages] + rows.map { [$0.criterion] + $0.values }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(CSV.make(table), forType: .string)
                    browser.showToast("doc.on.doc", "Comparison copied")
                }
                .buttonStyle(.glass)
            }
        }
    }
}
