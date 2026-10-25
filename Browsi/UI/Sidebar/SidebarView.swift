import SwiftUI

struct SidebarView: View {
    @Environment(BrowserState.self) private var browser
    @Namespace private var selectionNS
    @State private var swipe = SwipeTracker()
    @State private var newTabHover = false

    var body: some View {
        let space = browser.selectedSpace
        VStack(alignment: .leading, spacing: 10) {
            NavRow()
                .padding(.top, 6)
            URLBarView()
            ExtensionToolbar()

            Group {
                VStack(alignment: .leading, spacing: 10) {
                    HomeRow(isSelected: space.selectedTabID == nil, selectionNamespace: selectionNS)
                    if !space.pinnedTabs.isEmpty {
                        PinnedTabsGrid(space: space, selectionNamespace: selectionNS)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: space.symbol).foregroundStyle(space.color)
                        Text(space.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        Rectangle().fill(.primary.opacity(0.08)).frame(height: 1)
                    }
                    .font(.system(size: 10))
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { items, _ in
                        // Dropping a tab onto the space header pins it.
                        guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                        browser.move(tabID: id, before: nil, pinned: true)
                        return true
                    }
                    .help("Drop a tab here to pin it")

                    Button { browser.palette = .newTab } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                                .rotationEffect(.degrees(newTabHover && !Motion.reduceMotion ? 90 : 0))
                                .frame(width: 16)
                            Text("New Tab").font(.system(size: 13))
                            Spacer()
                            Text("⌘T").font(.system(size: 11)).foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .frame(height: 22)
                    }
                    .buttonStyle(SquishButtonStyle())
                    .onHover { h in withAnimation(Motion.bouncy) { newTabHover = h } }

                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(space.tabs) { tab in
                                TabRow(tab: tab, isSelected: space.selectedTabID == tab.id, selectionNamespace: selectionNS)
                                    .transition(.tabInsert)
                                    .dropDestination(for: String.self) { items, _ in
                                        guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                                        browser.move(tabID: id, before: tab, pinned: false)
                                        return true
                                    }
                            }
                            Color.clear.frame(height: 40)
                                .dropDestination(for: String.self) { items, _ in
                                    guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                                    browser.move(tabID: id, before: nil, pinned: false)
                                    return true
                                }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
            .id(space.id)
            .transition(.push(from: browser.spaceSwitchDirection > 0 ? .trailing : .leading))
            .offset(x: swipe.offset)

            SpaceSwitcher()
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
        }
        .padding(.horizontal, 10)
        .clipped()
        .background(ScrollSwipeCatcher(tracker: swipe) { dir in browser.switchSpace(offset: dir) })
    }
}

private struct NavRow: View {
    @Environment(BrowserState.self) private var browser

    var body: some View {
        let tab = browser.selectedTab
        HStack(spacing: 2) {
            Spacer().frame(width: 70) // traffic lights
            Button { withAnimation(Motion.snappy) { browser.sidebarVisible.toggle() } } label: {
                Image(systemName: "sidebar.left")
            }.help("Toggle Sidebar (⌘S)")
            Spacer()
            Button { tab?.controller?.webView.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(tab?.canGoBack != true).help("Back (⌘[)")
            Button { tab?.controller?.webView.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(tab?.canGoForward != true).help("Forward (⌘])")
            Button {
                if tab?.isLoading == true { tab?.controller?.webView.stopLoading() }
                else { tab?.controller?.webView.reload() }
            } label: {
                Image(systemName: tab?.isLoading == true ? "xmark" : "arrow.clockwise")
                    .contentTransition(.symbolEffect(.replace))
            }.help("Reload (⌘R)")
        }
        .font(.system(size: 13, weight: .medium))
        .buttonStyle(SquishButtonStyle())
        .foregroundStyle(.secondary)
        .frame(height: 28)
    }
}

/// Tracks horizontal two-finger swipes over the sidebar to switch spaces.
@Observable
final class SwipeTracker {
    var offset: CGFloat = 0
    @ObservationIgnored var accumulated: CGFloat = 0
    @ObservationIgnored var monitor: Any?
}

private struct ScrollSwipeCatcher: NSViewRepresentable {
    let tracker: SwipeTracker
    let onSwipe: (Int) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        tracker.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak view] event in
            guard let view, let window = view.window, event.window === window else { return event }
            let p = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(p), event.hasPreciseScrollingDeltas else { return event }
            switch event.phase {
            case .began:
                tracker.accumulated = 0
            case .changed:
                guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) || tracker.accumulated != 0 else { return event }
                tracker.accumulated += event.scrollingDeltaX
                tracker.offset = max(-60, min(60, tracker.accumulated * 0.35))
                return nil
            case .ended, .cancelled:
                let acc = tracker.accumulated
                tracker.accumulated = 0
                withAnimation(Motion.bouncy) { tracker.offset = 0 }
                if abs(acc) > 80 { onSwipe(acc < 0 ? 1 : -1); return nil }
            default: break
            }
            return event
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {}
}

/// Always-present entry at the top of every space that shows the home page.
private struct HomeRow: View {
    @Environment(BrowserState.self) private var browser
    var isSelected: Bool
    var selectionNamespace: Namespace.ID
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: isSelected ? "house.fill" : "house")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(browser.selectedSpace.color) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 16)
            Text("Home").font(.system(size: 13, weight: isSelected ? .medium : .regular))
            Spacer()
            Text("⌘⇧H").font(.system(size: 11)).foregroundStyle(.tertiary)
                .opacity(hovering ? 1 : 0)
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
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .onTapGesture { browser.showHome() }
        .help("Home (⌘⇧H)")
    }
}
