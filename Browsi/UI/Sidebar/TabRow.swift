import SwiftUI
import UniformTypeIdentifiers

struct FaviconView: View {
    let tab: Tab
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            if let icon = tab.favicon {
                Image(nsImage: icon).resizable().interpolation(.high)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                    .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: tab.isSuspended && Preferences.shared.showSuspendedIndicator ? "moon.zzz.fill" : "globe")
                    .font(.system(size: size * 0.8))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse, options: .repeating, isActive: tab.isLoading)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: size, height: size)
        .animation(Motion.bouncy, value: tab.favicon != nil)
    }
}

struct TabRow: View {
    @Environment(BrowserState.self) private var browser
    let tab: Tab
    var isSelected: Bool
    var selectionNamespace: Namespace.ID
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            FaviconView(tab: tab)
            Text(tab.displayTitle)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                .foregroundStyle(tab.isSuspended && !isSelected && Preferences.shared.showSuspendedIndicator ? .secondary : .primary)
                .contentTransition(.interpolate)
            Spacer(minLength: 0)
            if tab.isInFloatingPlayer {
                Image(systemName: "pip.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                    .symbolEffect(.pulse, options: .repeating)
                    .help("Playing in floating window")
            }
            if hovering || isSelected {
                Button { browser.close(tab) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(SquishButtonStyle())
                .padding(-6)
                .foregroundStyle(.secondary)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
                .help("Close Tab (⌘W)")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Preferences.shared.tabDensity.rowHeight)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular.tint(.white.opacity(0.12)).interactive(),
                                 in: .rect(cornerRadius: 10, style: .continuous))
                    .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            } else if hovering {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.06))
            }
        }
        .contentShape(Rectangle())
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { hovering = h }
            MiddleClickCloser.shared.hover(tab.id, h)
        }
        .onTapGesture { browser.select(tab) }
        .draggable(tab.id.uuidString) { DragPreview(tab: tab) }
        .contextMenu { TabContextMenu(tab: tab) }
    }
}

struct DragPreview: View {
    let tab: Tab
    var body: some View {
        HStack { FaviconView(tab: tab); Text(tab.displayTitle).lineLimit(1) }
            .padding(8)
            .glassEffect(.regular, in: .capsule)
    }
}

struct TabContextMenu: View {
    @Environment(BrowserState.self) private var browser
    let tab: Tab

    var body: some View {
        Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") { browser.togglePin(tab) }
        Button("Duplicate Tab") { if let u = tab.url { browser.newTab(url: u, background: true, after: tab) } }
        Button("Copy Link") {
            guard let u = tab.url else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(u.absoluteString, forType: .string)
        }
        Menu("Move to Space") {
            ForEach(browser.spaces) { s in
                Button(s.name) { move(to: s) }.disabled(browser.space(of: tab) === s)
            }
        }
        Divider()
        Button("Close Tab") { browser.close(tab) }
    }

    private func move(to target: Space) {
        guard let from = browser.space(of: tab) else { return }
        let wasSelected = from.selectedTabID == tab.id
        withAnimation(Motion.snappy) {
            from.tabs.removeAll { $0 === tab }
            from.pinnedTabs.removeAll { $0 === tab }
            tab.isPinned = false
            target.tabs.insert(tab, at: 0)
            if wasSelected { from.selectedTabID = from.allTabs.first?.id }
        }
        browser.scheduleSave()
    }
}
