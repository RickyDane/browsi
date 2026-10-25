import SwiftUI
import Observation

@Observable
final class Space: Identifiable {
    let id: UUID
    var name: String
    var symbol: String
    /// Hue 0…1 used to tint the window's mesh gradient and accents.
    var hue: Double
    var pinnedTabs: [Tab]
    var tabs: [Tab]
    var selectedTabID: UUID?

    init(id: UUID = UUID(), name: String, symbol: String = "circle.fill", hue: Double,
         pinnedTabs: [Tab] = [], tabs: [Tab] = [], selectedTabID: UUID? = nil) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.hue = hue
        self.pinnedTabs = pinnedTabs
        self.tabs = tabs
        self.selectedTabID = selectedTabID
    }

    var allTabs: [Tab] { pinnedTabs + tabs }
    var selectedTab: Tab? { allTabs.first { $0.id == selectedTabID } }

    var color: Color { Color(hue: hue, saturation: 0.62, brightness: 0.92) }

    static let palette: [(String, String, Double)] = [
        ("Personal", "house.fill", 0.72),
        ("Work", "briefcase.fill", 0.58),
        ("Research", "books.vertical.fill", 0.42),
        ("Fun", "gamecontroller.fill", 0.93),
        ("Travel", "airplane", 0.08),
    ]
}
