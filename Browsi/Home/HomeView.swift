import SwiftUI

/// Personal home page: an AI-powered search bar above a grid of live web modules
/// that can be dragged and resized.
struct HomeView: View {
    @Environment(BrowserState.self) private var browser
    @State private var store = HomeStore.shared
    @State private var search = SmartSearch()
    @State private var editing = false
    @State private var showAdd = false

    static let barHeight: CGFloat = 54

    var body: some View {
        GeometryReader { viewport in
            let half = max(140, (viewport.size.height - Self.barHeight) / 2)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // Upper half: clock, resting just above the bar.
                        VStack(spacing: 0) {
                            Spacer(minLength: 16)
                            header
                            Spacer().frame(height: 26)
                        }
                        .frame(height: half)

                        // The search bar sits exactly in the vertical centre of the page.
                        HomeSearchBar(search: search)

                        // Lower half: the answer unfolds below the bar; modules peek in at the bottom.
                        VStack(spacing: 18) {
                            if search.phase != .idle {
                                SmartAnswerCard(search: search)
                                    .transition(BlurScaleTransition(scale: 0.96, blur: 8).combined(with: .move(edge: .top)))
                            }
                            Spacer(minLength: 0)
                            if !store.modules.isEmpty {
                                Button {
                                    withAnimation(Motion.smooth) { proxy.scrollTo("modules", anchor: .top) }
                                } label: {
                                    Label("Modules", systemImage: "chevron.compact.down")
                                        .labelStyle(.titleAndIcon)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(SquishButtonStyle())
                            }
                        }
                        .padding(.top, 18)
                        .padding(.bottom, 12)
                        .frame(minHeight: half, alignment: .top)

                        VStack(spacing: 14) {
                            HStack {
                                Label("Modules", systemImage: "square.grid.2x2").font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button { showAdd = true } label: { Label("Add", systemImage: "plus") }
                                    .buttonStyle(.glass).controlSize(.small)
                                    .popover(isPresented: $showAdd, arrowEdge: .bottom) { AddModuleView { showAdd = false } }
                            }
                            ModuleGrid(store: store)
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                        .id("modules")
                    }
                    .padding(.horizontal, 28)
                    .frame(maxWidth: 1400)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.automatic)
            }
        }
        .animation(Motion.smooth, value: search.phase)
        .onAppear { HomeWebCache.shared.homeAppeared() }
        .onDisappear { HomeWebCache.shared.homeDisappeared(); search.cancel() }
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
    @State private var query = ""
    @FocusState private var focused: Bool

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
                TextField("", text: $query,
                          prompt: Text(SmartSearch.isAvailable ? "Ask anything, search, or enter an address"
                                                                : "Search or enter an address")
                              .foregroundStyle(.secondary))
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused($focused)
                    .onSubmit(submit)
                if !query.isEmpty {
                    Button("Search \(engine.name)") { openWebSearch() }
                        .buttonStyle(.glass).controlSize(.small)
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("⌘↩ searches \(engine.name) directly")
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 18)
            .frame(height: HomeView.barHeight)
        }
        .frame(maxWidth: 720)
        .glassEffect(.regular, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay {
            if search.phase == .working { IntelligenceGlow(cornerRadius: 18) }
        }
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .animation(Motion.snappy, value: query.isEmpty)
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: query) { if $1.isEmpty { search.reset() } }
    }

    private func submit() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        if case .url(let url)? = URLInputParser.parse(q) {
            browser.openFromHome(url)
        } else if SmartSearch.isAvailable && Preferences.shared.homeSmartAnswers {
            search.run(q, library: browser.library)
        } else {
            openWebSearch()
        }
    }

    private func openWebSearch() {
        guard let url = URLInputParser.url(for: query, engine: Preferences.shared.searchEngine) else { return }
        browser.openFromHome(url)
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

private struct ModuleGrid: View {
    let store: HomeStore
    static let rowHeight: CGFloat = 64
    static let gap: CGFloat = 12

    /// In-flight drag/resize: the module, its live rect in points, and the snapped target.
    @State private var active: (id: UUID, frame: CGRect, target: GridRect)?
    @State private var preview: [UUID: GridRect] = [:]

    var body: some View {
        GeometryReader { geo in
            let colWidth = (geo.size.width - Self.gap * CGFloat(GridLayout.columns - 1)) / CGFloat(GridLayout.columns)
            ZStack(alignment: .topLeading) {
                if let active {
                    // Snapped landing spot.
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.primary.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])).foregroundStyle(.secondary))
                        .frame(width: frame(active.target, colWidth).width, height: frame(active.target, colWidth).height)
                        .offset(x: frame(active.target, colWidth).minX, y: frame(active.target, colWidth).minY)
                        .animation(Motion.snappy, value: active.target)
                }
                ForEach(store.modules) { module in
                    let isActive = active?.id == module.id
                    let rect = isActive ? active!.frame : frame(preview[module.id] ?? module.rect, colWidth)
                    ModuleCard(module: module, isActive: isActive,
                               onMove: { translation, ended in
                                   drag(module, translation: translation, ended: ended, colWidth: colWidth, resize: false)
                               },
                               onResize: { translation, ended in
                                   drag(module, translation: translation, ended: ended, colWidth: colWidth, resize: true)
                               })
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .zIndex(isActive ? 10 : 0)
                        .animation(isActive ? nil : Motion.snappy, value: rect)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
                if store.modules.isEmpty {
                    ContentUnavailableView("No modules yet", systemImage: "square.grid.2x2",
                                           description: Text("Add web pages with “Add” and arrange them however you like."))
                        .frame(width: geo.size.width, height: 260)
                }
            }
        }
        .frame(height: max(260, CGFloat(displayRows) * (Self.rowHeight + Self.gap)))
        .animation(Motion.snappy, value: store.modules.map(\.id))
    }

    private var displayRows: Int {
        let all = store.modules.map { preview[$0.id] ?? $0.rect } + (active.map { [$0.target] } ?? [])
        return (all.map { $0.row + $0.h }.max() ?? 0) + (active == nil ? 0 : 2)
    }

    private func frame(_ r: GridRect, _ colWidth: CGFloat) -> CGRect {
        CGRect(x: CGFloat(r.col) * (colWidth + Self.gap), y: CGFloat(r.row) * (Self.rowHeight + Self.gap),
               width: CGFloat(r.w) * colWidth + CGFloat(r.w - 1) * Self.gap,
               height: CGFloat(r.h) * Self.rowHeight + CGFloat(r.h - 1) * Self.gap)
    }

    private func drag(_ module: HomeModule, translation: CGSize, ended: Bool, colWidth: CGFloat, resize: Bool) {
        let start = frame(module.rect, colWidth)
        let stepX = colWidth + Self.gap, stepY = Self.rowHeight + Self.gap
        var live = start
        var target = module.rect
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

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                Text(module.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                if hovering {
                    Group {
                        button("arrow.clockwise", "Reload") { HomeWebCache.shared.reload(module.id) }
                        button("arrow.up.forward.square", "Open as Tab") {
                            browser.openFromHome(HomeWebCache.shared.currentURL(module.id) ?? module.url)
                        }
                        button("xmark", "Remove") { withAnimation(Motion.snappy) { HomeStore.shared.remove(module.id) } }
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { onMove($0.translation, false) }
                .onEnded { onMove($0.translation, true) })
            .onHover { if $0 { NSCursor.openHand.push() } else { NSCursor.pop() } }

            ModuleWebView(module: module)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12, style: .continuous))
                .padding([.horizontal, .bottom], 4)
                .allowsHitTesting(!isActive)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            // Resize handle.
            Image(systemName: "arrow.down.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(.regularMaterial, in: .circle)
                .opacity(hovering || isActive ? 1 : 0)
                .padding(4)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { onResize($0.translation, false) }
                    .onEnded { onResize($0.translation, true) })
        }
        .scaleEffect(isActive && !Motion.reduceMotion ? 1.02 : 1)
        .shadow(color: .black.opacity(isActive ? 0.3 : 0.1), radius: isActive ? 24 : 8, y: isActive ? 14 : 3)
        .animation(Motion.snappy, value: isActive)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .contextMenu {
            Button("Reload") { HomeWebCache.shared.reload(module.id) }
            Button("Zoom In") { setZoom(module.zoom + 0.1) }
            Button("Zoom Out") { setZoom(module.zoom - 0.1) }
            Button("Rename…") { rename() }
            Divider()
            Button("Remove", role: .destructive) { HomeStore.shared.remove(module.id) }
        }
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
