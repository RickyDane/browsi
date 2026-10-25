import SwiftUI

struct URLBarView: View {
    @Environment(BrowserState.self) private var browser
    @State private var hovering = false

    var body: some View {
        let tab = browser.selectedTab
        let host = tab?.isHome == true ? nil : tab?.url?.host()
        HStack(spacing: 6) {
            Image(systemName: tab?.isSecure == true ? "lock.fill" : tab?.url == nil ? "magnifyingglass" : "lock.open")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .contentTransition(.symbolEffect(.replace))
            Text(addressText(tab) ?? "Search or enter address")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(host == nil ? .secondary : .primary)
                .lineLimit(1)
                .contentTransition(.numericText())
            Spacer(minLength: 0)
            if let storeID = tab?.url.flatMap({ ExtensionPackage.storeID(from: $0.absoluteString) }),
               !ExtensionManager.shared.records.contains(where: { $0.storeID == storeID }) {
                Button {
                    Task {
                        do { try await ExtensionManager.shared.installFromStore(storeID) }
                        catch let e as ExtensionInstallError where e == .cancelled {}
                        catch { browser.showToast("exclamationmark.triangle.fill", error.localizedDescription) }
                    }
                } label: {
                    Label("Add", systemImage: "puzzlepiece.extension.fill").labelStyle(.titleAndIcon)
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.glassProminent).controlSize(.mini)
                .help("Add this extension to Browsi")
                .transition(.scale.combined(with: .opacity))
            }
            if host != nil, let tab {
                TranslateButton(translator: browser.translator(for: tab), tab: tab)
                if PageWatcher.shared.isWatching(tab.url) {
                    Button { browser.showWatchSetup(tab) } label: {
                        Image(systemName: "eye.fill").foregroundStyle(browser.selectedSpace.color)
                    }
                    .buttonStyle(SquishButtonStyle()).padding(-5)
                    .help(PageWatcher.shared.watch(for: tab.url)?.trimmedFocus.map { "Watching for: \($0) — click to edit" }
                          ?? "Watching this page for changes — click to edit")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            if host != nil, SmartSearch.isAvailable {
                Button {
                    if browser.pageAssistantVisible { browser.closePageAssistant() } else { browser.togglePageAssistant(.summary) }
                } label: {
                    Image(systemName: "apple.intelligence")
                        .foregroundStyle(browser.pageAssistantVisible ? AnyShapeStyle(browser.selectedSpace.color)
                                                                      : AnyShapeStyle(.secondary))
                        .symbolEffect(.bounce, value: browser.pageAssistantVisible)
                }
                .buttonStyle(SquishButtonStyle()).padding(-5)
                .help("Summarize this page (⌘⇧S) · Ask about it (⌘⇧E)")
            }
            if host != nil {
                let blocking = ContentBlocker.shared.isEnabled(for: host)
                Button { browser.toggleBlockingForSelectedSite() } label: {
                    Image(systemName: blocking ? "shield.lefthalf.filled" : "shield.slash")
                        .foregroundStyle(blocking ? AnyShapeStyle(browser.selectedSpace.color) : AnyShapeStyle(.secondary))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(SquishButtonStyle()).padding(-5)
                .help(blocking ? "Trackers blocked — click to allow on this site" : "Blocking paused on this site")

                let starred = browser.library.isBookmarked(tab?.url)
                Button { browser.toggleBookmarkForSelectedTab() } label: {
                    Image(systemName: starred ? "star.fill" : "star")
                        .foregroundStyle(starred ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
                        .symbolEffect(.bounce, value: starred)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(SquishButtonStyle()).padding(-5)
                .help("Bookmark (⌘D)")
            }
            ExtensionBarSection()
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .frame(height: 34)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 11, style: .continuous))
        .scaleEffect(hovering && !Motion.reduceMotion ? 1.015 : 1)
        .animation(Motion.bouncy, value: hovering)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(Motion.bouncy) { browser.palette = .editCurrent } }
        .animation(Motion.snappy, value: host)
    }

    private func addressText(_ tab: Tab?) -> String? {
        guard let url = tab?.url, tab?.isHome == false else { return nil }
        if Preferences.shared.showFullURL { return url.absoluteString }
        return url.host()?.replacingOccurrences(of: "www.", with: "")
    }
}

/// Shown when the page is in another language (or translated): translates on device, or restores the original.
private struct TranslateButton: View {
    @Environment(BrowserState.self) private var browser
    let translator: PageTranslator
    let tab: Tab

    var body: some View {
        if translator.offersTranslation || translator.state != .idle {
            let lang = translator.language
            Button { browser.toggleTranslation(tab) } label: {
                if translator.isBusy {
                    ProgressView().controlSize(.mini).frame(width: 14, height: 14)
                } else {
                    Image(systemName: "translate")
                        .foregroundStyle(translator.isTranslated ? AnyShapeStyle(browser.selectedSpace.color) : AnyShapeStyle(.secondary))
                        .symbolEffect(.bounce, value: translator.isTranslated)
                }
            }
            .buttonStyle(SquishButtonStyle()).padding(-5)
            .help(help(lang))
            .contextMenu {
                Button(translator.isTranslated || translator.isBusy ? "Show Original" : "Translate Page") {
                    browser.toggleTranslation(tab)
                }
                if let lang {
                    Toggle("Always Translate \(TranslationLanguages.displayName(lang))", isOn: Binding(
                        get: { Preferences.shared.alwaysTranslate.contains(lang) },
                        set: { browser.setAlwaysTranslate(lang, $0) }))
                }
            }
            .transition(.scale.combined(with: .opacity))
        }
    }

    private func help(_ lang: String?) -> String {
        switch translator.state {
        case .translated: return "Translated on device — click to show the original"
        case .translating(let done, let total) where total > 0: return "Translating… \(done * 100 / total) %"
        case .translating: return "Translating…"
        case .failed(let message): return message
        case .idle:
            return lang.map { "Translate from \(TranslationLanguages.displayName($0)) on device (⌥⌘T)" } ?? "Translate page (⌥⌘T)"
        }
    }
}
