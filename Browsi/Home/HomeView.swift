import SwiftUI

/// Personal home page: an AI-powered search bar above a grid of live web modules
/// that can be dragged and resized.
struct HomeView: View {
    @State private var homeQuery = ""
    @Environment(BrowserState.self) private var browser
    @State private var store = HomeStore.shared
    @State private var search = SmartSearch()
    @State private var editing = false
    @State private var showAdd = false

    static let barHeight: CGFloat = 54

    /// The fixed central block (clock + search bar) on the 12-column grid.
    /// Wide windows: modules sit left, right, above and below it; narrow windows: above and below.
    static func heroRect(colWidth: CGFloat) -> GridRect {
        colWidth >= 70 ? GridRect(col: 3, row: 3, w: 6, h: 4) : GridRect(col: 0, row: 3, w: 12, h: 4)
    }

    var body: some View {
        GeometryReader { viewport in
            let width = max(300, min(viewport.size.width - 56, 1400))
            let colWidth = HomeGridMetrics.colWidth(for: width)
            let hero = Self.heroRect(colWidth: colWidth)
            let heroFrame = HomeGridMetrics.frame(hero, colWidth)
            // Scroll position 0 shows the search bar exactly in the vertical centre.
            let topInset = max(16, viewport.size.height / 2 - heroFrame.midY)
            ScrollView {
                ModuleGrid(store: store, width: width, hero: hero) {
                    heroContent
                }
                .padding(.top, topInset)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
                .background {
                    // Clicking empty space takes focus away from the search bar.
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
                }
            }
            .background {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
            }
            .scrollIndicators(.automatic)
        }
        .animation(Motion.smooth, value: search.phase)
        .onAppear { HomeWebCache.shared.homeAppeared() }
        .onDisappear { HomeWebCache.shared.homeDisappeared(); search.cancel() }
    }

    /// Search bar centred in the hero block; clock above, "Add module" and the answer below
    /// (as overlays, so the bar never moves and the answer can float over modules).
    private var heroContent: some View {
        let above = Self.barHeight / 2 + 24   // header bottom sits this far above the bar's centre
        let below = Self.barHeight / 2 + 16   // answer / add button top sits this far below it
        return HomeSearchBar(search: search, query: $homeQuery)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .center) {
                header
                    .fixedSize()
                    .alignmentGuide(VerticalAlignment.center) { $0[.bottom] + above }
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .center) {
                VStack(spacing: 14) {
                    if !homeQuery.isEmpty && search.phase == .idle {
                        EmptyView()   // suggestions dropdown occupies this space
                    } else if search.phase != .idle {
                        SmartAnswerCard(search: search)
                            .transition(BlurScaleTransition(scale: 0.96, blur: 8).combined(with: .move(edge: .top)))
                    } else {
                        Button { showAdd = true } label: { Label("Add Module", systemImage: "plus") }
                            .buttonStyle(.glass).controlSize(.small)
                            .popover(isPresented: $showAdd, arrowEdge: .bottom) { AddModuleView { showAdd = false } }
                            .transition(.opacity)
                    }
                }
                .frame(width: 720)
                .fixedSize(horizontal: false, vertical: true)
                .alignmentGuide(VerticalAlignment.center) { $0[.top] - below }
            }
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            VStack(spacing: 2) {
                Text(ctx.date, format: .dateTime.hour().minute())
                    .font(.system(size: 54, weight: .thin, design: .rounded))
                    .contentTransition(.numericText())
                Text(greeting(ctx.date)).font(.title3).foregroundStyle(.secondary)
            }
        }
    }

    private func greeting(_ date: Date) -> String {
        let h = Calendar.current.component(.hour, from: date)
        let part = h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
        return "\(part) · \(browser.selectedSpace.name)"
    }
}

// MARK: - Search bar

private struct HomeSearchBar: View {
    @Environment(BrowserState.self) private var browser
    let search: SmartSearch
    @Binding var query: String
    @FocusState private var focused: Bool
    @Environment(\.openSettings) private var openSettings
    @State private var suggestions: [PaletteItem] = []
    @State private var selection = 0
    @Namespace private var ns

    private var showsSuggestions: Bool { focused && !suggestions.isEmpty && search.phase == .idle }

