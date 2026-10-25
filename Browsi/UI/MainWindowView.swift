import SwiftUI

struct MainWindowView: View {
    @Environment(BrowserState.self) private var browser
    @State private var prefs = Preferences.shared
    @State private var sidebarPeek = false

    var body: some View {
        let space = browser.selectedSpace
        let sidebarWidth = prefs.sidebarWidth
        let inset: CGFloat = prefs.edgeToEdgeContent ? 0 : 8
        ZStack {
            MeshBackground(hue: space.hue, animated: prefs.animatedBackground)
                .opacity(prefs.backgroundIntensity)

            HStack(spacing: 0) {
                if browser.sidebarVisible {
                    SidebarView()
                        .frame(width: sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                ContentCard(edgeToEdge: prefs.edgeToEdgeContent)
                    .padding(.vertical, inset)
                    .padding(.trailing, inset)
                    .padding(.leading, browser.sidebarVisible ? 0 : inset)
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
                            .frame(width: sidebarWidth)
                            .glassEffect(.regular, in: .rect(cornerRadius: 16, style: .continuous))
                            .padding(8)
                            .onHover { if !$0 { withAnimation(Motion.snappy) { sidebarPeek = false } } }
                        Spacer()
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }

            if let peek = browser.peek {
                PeekOverlay(peek: peek)
                    .transition(BlurScaleTransition(scale: 0.94, blur: 8))
                    .zIndex(9)
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
            .padding(.leading, browser.sidebarVisible ? sidebarWidth : 0)
            .zIndex(20)
        }
        .animation(Motion.snappy, value: browser.palette)
        .animation(Motion.snappy, value: browser.sidebarVisible)
        .animation(Motion.snappy, value: prefs.sidebarWidth)
        .frame(minWidth: 720, minHeight: 480)
        .ignoresSafeArea()
        .background(WindowConfigurator(showTrafficLights: browser.sidebarVisible || sidebarPeek))
        .onChange(of: browser.sidebarVisible) { if $1 { sidebarPeek = false } }
    }
}

/// Rounded, shadowed card holding the web content.
/// Tab switches are instant: one persistent host swaps web views without any transition.
private struct ContentCard: View {
    @Environment(BrowserState.self) private var browser
    var edgeToEdge: Bool

    var body: some View {
        let tab = browser.selectedTab
        let radius: CGFloat = edgeToEdge ? 0 : 12
        ZStack(alignment: .top) {
            if let tab {
                Rectangle().fill(.background)
                WebViewHost(tab: tab)
                if tab.showsSnapshot, let snap = tab.snapshot {
                    Image(nsImage: snap).resizable().aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .clipped()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                ProgressGlow(progress: tab.progress, isLoading: tab.isLoading, tint: browser.selectedSpace.color)
                if let impact = browser.impact {
                    ImpactOverlay(impact: impact).id(impact.id)
                }
            } else {
                // Empty space: let the mesh glow through a frosted card.
                Rectangle().fill(.ultraThinMaterial)
                EmptyStateView()
            }
        }
        // No implicit/explicit animation leaks into tab swaps (avoids the page "shifting in").
        .transaction { $0.animation = nil }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.primary.opacity(edgeToEdge ? 0 : 0.08)))
        .shadow(color: .black.opacity(edgeToEdge ? 0 : 0.14), radius: 14, y: 4)
        .modifier(ImpactShake(trigger: browser.impact?.id))
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

/// Makes the title bar transparent so the traffic lights float over the sidebar,
/// and hides them while the sidebar is collapsed.
private struct WindowConfigurator: NSViewRepresentable {
    var showTrafficLights: Bool

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
            Self.setTrafficLights(visible: showTrafficLights, in: w, animated: false)
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let w = nsView.window else { return }
        Self.setTrafficLights(visible: showTrafficLights, in: w, animated: true)
    }

    static func setTrafficLights(visible: Bool, in window: NSWindow, animated: Bool) {
        // In full screen the buttons live in the menu-bar reveal area; leave them alone there.
        let show = visible || window.styleMask.contains(.fullScreen)
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
        guard buttons.contains(where: { $0.isHidden == show }) || !animated else { return }
        if show { buttons.forEach { $0.isHidden = false } }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = animated && !Motion.reduceMotion ? 0.18 : 0
            buttons.forEach { $0.animator().alphaValue = show ? 1 : 0 }
        }, completionHandler: {
            MainActor.assumeIsolated {
                if !show, !(window.standardWindowButton(.closeButton)?.alphaValue ?? 0 > 0) {
                    buttons.forEach { $0.isHidden = true }
                }
            }
        })
    }
}
