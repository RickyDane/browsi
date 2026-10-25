import Foundation
import SwiftData

/// History + bookmarks backed by SwiftData. Writes are coalesced and saved in batches.
@Observable
final class LibraryStore {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private var saveTask: Task<Void, Never>?
    /// Bumped on bookmark changes so views can refresh cheaply.
    private(set) var bookmarkRevision = 0
    /// In-memory stores (tests) must never write to the user's files.
    let isInMemory: Bool

    init(inMemory: Bool = false) {
        isInMemory = inMemory
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: HistoryEntry.self, Bookmark.self, configurations: config)
        } catch {
            container = try! ModelContainer(for: HistoryEntry.self, Bookmark.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        container.mainContext.autosaveEnabled = false
    }

    // MARK: History

    func recordVisit(url: URL, title: String) {
        guard let scheme = url.scheme, scheme == "http" || scheme == "https" else { return }
        let key = url.absoluteString
        var d = FetchDescriptor<HistoryEntry>(predicate: #Predicate { $0.urlString == key })
        d.fetchLimit = 1
        if let existing = try? context.fetch(d).first {
            existing.visitCount += 1
            existing.lastVisit = .now
            if !title.isEmpty { existing.title = title }
        } else {
            context.insert(HistoryEntry(urlString: key, title: title, host: url.host() ?? ""))
        }
        scheduleSave()
    }

    func updateTitle(url: URL, title: String) {
        guard !title.isEmpty else { return }
        let key = url.absoluteString
        var d = FetchDescriptor<HistoryEntry>(predicate: #Predicate { $0.urlString == key })
        d.fetchLimit = 1
        if let e = try? context.fetch(d).first, e.title != title {
            e.title = title
            scheduleSave()
        }
    }

    func searchHistory(_ query: String, limit: Int = 40) -> [HistoryEntry] {
        var d: FetchDescriptor<HistoryEntry>
        if query.isEmpty {
            d = FetchDescriptor(sortBy: [SortDescriptor(\.lastVisit, order: .reverse)])
        } else {
            d = FetchDescriptor(predicate: #Predicate {
                $0.urlString.localizedStandardContains(query) || $0.title.localizedStandardContains(query)
            }, sortBy: [SortDescriptor(\.lastVisit, order: .reverse)])
        }
        d.fetchLimit = limit
        return (try? context.fetch(d)) ?? []
    }

    func clearHistory() {
        try? context.delete(model: HistoryEntry.self)
        scheduleSave()
    }

    // MARK: Bookmarks

    func allBookmarks() -> [Bookmark] {
        (try? context.fetch(FetchDescriptor<Bookmark>(sortBy: [SortDescriptor(\.created, order: .reverse)]))) ?? []
    }

    func isBookmarked(_ url: URL?) -> Bool {
        _ = bookmarkRevision
        guard let key = url?.absoluteString else { return false }
        var d = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.urlString == key })
        d.fetchLimit = 1
        return ((try? context.fetchCount(d)) ?? 0) > 0
    }

    /// Returns true when the URL is bookmarked after the toggle.
    @discardableResult
    func toggleBookmark(url: URL, title: String) -> Bool {
        let key = url.absoluteString
        let d = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.urlString == key })
        let existing = (try? context.fetch(d)) ?? []
        defer { bookmarkRevision += 1; scheduleSave() }
        if existing.isEmpty {
            context.insert(Bookmark(urlString: key, title: title))
            return true
        }
        existing.forEach(context.delete)
        return false
    }

    func delete(_ bookmark: Bookmark) {
        context.delete(bookmark)
        bookmarkRevision += 1
        scheduleSave()
    }

    // MARK: Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        if context.hasChanges { try? context.save() }
    }
}
