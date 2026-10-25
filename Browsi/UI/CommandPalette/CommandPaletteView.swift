import SwiftUI

struct PaletteItem: Identifiable {
    let id: String
    let kind: PaletteKind
    let title: String
    let subtitle: String
    let symbol: String
    var favicon: NSImage? = nil
    var badge: String? = nil
    let action: () -> Void
}

struct CommandPaletteView: View {
    static let inputHeight: CGFloat = 56
    var maxResultsHeight: CGFloat = 400
    @Environment(BrowserState.self) private var browser
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @State private var selection = 0
    @State private var results: [PaletteItem] = []
    @FocusState private var focused: Bool
    @Namespace private var ns

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: browser.palette == .editCurrent ? "globe" : "sparkle.magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(browser.selectedSpace.color)
                    .symbolEffect(.bounce, value: browser.palette)
                TextField(browser.palette == .editCurrent ? "Edit address" : "Search, enter address, or type a command",
                          text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 19, weight: .regular))
                    .focused($focused)
                    .onSubmit(run)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.tab) { move(1); return .handled }
                    .onKeyPress(.escape) { dismiss(); return .handled }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.tertiary)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 18)
            .frame(height: Self.inputHeight)

            if !results.isEmpty {
                Divider().opacity(0.5)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { i, item in
                            PaletteRow(item: item, selected: i == selection, ns: ns)
                                .onTapGesture { selection = i; run() }
                                .onHover { if $0 { selection = i } }
                                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -6)), removal: .opacity))
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: min(400, maxResultsHeight))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 640)
        .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 40, y: 20)
        .animation(Motion.snappy, value: results.map(\.id))
        .animation(Motion.snappy, value: selection)
        .onAppear {
            if browser.palette == .editCurrent, browser.selectedTab?.isHome == false {
                query = browser.selectedTab?.url?.absoluteString ?? ""
            }
            refresh()
            DispatchQueue.main.async { focused = true }
        }
        .onChange(of: query) { selection = 0; refresh() }
    }

    private func move(_ d: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + d + results.count) % results.count
    }

    private func dismiss() {
        withAnimation(Motion.snappy) { browser.palette = .hidden }
    }

    private func run() {
        guard results.indices.contains(selection) else { return }
        let action = results[selection].action
        dismiss()
        action()
    }

    private func refresh() {
        results = PaletteResults.build(query: query, editingCurrent: browser.palette == .editCurrent,
                                       browser: browser, openSettings: { openSettings() })
    }
}

struct PaletteRow: View {
    let item: PaletteItem
    let selected: Bool
    let ns: Namespace.ID

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon = item.favicon {
                    Image(nsImage: icon).resizable().clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: item.symbol).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected ? .primary : .secondary)
                }
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let badge = item.badge, selected {
                Text(badge).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.primary.opacity(0.08), in: .capsule)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: item.subtitle.isEmpty ? 38 : 46)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.primary.opacity(0.09))
                    .matchedGeometryEffect(id: "sel", in: ns)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Builds and ranks suggestions; shared by the command palette and the home search bar.
