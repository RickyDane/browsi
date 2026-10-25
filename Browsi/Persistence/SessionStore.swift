import Foundation

/// Codable snapshot of the window's spaces & tabs, restored on launch.
nonisolated struct SessionSnapshot: Codable, Sendable {
    struct TabState: Codable, Sendable {
        var id: UUID
        var url: URL?
        var title: String
    }
    struct SpaceState: Codable, Sendable {
        var id: UUID
        var name: String
        var symbol: String
        var hue: Double
        var pinned: [TabState]
        var tabs: [TabState]
        var selectedTabID: UUID?
    }
    var spaces: [SpaceState]
    var selectedSpaceID: UUID?
}

nonisolated enum SessionStore {
    static var fileURL: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Browsi", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "session.json")
    }

    static func load() -> SessionSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(SessionSnapshot.self, from: data)
    }

    static func save(_ snapshot: SessionSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
