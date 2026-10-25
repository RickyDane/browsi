import Foundation
import Observation

/// A web page embedded on the home page.
struct HomeModule: Identifiable, Codable, Equatable {
    var id = UUID()
    var url: URL
    var title: String
    var rect: GridRect
    var zoom: Double = 0.85
}

/// The user's home page layout, persisted as JSON.
@Observable
final class HomeStore {
    static let shared = HomeStore()
    private(set) var modules: [HomeModule] = []
    /// Area reserved for the clock + search bar; modules flow around it.
    @ObservationIgnored var locked: [GridRect] = []
    @ObservationIgnored private let fileURL: URL?

    static let presets: [(title: String, url: String, symbol: String)] = [
        ("Hacker News", "https://news.ycombinator.com", "flame.fill"),
        ("Weather", "https://wttr.in/?format=v2", "cloud.sun.fill"),
        ("Wikipedia", "https://en.m.wikipedia.org/wiki/Main_Page", "book.fill"),
        ("GitHub", "https://github.com", "chevron.left.forwardslash.chevron.right"),
        ("YouTube", "https://m.youtube.com", "play.rectangle.fill"),
        ("Reddit", "https://www.reddit.com", "bubble.left.and.bubble.right.fill"),
        ("Apple Newsroom", "https://www.apple.com/newsroom/", "apple.logo"),
        ("Google Calendar", "https://calendar.google.com", "calendar"),
    ]

    init(fileURL: URL? = SessionStore.fileURL.deletingLastPathComponent().appending(path: "home.json")) {
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.fileURL = testing && fileURL == SessionStore.fileURL.deletingLastPathComponent().appending(path: "home.json") ? nil : fileURL
        if let fileURL = self.fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([HomeModule].self, from: data) {
            modules = saved
        } else if self.fileURL != nil {
            modules = [
                HomeModule(url: URL(string: "https://news.ycombinator.com")!, title: "Hacker News",
                           rect: GridRect(col: 0, row: 0, w: 3, h: 7)),
                HomeModule(url: URL(string: "https://wttr.in/?format=v2")!, title: "Weather",
                           rect: GridRect(col: 9, row: 0, w: 3, h: 4)),
            ]
        }
    }

    var rows: Int { modules.map { $0.rect.row + $0.rect.h }.max() ?? 0 }

    @discardableResult
    func add(url: URL, title: String, w: Int = 4, h: Int = 4) -> HomeModule {
        let rect = GridLayout.firstFree(w: w, h: h, among: modules.map(\.rect) + locked)
        let module = HomeModule(url: url, title: title.isEmpty ? (url.host() ?? url.absoluteString) : title, rect: rect)
        modules.append(module)
        save()
        return module
    }

    func remove(_ id: UUID) {
        modules.removeAll { $0.id == id }
        apply(layout())
        HomeWebCache.shared.drop(id)
        save()
    }

    /// Layout preview for `id` placed at `rect` (doesn't commit).
    func preview(_ id: UUID, at rect: GridRect) -> [UUID: GridRect] {
        GridLayout.resolve(modules.map { ($0.id, $0.rect) }, fixedID: id, fixed: rect, locked: locked)
    }

    /// Current positions with the reserved area respected (display only; not persisted).
    func layout() -> [UUID: GridRect] {
        GridLayout.resolve(modules.map { ($0.id, $0.rect) }, fixedID: nil, fixed: nil, locked: locked)
    }

    func commit(_ id: UUID, at rect: GridRect) {
        apply(preview(id, at: rect))
        save()
    }

    func update(_ id: UUID, _ change: (inout HomeModule) -> Void) {
        guard let i = modules.firstIndex(where: { $0.id == id }) else { return }
        change(&modules[i])
        save()
    }

    private func apply(_ layout: [UUID: GridRect]) {
        for i in modules.indices { if let r = layout[modules[i].id] { modules[i].rect = r } }
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(modules) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
