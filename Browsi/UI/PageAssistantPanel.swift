import SwiftUI

/// Glass side panel: an Apple Intelligence summary of the current page and questions about it.
struct PageAssistantPanel: View {
    @Environment(BrowserState.self) private var browser
    static let width: CGFloat = 340

    var body: some View {
        VStack(spacing: 0) {
            if let tab = browser.selectedTab, !tab.isHome, tab.url != nil {
                PageAssistantContent(tab: tab, assistant: browser.pageAssistant(for: tab))
                    .id(tab.id)
            } else {
                PanelHeader(title: "Page Summary", subtitle: nil, onRefresh: nil)
                Spacer()
                ContentUnavailableView("Open a web page", systemImage: "doc.text.magnifyingglass",
                                       description: Text("Browsi summarizes it and answers your questions about it."))
                Spacer()
            }
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 16, style: .continuous))
    }
}

private struct PanelHeader: View {
    @Environment(BrowserState.self) private var browser
    let title: String
    let subtitle: String?
    let onRefresh: (() -> Void)?
    var refreshSymbol = "arrow.clockwise"
    var refreshHelp = "Summarize again"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "apple.intelligence")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(browser.selectedSpace.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let onRefresh {
                Button(action: onRefresh) { Image(systemName: refreshSymbol) }
                    .buttonStyle(SquishButtonStyle()).foregroundStyle(.secondary)
                    .help(refreshHelp)
            }
            Button { browser.closePageAssistant() } label: { Image(systemName: "xmark") }
                .buttonStyle(SquishButtonStyle()).foregroundStyle(.secondary)
                .help("Close (Esc)")
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

private struct PageAssistantContent: View {
    @Environment(BrowserState.self) private var browser
    let tab: Tab
    let assistant: PageAssistant
    @State private var question = ""
    @FocusState private var focused: Bool

    static let suggestions = ["What are the key takeaways?", "Explain this simply", "Any important numbers or dates?"]

    var body: some View {
        VStack(spacing: 0) {
            let chatOnly = assistant.summary.isEmpty && assistant.phase != .summarizing
            PanelHeader(title: chatOnly ? "Ask About This Page" : "Page Summary",
                        subtitle: tab.url?.host()?.replacingOccurrences(of: "www.", with: ""),
                        onRefresh: assistant.isBusy ? nil : {
                            assistant.prepare(for: tab, summarize: !chatOnly, force: true)
                            focused = true
                        },
                        refreshSymbol: chatOnly ? "square.and.pencil" : "arrow.clockwise",
                        refreshHelp: chatOnly ? "New chat" : "Summarize again")
            Divider().opacity(0.5)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summarySection
                        ForEach(assistant.turns) { turn in
                            TurnView(turn: turn, assistant: assistant)
                                .id(turn.id)
                                .transition(BlurScaleTransition(scale: 0.96, blur: 4))
                        }
                        if assistant.phase == .ready, assistant.turns.isEmpty {
                            suggestionChips
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.automatic)
                .onChange(of: assistant.turns.last?.answer) {
                    if let id = assistant.turns.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            inputRow
        }
        .animation(Motion.snappy, value: assistant.turns)
        .animation(Motion.smooth, value: assistant.phase)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "browsi-cite", let n = Int(url.absoluteString.dropFirst("browsi-cite:".count)) {
                assistant.reveal(n)
            } else {
                browser.newTab(url: url, background: false)
            }
            return .handled
        })
        .task(id: tab.url) { assistant.prepare(for: tab, summarize: browser.pageAssistantMode == .summary) }
        .onChange(of: browser.pageAssistantMode) {
            assistant.prepare(for: tab, summarize: browser.pageAssistantMode == .summary)
            if browser.pageAssistantMode == .chat { focused = true }
        }
    }

    @ViewBuilder private var summarySection: some View {
        switch assistant.phase {
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.system(size: 12.5)).foregroundStyle(.secondary)
        case .idle, .reading:
            VStack(alignment: .leading, spacing: 10) {
                Text("Reading the page…").font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
                ShimmerLines()
            }
        case .ready where assistant.summary.isEmpty:
            if assistant.turns.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ask anything about this page").font(.system(size: 13, weight: .semibold))
                    Text("Answers come from the page’s text, with citations you can click.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
        case .summarizing, .ready:
            if assistant.summary.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Summarizing…").font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
                    ShimmerLines()
                }
            } else {
                CitedText(text: assistant.summary, assistant: assistant, size: 13)
            }
        }
    }

    private var suggestionChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            if assistant.summary.isEmpty {
                Button { assistant.prepare(for: tab, summarize: true) } label: {
                    Label("Summarize this page", systemImage: "text.append")
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.primary.opacity(0.06), in: .capsule)
                }
                .buttonStyle(.plain)
            }
            ForEach(Self.suggestions, id: \.self) { s in
                Button { assistant.ask(s) } label: {
                    Label(s, systemImage: "sparkle")
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.primary.opacity(0.06), in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .transition(.opacity)
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Ask about this page…", text: $question)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit(send)
                .onKeyPress(.escape) { browser.closePageAssistant(); return .handled }
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 20))
                    .foregroundStyle(canSend ? AnyShapeStyle(browser.selectedSpace.color) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(SquishButtonStyle())
            .disabled(!canSend)
        }
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(12)
        .disabled(assistant.phase != .ready)
        .onAppear { focused = true }
    }

    private var canSend: Bool {
        !question.trimmingCharacters(in: .whitespaces).isEmpty && !assistant.isBusy && assistant.phase == .ready
    }

    private func send() {
        guard canSend else { return }
        assistant.ask(question)
        question = ""
    }
}

private struct TurnView: View {
    let turn: PageAssistant.Turn
    let assistant: PageAssistant

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(turn.question)
                .font(.system(size: 12.5, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.primary.opacity(0.08), in: .rect(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .textSelection(.enabled)
            if let failed = turn.failed {
                Text(failed).font(.system(size: 12.5)).foregroundStyle(.secondary)
            } else if turn.answer.isEmpty {
                ShimmerLines()
            } else {
                CitedText(text: turn.answer, assistant: assistant, size: 13)
            }
        }
    }
}

/// Model Markdown with [n] citations turned into links that scroll the page to the passage.
private struct CitedText: View {
    let text: String
    let assistant: PageAssistant
    var size: CGFloat

    var body: some View {
        let valid = Set(assistant.passages.map(\.number))
        let md = PageText.linkCitations(PageText.bulletize(text), valid: valid)
        let rendered = (try? AttributedString(markdown: md, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        Text(rendered)
            .font(.system(size: size))
            .lineSpacing(3)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
