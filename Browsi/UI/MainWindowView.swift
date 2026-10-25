import SwiftUI

struct MainWindowView: View {
    @Environment(BrowserState.self) private var browser
    @State private var prefs = Preferences.shared
    @State private var sidebarPeek = false

    var body: some View {
        let space = browser.selectedSpace
        ZStack {
            MeshBackground(hue: space.hue, animated: prefs.animatedBackground)
                .opacity(0.85)

            HStack(spacing: 0) {
                if browser.sidebarVisible {
                    SidebarView()
                        .frame(width: 252)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                ContentCard()
                    .padding(.vertical, 8)
                    .padding(.trailing, 8)
                    .padding(.leading, browser.sidebarVisible ? 0 : 8)
            }

            if !browser.sidebarVisible {
                // Hover the left edge to peek the sidebar.
                HStack(spacing: 0) {
                    Color.clear.frame(width: 8).contentShape(Rectangle())
                        .onHover { if $0 { withAnimation(Motion.snappy) { sidebarPeek = true } } }
                    Spacer()
                }
                if sidebarPeek {
                    HStack(spacing: 0) {
                        SidebarView()
                            .frame(width: 252)
                            .glassEffect(.regular, in: .rect(cornerRadius: 16, style: .continuous))
                            .padding(8)
                            .onHover { if !$0 { withAnimation(Motion.snappy) { sidebarPeek = false } } }
                        Spacer()
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }

            if browser.palette != .hidden {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(Motion.snappy) { browser.palette = .hidden } }
                    .transition(.opacity)
                VStack {
                    CommandPaletteView()
                        .id(browser.palette)
                        .padding(.top, 90)
                    Spacer()
                }
                .transition(BlurScaleTransition())
                .zIndex(10)
            }

            VStack {
                if let offer = browser.pendingPasswordSave {
                    SavePasswordBanner(offer: offer)
                        .transition(.move(edge: .top).combined(with: .opacity).combined(with: BlurScaleTransition()))
                }
                Spacer()
                if let toast = browser.toast {
                    ToastView(toast: toast)
                        .id(toast.id)
                        .transition(BlurScaleTransition(scale: 0.7).combined(with: .move(edge: .bottom)))
                        .padding(.bottom, 24)
                }
            }
            .padding(.top, 16)
            .frame(maxWidth: .infinity)
            .padding(.leading, browser.sidebarVisible ? 252 : 0)
            .zIndex(20)
        }
        .animation(Motion.snappy, value: browser.palette)
        .animation(Motion.snappy, value: browser.sidebarVisible)
        .frame(minWidth: 720, minHeight: 480)
        .ignoresSafeArea()
        .background(WindowConfigurator())
    }
}

/// Rounded, shadowed card holding the web content.
private struct ContentCard: View {
    @Environment(BrowserState.self) private var browser

    var body: some View {
        let tab = browser.selectedTab
        ZStack(alignment: .top) {
            if tab == nil {
                // Empty space: let the mesh glow through a frosted card.
                Rectangle().fill(.ultraThinMaterial)
            } else {
                Rectangle().fill(.background)
            }
            if let tab {
                ZStack {
                    WebViewHost(tab: tab)
                    if let snap = tab.snapshot, tab.isSuspended || tab.isLoading {
                        Image(nsImage: snap).resizable().aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .clipped()
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .id(tab.id)
                .transition(.opacity)
                ProgressGlow(progress: tab.progress, isLoading: tab.isLoading, tint: browser.selectedSpace.color)
            } else {
                EmptyStateView()
            }
        }
        .animation(.easeInOut(duration: 0.16), value: tab?.id)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 4)
    }
}

private struct EmptyStateView: View {
    @Environment(BrowserState.self) private var browser
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: browser.selectedSpace.symbol)
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(browser.selectedSpace.color.gradient)
                .symbolEffect(.breathe, options: .repeating)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
            Text(browser.selectedSpace.name).font(.title2.weight(.semibold))
            Button("New Tab  ⌘T") { browser.palette = .newTab }
                .buttonStyle(.glass)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { withAnimation(Motion.bouncy.delay(0.05)) { appeared = true } }
    }
}

struct ToastView: View {
    let toast: Toast
    var body: some View {
        Label(toast.text, systemImage: toast.symbol)
            .font(.system(size: 13, weight: .medium))
            .symbolEffect(.bounce, value: toast.id)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
    }
}

/// Makes the title bar transparent so the traffic lights float over the sidebar.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.isMovableByWindowBackground = true
            w.backgroundColor = .windowBackgroundColor
            w.tabbingMode = .disallowed
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