    var body: some View {
        let engine = Preferences.shared.searchEngine
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: SmartSearch.isAvailable ? "apple.intelligence" : "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(SmartSearch.isAvailable
                                     ? AnyShapeStyle(LinearGradient(colors: [.purple, .pink, .orange, .cyan],
                                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                     : AnyShapeStyle(.secondary))
                    .symbolEffect(.pulse, options: .repeating, isActive: search.phase == .working)
                    .symbolEffect(.bounce, value: focused)
                    .scaleEffect(focused && !Motion.reduceMotion ? 1.12 : 1)
                TextField("", text: $query,
                          prompt: Text(SmartSearch.isAvailable ? "Ask anything, search, or enter an address"
                                                                : "Search or enter an address")
                              .foregroundStyle(.secondary))
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused($focused)
                    .onSubmit { runSelection() }
                    .onKeyPress(keys: [.return]) { press in
                        if press.modifiers.contains(.shift) { openWebSearch(); return .handled }
                        if press.modifiers.contains(.command) { askIntelligence(); return .handled }
                        runSelection(); return .handled
                    }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.tab) { move(1); return .handled }
                    .onKeyPress(.escape) {
                        if !query.isEmpty { query = "" } else { focused = false }
                        return .handled
                    }
                if !query.isEmpty {
                    Button { openWebSearch() } label: {
                        HStack(spacing: 4) {
                            Text("Search \(engine.name)")
                            Text("⇧↩").foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.glass).controlSize(.small)
                    .help("⇧↩ searches \(engine.name) directly")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 18)
            .frame(height: HomeView.barHeight)
        }
        .frame(maxWidth: 720)
        .glassEffect(.regular, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay {
            // Focus ring: a soft space-tinted rim that blooms in when the bar is focused.
            let tint = browser.selectedSpace.color
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tint.opacity(focused ? 0.75 : 0), lineWidth: 1.5)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(tint.opacity(focused ? 0.45 : 0), lineWidth: 8)
                        .blur(radius: 12)
                }
                .allowsHitTesting(false)
        }
        .overlay {
            if search.phase == .working { IntelligenceGlow(cornerRadius: 18) }
        }
        .scaleEffect(focused && !Motion.reduceMotion ? 1.025 : 1)
        .shadow(color: .black.opacity(focused ? 0.2 : 0.12), radius: focused ? 28 : 18, y: focused ? 14 : 8)
        .animation(Motion.bouncy, value: focused)
        .animation(Motion.snappy, value: query.isEmpty)
        .overlay(alignment: .top) {
            // Same suggestions as the command palette, dropping down from the bar.
            if showsSuggestions {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(suggestions.enumerated()), id: \.element.id) { i, item in
                            PaletteRow(item: item, selected: i == selection, ns: ns)
                                .onTapGesture { selection = i; runSelection() }
                                .onHover { if $0 { selection = i } }
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 380)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 720)
                .glassEffect(.regular, in: .rect(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 26, y: 12)
                .offset(y: HomeView.barHeight + 8)
                .transition(BlurScaleTransition(scale: 0.97, blur: 6).combined(with: .offset(y: -6)))
                .animation(Motion.snappy, value: selection)
                .animation(Motion.snappy, value: suggestions.map(\.id))
            }
        }
        .animation(Motion.snappy, value: showsSuggestions)
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: browser.homeSearchFocusRequest) {
            // Re-trigger even if already focused so the focus animation plays.
            focused = false
            DispatchQueue.main.async { focused = true }
        }
        .onChange(of: query) {
            if search.phase != .working { search.reset() }
            selection = 0
            refreshSuggestions()
        }
    }

    private func refreshSuggestions() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { suggestions = []; return }
        var items = PaletteResults.build(query: q, editingCurrent: false, browser: browser,
                                         openSettings: { openSettings() }, limit: 8)
        // Apple Intelligence is one suggestion among the others (⌘↩), right below the top hit.
        if SmartSearch.isAvailable, Preferences.shared.homeSmartAnswers, case .search? = URLInputParser.parse(q) {
            let ask = PaletteItem(id: "ask-ai", kind: .search, title: q, subtitle: "", symbol: "apple.intelligence",
                                  badge: "Ask Apple Intelligence ⌘↩") { [search, browser] in
                search.run(q, library: browser.library)
            }
            items.insert(ask, at: min(1, items.count))
        }
        suggestions = items
    }

    private func move(_ d: Int) {
        guard !suggestions.isEmpty else { return }
        selection = (selection + d + suggestions.count) % suggestions.count
    }

    /// ↩ runs the highlighted suggestion, exactly like the command palette.
    private func runSelection() {
        if suggestions.isEmpty { refreshSuggestions() }
        guard suggestions.indices.contains(selection) else { return }
        let item = suggestions[selection]
        if item.id != "ask-ai" { query = "" }
        item.action()
    }

    private func askIntelligence() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        if SmartSearch.isAvailable { search.run(q, library: browser.library) } else { openWebSearch() }
    }

    /// ⇧↩: always a web search on the configured engine, even for things that look like addresses.
    private func openWebSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        query = ""
        browser.openFromHome(Preferences.shared.searchEngine.searchURL(for: q))
    }
}

