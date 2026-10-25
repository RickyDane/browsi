import SwiftUI

struct MainWindowView: View {
    @Environment(BrowserState.self) private var browser
    @State private var prefs = Preferences.shared
    @State private var sidebarPeek = false

    var body: some View {
        let space = browser.selectedSpace
        let sidebarWidth = prefs.sidebarWidth
        let inset: CGFloat = prefs.edgeToEdgeContent ? 0 : 8
        // Redrawing the full-window background behind a playing video makes it flicker on big high-refresh displays.
        let videoPlaying = browser.selectedTab?.isPlayingMedia == true
            || (browser.floatingPlayer.isActive && browser.floatingPlayer.isPlaying)
        let animateBackground = prefs.animatedBackground && !videoPlaying
        ZStack {
            if prefs.spaceTheme {
                StarfieldView(hue: space.hue, starCount: 320, animated: animateBackground,
                              intensity: prefs.backgroundIntensity)
                    .animation(Motion.smooth, value: space.hue)
            } else {
                MeshBackground(hue: space.hue, animated: animateBackground)
                    .opacity(prefs.backgroundIntensity)
            }

            HStack(spacing: 0) {
                if browser.sidebarVisible {
                    SidebarView()
                        .frame(width: sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                ContentCard(edgeToEdge: prefs.edgeToEdgeContent)
                    .overlay(alignment: .top) {
                        if browser.find.visible, browser.selectedWebTab != nil {
                            FindBar(find: browser.find)
                                .padding(.top, 12)
                                .transition(.move(edge: .top).combined(with: .opacity).combined(with: BlurScaleTransition()))
                        }
                    }
                    .animation(Motion.snappy, value: browser.find.visible)
                    .padding(.vertical, inset)
                    .padding(.trailing, inset)
                    .padding(.leading, browser.sidebarVisible ? 0 : inset)
                if browser.pageAssistantVisible {
                    PageAssistantPanel()
                        .padding(.vertical, max(inset, 8))
                        .padding(.trailing, max(inset, 8))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
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

            if let run = browser.pageAction {
                PageActionSheet(run: run)
                    .id(run.id)
                    .transition(.opacity)
                    .zIndex(9)
            }

            if let setup = browser.watchSetup {
                WatchSetupSheet(setup: setup)
                    .id(setup.id)
                    .transition(.opacity)
                    .zIndex(9)
            }

            if let sheet = browser.appleSignIn, browser.selectedTab === sheet.source {
                AppleSignInSheet(sheet: sheet)
                    .id(sheet.id)
                    .transition(BlurScaleTransition(scale: 0.94, blur: 8))
                    .zIndex(9)
            }

            if browser.palette != .hidden {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(Motion.snappy) { browser.palette = .hidden } }
                    .transition(.opacity)
                // The input row sits exactly in the window's centre; results unfold below it.
                GeometryReader { geo in
                    let inputHeight = CommandPaletteView.inputHeight
                    let top = max(16, geo.size.height / 2 - inputHeight / 2)
                    CommandPaletteView(maxResultsHeight: max(120, geo.size.height - top - inputHeight - 24))
                        .id(browser.palette)
                        .frame(maxWidth: .infinity)
                        .padding(.top, top)
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
        .overlay {
            // Downloads flying from the click point to the downloads button.
            GeometryReader { geo in
                let origin = geo.frame(in: .global).origin
                let target = browser.downloadsButtonFrame.map { CGPoint(x: $0.midX - origin.x, y: $0.midY - origin.y) }
                    ?? CGPoint(x: geo.size.width - 35, y: 35)
                ForEach(browser.downloadFlights) { flight in
                    DownloadFlightView(flight: flight, target: target)
                }
            }
            .allowsHitTesting(false)
        }
        .overlay {
            // Downloads queue: a glass card that grows out of the downloads button (no popover arrow).
            if browser.downloadsVisible { DownloadsPanelLayer() }
        }
        .overlay(alignment: .topTrailing) {
            if browser.downloadsButtonShown {
                DownloadsButton()
                    .padding(.top, 16)
                    .padding(.trailing, 18 + (browser.pageAssistantVisible ? PageAssistantPanel.width + 8 : 0))
                    .transition(.scale(scale: 0.3, anchor: .center).combined(with: .opacity))
            }
        }
        .animation(Motion.bouncy, value: browser.downloadsButtonShown)
        .overlay {
            if let ripple = browser.calmRipple {
                CalmRippleOverlay(ripple: ripple).id(ripple.id)
            }
        }
        .animation(Motion.bouncy, value: browser.downloadsVisible)
        .animation(Motion.snappy, value: browser.palette)
        .animation(Motion.snappy, value: browser.sidebarVisible)
        .animation(Motion.bouncy, value: browser.pageAssistantVisible)
        .animation(Motion.snappy, value: prefs.sidebarWidth)
        .frame(minWidth: 720, minHeight: 480)
        .ignoresSafeArea()
        .background(WindowConfigurator(showTrafficLights: browser.sidebarVisible || sidebarPeek))
        .onChange(of: browser.sidebarVisible) { if $1 { sidebarPeek = false } }
        .onChange(of: browser.selectedTab?.id) {
            browser.find.pageChanged(browser.selectedTab)
            PageWatcher.shared.markSeen(browser.selectedTab?.url)
        }
        .translationTask(browser.translationConfig) { session in
            await browser.runTranslation(with: session)
        }
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
            if let tab, !tab.isHome {
                Rectangle().fill(.background)
                // During in-place Apple sign-in the tab's web view lives in the sheet; the site stays frozen here.
                let signIn = browser.appleSignIn
                let inSheet = signIn?.mode == .inPlace && signIn?.tab === tab
                WebViewHost(tab: tab, claim: !inSheet)
                if inSheet, let backdrop = signIn?.background {
                    Image(nsImage: backdrop).resizable().aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .clipped()
                        .allowsHitTesting(false)
                }
                if tab.showsSnapshot, let snap = tab.snapshot {
                    Image(nsImage: snap).resizable().aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .clipped()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                ProgressGlow(progress: tab.progress, isLoading: tab.isLoading, tint: browser.selectedSpace.color)
                if let storeID = tab.url.flatMap({ ExtensionPackage.storeID(from: $0.absoluteString) }) {
                    VStack {
                        Spacer()
                        StoreInstallBanner(storeID: storeID,
                                           title: tab.title.replacingOccurrences(of: " - Chrome Web Store", with: ""))
                            .padding(.bottom, 22)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(storeID)
                }
            } else {
                // Home page: frosted card so the space's gradient glows through.
                if Preferences.shared.spaceTheme {
                    // Home page is the night sky itself, with shooting stars.
                    StarfieldView(hue: browser.selectedSpace.hue, starCount: 420, shootingStars: true,
                                  animated: Preferences.shared.animatedBackground,
                                  intensity: Preferences.shared.backgroundIntensity)
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                }
                HomeView().id(tab?.id)
            }
        }
        // No implicit/explicit animation leaks into tab swaps (avoids the page "shifting in").
        .transaction { $0.animation = nil }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.primary.opacity(edgeToEdge ? 0 : 0.08)))
        .shadow(color: .black.opacity(edgeToEdge ? 0 : 0.14), radius: 14, y: 4)
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