@MainActor
enum PaletteResults {
    static func build(query q: String, editingCurrent: Bool, browser: BrowserState,
                      openSettings: @escaping () -> Void, limit: Int = 9) -> [PaletteItem] {
        let newTab = !editingCurrent
        var items: [String: PaletteItem] = [:]
        var candidates: [PaletteSearch.Candidate<String>] = []
        func add(_ item: PaletteItem, boost: Double = 0) {
            items[item.id] = item
            candidates.append(.init(id: item.id, kind: item.kind, title: item.title, subtitle: item.subtitle, extraBoost: boost))
        }

        let engine = Preferences.shared.searchEngine
        let parsed = URLInputParser.parse(q)
        if case .url(let url)? = parsed, !editingCurrent || q != browser.selectedTab?.url?.absoluteString {
            add(PaletteItem(id: "nav", kind: .navigate, title: url.absoluteString, subtitle: "", symbol: "arrow.up.right.circle.fill",
                            badge: "Open") { browser.open(url: url, inNewTab: newTab) })
        }

        for space in browser.spaces {
            for tab in space.allTabs where tab !== browser.selectedTab || q.isEmpty == false {
                add(PaletteItem(id: "tab-\(tab.id)", kind: .tab, title: tab.displayTitle,
                                subtitle: tab.url?.absoluteString ?? "", symbol: "square.on.square",
                                favicon: tab.favicon, badge: "Switch to Tab") { browser.select(tab) },
                    boost: q.isEmpty ? -5 : 0)
            }
        }
        for b in browser.library.allBookmarks().prefix(200) {
            guard let url = URL(string: b.urlString) else { continue }
            add(PaletteItem(id: "bm-\(b.urlString)", kind: .bookmark, title: b.title, subtitle: b.urlString,
                            symbol: "star.fill", favicon: FaviconLoader.shared.cached(host: url.host() ?? "")) {
                browser.open(url: url, inNewTab: newTab)
            })
        }
        for h in browser.library.searchHistory(q, limit: q.isEmpty ? 6 : 30) {
            guard let url = URL(string: h.urlString) else { continue }
            add(PaletteItem(id: "h-\(h.urlString)", kind: .history, title: h.title.isEmpty ? h.host : h.title,
                            subtitle: h.urlString, symbol: "clock.arrow.circlepath",
                            favicon: FaviconLoader.shared.cached(host: h.host)) {
                browser.open(url: url, inNewTab: newTab)
            }, boost: min(15, h.frecency / 50))
        }
        if !q.isEmpty {
            for c in commands(browser: browser, openSettings: openSettings) { add(c) }
        }

        var ranked = PaletteSearch.rank(candidates, query: q, limit: limit).compactMap { items[$0] }
        if case .search(let text)? = parsed {
            let search = PaletteItem(id: "search", kind: .search, title: text, subtitle: "", symbol: "magnifyingglass",
                                     badge: "Search \(engine.name)") {
                browser.open(url: engine.searchURL(for: text), inNewTab: newTab)
            }
            // Strong matches (e.g. a host prefix) stay on top, otherwise searching is the default.
            let topScore = ranked.first.flatMap { PaletteSearch.score(query: q, title: $0.title, subtitle: $0.subtitle) } ?? 0
            ranked.insert(search, at: topScore >= 95 ? 1 : 0)
        }
        return Array(ranked.prefix(limit))
    }

    private static func commands(browser: BrowserState, openSettings: @escaping () -> Void) -> [PaletteItem] {
        var c: [PaletteItem] = [
            PaletteItem(id: "cmd-space", kind: .command, title: "New Space", subtitle: "", symbol: "square.stack.3d.up.fill") {
                browser.addSpace()
            },
            PaletteItem(id: "cmd-sidebar", kind: .command, title: "Toggle Sidebar", subtitle: "", symbol: "sidebar.left") {
                withAnimation(Motion.snappy) { browser.sidebarVisible.toggle() }
            },
            PaletteItem(id: "cmd-reopen", kind: .command, title: "Reopen Closed Tab", subtitle: "", symbol: "arrow.uturn.backward") {
                browser.reopenClosedTab()
            },
            PaletteItem(id: "cmd-settings", kind: .command, title: "Settings", subtitle: "", symbol: "gearshape") {
                openSettings()
            },
            PaletteItem(id: "cmd-passwords", kind: .command, title: "Passwords", subtitle: "", symbol: "key.fill") {
                UserDefaults.standard.set("passwords", forKey: "settingsTab"); openSettings()
            },
            PaletteItem(id: "cmd-clear", kind: .command, title: "Clear History", subtitle: "", symbol: "trash") {
                browser.library.clearHistory(); browser.showToast("trash", "History cleared")
            },
        ]
        if let tab = browser.selectedTab {
            c.append(PaletteItem(id: "cmd-pin", kind: .command, title: tab.isPinned ? "Unpin Tab" : "Pin Tab",
                                 subtitle: "", symbol: "pin.fill") { browser.togglePin(tab) })
            c.append(PaletteItem(id: "cmd-blocker", kind: .command, title: "Toggle Tracker Blocking for This Site",
                                 subtitle: "", symbol: "shield.lefthalf.filled") { browser.toggleBlockingForSelectedSite() })
            c.append(PaletteItem(id: "cmd-copy", kind: .command, title: "Copy URL", subtitle: "", symbol: "link") {
                if let u = tab.url {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(u.absoluteString, forType: .string)
                    browser.showToast("link", "Link copied")
                }
            })
        }
        for (i, s) in browser.spaces.enumerated() where s.id != browser.selectedSpaceID {
            c.append(PaletteItem(id: "cmd-go-\(s.id)", kind: .command, title: "Go to \(s.name)", subtitle: "",
                                 symbol: s.symbol, badge: "⌃\(i + 1)") { browser.switchSpace(to: s) })
        }
        return c
    }
}