/// Apple-Intelligence-style rotating rainbow edge shown while the model works.
struct IntelligenceGlow: View {
    var cornerRadius: CGFloat
    var body: some View {
        TimelineView(.animation) { ctx in
            let angle = Angle.degrees(ctx.date.timeIntervalSinceReferenceDate * 120)
            let gradient = AngularGradient(colors: [.purple, .pink, .orange, .yellow, .cyan, .blue, .purple],
                                           center: .center, angle: angle)
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(gradient, lineWidth: 6).blur(radius: 10).opacity(0.8)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(gradient, lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

// MARK: - Answer

private struct SmartAnswerCard: View {
    @Environment(BrowserState.self) private var browser
    let search: SmartSearch

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "apple.intelligence")
                Text(title).font(.system(size: 12, weight: .semibold))
                    .contentTransition(.interpolate)
                Spacer()
                Button { search.reset() } label: { Image(systemName: "xmark") }
                    .buttonStyle(SquishButtonStyle()).padding(-6).foregroundStyle(.secondary)
            }
            .foregroundStyle(.secondary)

            if case .failed(let message) = search.phase {
                Text(message).foregroundStyle(.secondary)
            } else if search.answer.isEmpty {
                ShimmerLines()
            } else {
                Text(rendered)
                    .font(.system(size: 14.5))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !search.sources.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(search.sources) { s in
                            Button { browser.openFromHome(s.url) } label: {
                                HStack(spacing: 6) {
                                    Text("\(s.number)").font(.system(size: 10, weight: .bold))
                                        .frame(width: 16, height: 16).background(.primary.opacity(0.1), in: .circle)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(s.title).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                                        Text(s.url.host() ?? "").font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: 220, alignment: .leading)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.primary.opacity(0.06), in: .rect(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(18)
        .frame(maxWidth: 720, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18, style: .continuous))
        .animation(Motion.snappy, value: search.sources)
        .environment(\.openURL, OpenURLAction { url in browser.openFromHome(url); return .handled })
    }

    private var title: String {
        switch search.phase {
        case .working: search.answer.isEmpty ? search.activity + "…" : "Answering…"
        case .failed: "No answer"
        default: "Answer"
        }
    }

    private var rendered: AttributedString {
        let md = SmartSearch.linkCitations(search.answer, sources: search.sources)
        return (try? AttributedString(markdown: md, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(search.answer)
    }
}

private struct ShimmerLines: View {
    @State private var phase = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach([1.0, 0.92, 0.6], id: \.self) { w in
                RoundedRectangle(cornerRadius: 4).fill(.primary.opacity(phase ? 0.12 : 0.05))
                    .frame(height: 10).frame(maxWidth: .infinity, alignment: .leading)
                    .scaleEffect(x: w, anchor: .leading)
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { phase = true } }
    }
}

// MARK: - Grid

private struct ModuleGrid<Hero: View>: View {
    let store: HomeStore
    let width: CGFloat
    let hero: GridRect
    @ViewBuilder let heroContent: () -> Hero
    static var rowHeight: CGFloat { HomeGridMetrics.rowHeight }
    static var gap: CGFloat { HomeGridMetrics.gap }

    /// In-flight drag/resize: the module, its live rect in points, and the snapped target.
    @State private var active: (id: UUID, frame: CGRect, target: GridRect)?
    @State private var preview: [UUID: GridRect] = [:]

    private var colWidth: CGFloat { HomeGridMetrics.colWidth(for: width) }
    private func frame(_ r: GridRect, _ colWidth: CGFloat) -> CGRect { HomeGridMetrics.frame(r, colWidth) }

    var body: some View {
        let _ = (store.locked = [hero])
        let layout = store.layout()
        let heroFrame = frame(hero, colWidth)
        ZStack(alignment: .topLeading) {
            if let active {
                // Snapped landing spot.
                let f = frame(active.target, colWidth)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.primary.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])).foregroundStyle(.secondary))
                    .frame(width: f.width, height: f.height)
                    .offset(x: f.minX, y: f.minY)
                    .animation(Motion.snappy, value: active.target)
            }
            ForEach(store.modules) { module in
                let isActive = active?.id == module.id
                let rect = isActive ? active!.frame
                    : frame(preview[module.id] ?? layout[module.id] ?? module.rect, colWidth)
                ModuleCard(module: module, isActive: isActive,
                           onMove: { translation, ended in
                               drag(module, from: layout[module.id] ?? module.rect, translation: translation,
                                    ended: ended, resize: false)
                           },
                           onResize: { translation, ended in
                               drag(module, from: layout[module.id] ?? module.rect, translation: translation,
                                    ended: ended, resize: true)
                           })
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .zIndex(isActive ? 10 : 0)
                    .animation(isActive ? nil : Motion.snappy, value: rect)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
            heroContent()
                .frame(width: heroFrame.width, height: heroFrame.height)
                .offset(x: heroFrame.minX, y: heroFrame.minY)
                .zIndex(5)
        }
        .frame(width: width, height: CGFloat(displayRows(layout)) * (Self.rowHeight + Self.gap), alignment: .topLeading)
        .animation(Motion.snappy, value: store.modules.map(\.id))
        .animation(Motion.snappy, value: hero)
    }

    private func displayRows(_ layout: [UUID: GridRect]) -> Int {
        let all = store.modules.map { preview[$0.id] ?? layout[$0.id] ?? $0.rect } + [hero]
            + (active.map { [$0.target] } ?? [])
        return (all.map { $0.row + $0.h }.max() ?? 0) + (active == nil ? 0 : 2)
    }

    private func drag(_ module: HomeModule, from current: GridRect, translation: CGSize, ended: Bool, resize: Bool) {
        let start = frame(current, colWidth)
        let stepX = colWidth + Self.gap, stepY = Self.rowHeight + Self.gap
        var live = start
        var target = current
        if resize {
            live.size.width = max(start.width + translation.width, colWidth * 2)
            live.size.height = max(start.height + translation.height, Self.rowHeight * 2)
            target.w = Int(((live.width + Self.gap) / stepX).rounded())
            target.h = Int(((live.height + Self.gap) / stepY).rounded())
        } else {
            live.origin.x += translation.width
            live.origin.y += translation.height
            target.col = Int((live.minX / stepX).rounded())
            target.row = Int((live.minY / stepY).rounded())
        }
        target = GridLayout.clamp(target)
        if ended {
            withAnimation(Motion.bouncy) {
                store.commit(module.id, at: target)
                active = nil
                preview = [:]
            }
        } else {
            if active?.target != target {
                let p = store.preview(module.id, at: target)
                withAnimation(Motion.snappy) { preview = p }
            }
            active = (module.id, live, preview[module.id] ?? target)
        }
    }
}

private struct ModuleCard: View {
    @Environment(BrowserState.self) private var browser
    let module: HomeModule
    let isActive: Bool
    let onMove: (CGSize, Bool) -> Void
    let onResize: (CGSize, Bool) -> Void
    @State private var hovering = false

    private var showsChrome: Bool { hovering || isActive }

    var body: some View {
        // Edge-to-edge page; the title bar only floats in while hovering.
        ModuleWebView(module: module)
            .allowsHitTesting(!isActive)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .top) {
                if showsChrome {
                    titleBar
                        .padding(6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showsChrome {
                    // Resize handle.
                    Image(systemName: "arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .glassEffect(.regular, in: .circle)
                        .padding(6)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { onResize($0.translation, false) }
                            .onEnded { onResize($0.translation, true) })
                        .onHover { if $0 { NSCursor.frameResize(position: .bottomRight, directions: .all).push() } else { NSCursor.pop() } }
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
        .scaleEffect(isActive && !Motion.reduceMotion ? 1.02 : 1)
        .shadow(color: .black.opacity(isActive ? 0.3 : 0.1), radius: isActive ? 24 : 8, y: isActive ? 14 : 3)
        .animation(Motion.snappy, value: isActive)
        .onHover { h in withAnimation(Motion.snappy) { hovering = h } }
        .contextMenu {
            Button("Reload") { HomeWebCache.shared.reload(module.id) }
            Button("Zoom In") { setZoom(module.zoom + 0.1) }
            Button("Zoom Out") { setZoom(module.zoom - 0.1) }
            Button("Rename…") { rename() }
            Divider()
            Button("Remove", role: .destructive) { HomeStore.shared.remove(module.id) }
        }
    }

    /// Floating glass bar: drag anywhere on it to move the module.
    private var titleBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            Text(module.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 4)
            button("arrow.clockwise", "Reload") { HomeWebCache.shared.reload(module.id) }
            button("arrow.up.forward.square", "Open as Tab") {
                browser.openFromHome(HomeWebCache.shared.currentURL(module.id) ?? module.url)
            }
            button("xmark", "Remove") { withAnimation(Motion.snappy) { HomeStore.shared.remove(module.id) } }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .glassEffect(.regular, in: .rect(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { onMove($0.translation, false) }
            .onEnded { onMove($0.translation, true) })
        .onHover { if $0 { NSCursor.openHand.push() } else { NSCursor.pop() } }
    }

    private func button(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
            .buttonStyle(SquishButtonStyle()).padding(-5).foregroundStyle(.secondary).help(help)
    }

    private func setZoom(_ z: Double) {
        HomeStore.shared.update(module.id) { $0.zoom = min(1.5, max(0.5, z)) }
    }

    private func rename() {
        let a = NSAlert()
        a.messageText = "Rename Module"
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        f.stringValue = module.title
        a.accessoryView = f
        a.addButton(withTitle: "Rename"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn, !f.stringValue.isEmpty {
            HomeStore.shared.update(module.id) { $0.title = f.stringValue }
        }
    }
}

private struct AddModuleView: View {
    @Environment(BrowserState.self) private var browser
    let done: () -> Void
    @State private var address = ""
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a module").font(.headline)
            TextField("Address, e.g. news.ycombinator.com", text: $address).textFieldStyle(.roundedBorder)
                .onSubmit(addCustom)
            TextField("Title (optional)", text: $title).textFieldStyle(.roundedBorder)
            HStack {
                if let url = browser.selectedTab?.url, !(browser.selectedTab?.isHome ?? true) {
                    Button("Use Current Page") { add(url, browser.selectedTab?.displayTitle ?? "") }
                }
                Spacer()
                Button("Add", action: addCustom).buttonStyle(.glassProminent).disabled(address.isEmpty)
            }
            Divider()
            Text("Suggestions").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(HomeStore.presets, id: \.url) { p in
                    Button { add(URL(string: p.url)!, p.title) } label: {
                        Label(p.title, systemImage: p.symbol).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8).background(.primary.opacity(0.06), in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func addCustom() {
        guard case .url(let url)? = URLInputParser.parse(address) else { return }
        add(url, title)
    }

    private func add(_ url: URL, _ title: String) {
        withAnimation(Motion.bouncy) { _ = HomeStore.shared.add(url: url, title: title) }
        done()
    }
}

/// Point geometry of the home grid.
enum HomeGridMetrics {
    static let rowHeight: CGFloat = 64
    static let gap: CGFloat = 12

    static func colWidth(for width: CGFloat) -> CGFloat {
        (width - gap * CGFloat(GridLayout.columns - 1)) / CGFloat(GridLayout.columns)
    }

    static func frame(_ r: GridRect, _ colWidth: CGFloat) -> CGRect {
        CGRect(x: CGFloat(r.col) * (colWidth + gap), y: CGFloat(r.row) * (rowHeight + gap),
               width: CGFloat(r.w) * colWidth + CGFloat(r.w - 1) * gap,
               height: CGFloat(r.h) * rowHeight + CGFloat(r.h - 1) * gap)
    }
}
