import Foundation
import SwiftData

@Model
final class HistoryEntry {
    #Index<HistoryEntry>([\.urlString], [\.lastVisit])
    @Attribute(.unique) var urlString: String
    var title: String
    var host: String
    var visitCount: Int
    var lastVisit: Date

    init(urlString: String, title: String, host: String) {
        self.urlString = urlString
        self.title = title
        self.host = host
        self.visitCount = 1
        self.lastVisit = .now
    }

    /// Frecency: visits weighted by recency.
    var frecency: Double {
        let ageDays = max(0, Date.now.timeIntervalSince(lastVisit) / 86_400)
        let recency = ageDays < 1 ? 100.0 : ageDays < 7 ? 70 : ageDays < 30 ? 50 : ageDays < 90 ? 30 : 10
        return Double(visitCount) * recency
    }
}

@Model
final class Bookmark {
    @Attribute(.unique) var urlString: String
    var title: String
    var folder: String
    var created: Date

    init(urlString: String, title: String, folder: String = "") {
        self.urlString = urlString
        self.title = title
        self.folder = folder
        self.created = .now
    }
}
