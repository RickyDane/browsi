import SwiftUI

struct PinnedTabsGrid: View {
    @Environment(BrowserState.self) private var browser
    let space: Space
    var selectionNamespace: Namespace.ID

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(space.pinnedTabs) { tab in
                PinnedTile(tab: tab, isSelected: space.selectedTabID == tab.id, selectionNamespace: selectionNamespace)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .dropDestination(for: String.self) { items, _ in
                        guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                        browser.move(tabID: id, before: tab, pinned: true)
                        return true
                    }
            }
        }
    }
}

private struct PinnedTile: View {
    @Environment(BrowserState.self) private var browser
    let tab: Tab
    var isSelected: Bool
    var selectionNamespace: Namespace.ID
    @State private var hovering = false

    var body: some View {
        FaviconView(tab: tab, size: 20)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.primary.opacity(isSelected ? 0 : hovering ? 0.1 : 0.05))
            }
            .glassEffect(isSelected ? .regular.tint(.white.opacity(0.15)).interactive() : .identity,
                         in: .rect(cornerRadius: 12, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                        .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                }
            }
            .scaleEffect(hovering && !Motion.reduceMotion ? 1.05 : 1)
            .animation(Motion.bouncy, value: hovering)
            .onHover { hovering = $0; MiddleClickCloser.shared.hover(tab.id, $0) }
            .onTapGesture { browser.select(tab) }
            .help(tab.displayTitle)
            .draggable(tab.id.uuidString) { DragPreview(tab: tab) }
            .contextMenu { TabContextMenu(tab: tab) }
    }
}
