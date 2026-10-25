import SwiftUI

/// Floating glass find bar over the page: literal find (⌘F) or "ask" find (⌘⇧F), which highlights
/// the passages that answer a question.
struct FindBar: View {
    @Environment(BrowserState.self) private var browser
    @Bindable var find: FindInPage
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button { toggleMode() } label: {
                    Image(systemName: find.mode == .ask ? "apple.intelligence" : "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(find.mode == .ask ? AnyShapeStyle(browser.selectedSpace.color) : AnyShapeStyle(.secondary))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 18)
                }
                .buttonStyle(SquishButtonStyle())
                .help(find.mode == .ask ? "Ask mode: find where the page answers a question (Tab for words)"
                                        : "Find words (Tab to ask a question instead)")

                TextField(find.mode == .ask ? "Ask where the page says…" : "Find on page", text: $find.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .focused($focused)
                    .onKeyPress(keys: [.return]) { press in
                        if press.modifiers.contains(.command) { find.ask() }
                        else if find.mode == .ask, find.query.trimmingCharacters(in: .whitespaces) != find.askedQuestion { find.ask() }
                        else { find.next(forward: !press.modifiers.contains(.shift)) }
                        return .handled
                    }
                    .onKeyPress(.escape) { browser.closeFind(); return .handled }
                    .onKeyPress(.tab) { toggleMode(); return .handled }
                    .onChange(of: find.query) { find.queryChanged() }

                status
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()

                HStack(spacing: 2) {
                    Button { find.next(forward: false) } label: { Image(systemName: "chevron.up") }
                        .help("Previous (⇧↩)")
                    Button { find.next(forward: true) } label: { Image(systemName: "chevron.down") }
                        .help("Next (↩)")
                }
                .buttonStyle(SquishButtonStyle())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .disabled(!canStep)

                Button { browser.closeFind() } label: { Image(systemName: "xmark") }
                    .buttonStyle(SquishButtonStyle())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .help("Close (Esc)")
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .glassEffect(.regular.interactive(), in: .capsule)

            if let card = answerCard {
                card
                    .transition(BlurScaleTransition(scale: 0.96, blur: 4).combined(with: .move(edge: .top)))
            }
        }
        .frame(width: 440)
        .animation(Motion.snappy, value: find.askPhase)
        .animation(Motion.snappy, value: find.mode)
        .onAppear { focused = true }
        .onChange(of: find.focusRequest) { focused = true }
    }

    private var canStep: Bool {
        find.mode == .text ? (find.matchCount ?? 0) > 0 : find.hits.count > 1
    }

    private func toggleMode() {
        find.open(find.mode == .ask ? .text : .ask, tab: browser.selectedTab)
    }

    @ViewBuilder private var status: some View {
        switch find.mode {
        case .text:
            if let n = find.matchCount {
                if n == 0 {
                    Text(PageFind.looksLikeQuestion(find.query) && SmartSearch.isAvailable ? "⌘↩ to ask" : "No matches")
                } else {
                    Text(find.currentMatch > 0 ? "\(find.currentMatch) of \(n)" : "\(n) found")
                }
            }
        case .ask:
            switch find.askPhase {
            case .reading, .thinking: ProgressView().controlSize(.small)
            case .answered where !find.hits.isEmpty: Text("\(find.hitIndex + 1) of \(find.hits.count)")
            case .idle where !find.query.isEmpty: Text("↩ to ask")
            default: EmptyView()
            }
        }
    }

    private var answerCard: AnyView? {
        guard find.mode == .ask else { return nil }
        switch find.askPhase {
        case .answered where !find.answer.isEmpty:
            return AnyView(card {
                Label { Text(find.answer).textSelection(.enabled) } icon: {
                    Image(systemName: "sparkle").foregroundStyle(browser.selectedSpace.color)
                }
            })
        case .failed(let message):
            return AnyView(card {
                Label(message, systemImage: "questionmark.circle").foregroundStyle(.secondary)
            })
        case .thinking:
            return AnyView(card {
                Label("Looking for the answer…", systemImage: "sparkle").foregroundStyle(.secondary)
            })
        default:
            return nil
        }
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .font(.system(size: 12.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
    }
}
