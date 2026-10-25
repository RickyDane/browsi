import SwiftUI

/// ⇧-click Link Peek: the link loads in a floating glass card without leaving the current page.
struct PeekOverlay: View {
    @Environment(BrowserState.self) private var browser
    let peek: PeekState
    @State private var keyMonitor: Any?

    var body: some View {
        let tab = peek.tab
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture { browser.closePeek() }
                .transition(.opacity)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    FaviconView(tab: tab, size: 16)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(tab.displayTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(tab.url?.host() ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { browser.promotePeek() } label: {
                        Label("Open in New Tab", systemImage: "arrow.up.forward.square")
                    }
                    .buttonStyle(.glass)
                    .help("Open in New Tab (⌘↩)")
                    Button { browser.closePeek() } label: { Image(systemName: "xmark").frame(width: 14, height: 14) }
                        .buttonStyle(.glass)
                        .help("Close (Esc)")
                }
                .padding(.horizontal, 14)
                .frame(height: 48)

                ZStack(alignment: .top) {
                    Rectangle().fill(.background)
                    WebViewHost(tab: tab, claim: browser.peek?.tab === tab)
                    ProgressGlow(progress: tab.progress, isLoading: tab.isLoading, tint: browser.selectedSpace.color)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding([.horizontal, .bottom], 8)
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 40, y: 18)
            .padding(.horizontal, 70)
            .padding(.vertical, 44)
            .padding(.leading, browser.sidebarVisible ? Preferences.shared.sidebarWidth : 0)
            .frame(maxWidth: 1400)
            .transition(BlurScaleTransition(scale: 0.88, blur: 10).combined(with: .offset(y: 30)))
        }
        .onAppear(perform: installKeys)
        .onDisappear { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }; keyMonitor = nil }
    }

    /// Esc closes, ⌘↩ promotes — handled here because the web view is first responder.
    private func installKeys() {
        let browser = browser
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let code = event.keyCode
            let command = event.modifierFlags.contains(.command)
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard browser.peek != nil else { return false }
                if code == 53 { browser.closePeek(); return true }
                if code == 36, command { browser.promotePeek(); return true }
                return false
            }
            return handled ? nil : event
        }
    }
}
