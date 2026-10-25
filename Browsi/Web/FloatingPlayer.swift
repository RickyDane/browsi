import AppKit
import SwiftUI
import WebKit

/// When the user leaves a tab that is playing a video, the tab's own WKWebView is moved into a
/// floating, draggable, resizable panel with the video styled to fill it. Selecting the tab again
/// (or pressing "back to tab") moves the web view back. No reload, playback never stops.
@Observable
final class FloatingPlayer {
    private(set) weak var tab: Tab?
    @ObservationIgnored weak var browser: BrowserState?
    @ObservationIgnored private var panel: NSPanel?
    var isPlaying = true

    var isActive: Bool { tab != nil }

    // MARK: Scripts (run in the isolated client world, so pages can't interfere)

    private static let markAttr = "data-browsi-float"

    /// Finds the largest audible playing video, tags it and makes it fill the viewport.
    /// Returns [videoWidth, videoHeight] or null.
    private static let popOutJS = """
    (() => {
      const vids = [...document.querySelectorAll('video')].filter(v =>
        !v.paused && !v.ended && v.readyState > 2 && v.videoWidth > 0 && !v.muted && v.volume > 0);
      if (!vids.length) return null;
      vids.sort((a, b) => b.clientWidth * b.clientHeight - a.clientWidth * a.clientHeight);
      const v = vids[0];
      if (v.clientWidth * v.clientHeight < 240 * 135) return null;
      v.setAttribute('\(markAttr)', '');
      let s = document.getElementById('browsi-float-style');
      if (!s) {
        s = document.createElement('style');
        s.id = 'browsi-float-style';
        s.textContent = `
          html, body { overflow: hidden !important; }
          video[\(markAttr)] { position: fixed !important; inset: 0 !important; left: 0 !important; top: 0 !important;
            width: 100vw !important; height: 100vh !important; max-width: none !important; max-height: none !important;
            transform: none !important; object-fit: contain !important; background: #000 !important;
            z-index: 2147483647 !important; margin: 0 !important; }`;
        (document.head || document.documentElement).appendChild(s);
      }
      return [v.videoWidth, v.videoHeight];
    })()
    """

    private static let restoreJS = """
    (() => {
      document.getElementById('browsi-float-style')?.remove();
      document.querySelectorAll('[\(markAttr)]').forEach(v => v.removeAttribute('\(markAttr)'));
      window.dispatchEvent(new Event('resize'));
    })()
    """

    private static let pauseJS = "document.querySelector('[\(markAttr)]')?.pause()"
    private static let toggleJS = """
    (() => { const v = document.querySelector('[\(markAttr)]'); if (!v) return null;
      if (v.paused) { v.play(); return true } v.pause(); return false })()
    """

    // MARK: Lifecycle

    /// Called after `tab` stopped being the visible tab.
    func considerPopOut(_ tab: Tab) {
        guard Preferences.shared.floatingVideoEnabled, tab !== self.tab,
              let webView = tab.controller?.webView else { return }
        Task {
            guard await webView.requestMediaPlaybackState() == .playing else { return }
            let result = try? await webView.evaluateJavaScript(Self.popOutJS, contentWorld: .defaultClient)
            guard let dims = result as? [Double], dims.count == 2, dims[0] > 0, dims[1] > 0,
                  tab !== browser?.selectedTab, tab.controller?.webView === webView else {
                if result != nil { _ = try? await webView.evaluateJavaScript(Self.restoreJS, contentWorld: .defaultClient) }
                return
            }
            present(tab: tab, webView: webView, aspect: NSSize(width: dims[0], height: dims[1]))
        }
    }

    private func present(tab: Tab, webView: WKWebView, aspect: NSSize) {
        if self.tab != nil { close(returnTo: nil) }
        self.tab = tab
        tab.isInFloatingPlayer = true
        isPlaying = true

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let content = panel.contentView!
        webView.removeFromSuperview()
        webView.frame = content.bounds
        webView.autoresizingMask = [.width, .height]
        content.addSubview(webView, positioned: .below, relativeTo: content.subviews.first)

        // Size: 420pt wide, aspect of the video, bottom-right of the screen.
        let width: CGFloat = 420
        let height = (width * aspect.height / aspect.width).rounded()
        panel.contentAspectRatio = aspect
        let screen = (NSApp.mainWindow?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let target = NSRect(x: screen.maxX - width - 24, y: screen.minY + 24, width: width, height: height)
        let start = target.insetBy(dx: width * 0.06, dy: height * 0.06).offsetBy(dx: 0, dy: -16)

        if !panel.isVisible {
            panel.setFrame(Motion.reduceMotion ? target : start, display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.1)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(NSRect(origin: panel.frame.origin, size: target.size), display: true, animate: true)
        }
    }

    /// Ends the floating session. If `returnTo` is the floating tab, the video keeps playing
    /// and the web view goes back into the browser; otherwise the video is paused.
    func close(returnTo: Tab?) {
        guard let tab, let panel else { return }
        let webView = tab.controller?.webView
        let keepPlaying = returnTo === tab
        self.tab = nil
        tab.isInFloatingPlayer = false
        if let webView {
            if !keepPlaying { webView.evaluateJavaScript(Self.pauseJS, in: nil, in: .defaultClient) { _ in } }
            webView.evaluateJavaScript(Self.restoreJS, in: nil, in: .defaultClient) { _ in }
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Motion.reduceMotion ? 0.1 : 0.22
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                guard self.tab == nil else { return }
                panel.orderOut(nil)
                // If the tab isn't being shown again, detach its web view from the panel.
                if webView?.superview === panel.contentView, !keepPlaying { webView?.removeFromSuperview() }
            }
        })
        if keepPlaying, webView?.superview === panel.contentView { webView?.removeFromSuperview() }
    }

    func backToTab() {
        guard let tab else { return }
        NSApp.activate()
        browser?.select(tab)
    }

    func togglePlayback() {
        guard let webView = tab?.controller?.webView else { return }
        webView.evaluateJavaScript(Self.toggleJS, in: nil, in: .defaultClient) { [weak self] result in
            MainActor.assumeIsolated {
                if case .success(let v) = result, let playing = v as? Bool { self?.isPlaying = playing }
            }
        }
    }

    // MARK: Panel

    private func makePanel() -> NSPanel {
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 236),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .black
        panel.hasShadow = true
        panel.minSize = NSSize(width: 220, height: 124)

        let content = NSView()
        content.wantsLayer = true
        content.layer?.cornerRadius = 14
        content.layer?.masksToBounds = true
        content.layer?.backgroundColor = NSColor.black.cgColor
        let controls = NSHostingView(rootView: FloatingControls(player: self))
        controls.frame = content.bounds
        controls.autoresizingMask = [.width, .height]
        content.addSubview(controls)
        panel.contentView = content
        return panel
    }
}

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Hover controls over the floating video. The whole surface drags the window.
private struct FloatingControls: View {
    let player: FloatingPlayer
    @State private var hovering = false

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .onTapGesture(count: 2) { player.backToTab() }

            if hovering {
                LinearGradient(colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.45)],
                               startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                VStack {
                    HStack {
                        control("xmark", help: "Close & pause") { player.close(returnTo: nil) }
                        Spacer()
                        if let title = player.tab?.displayTitle {
                            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                        Spacer()
                        control("arrow.up.left.and.arrow.down.right", help: "Back to tab") { player.backToTab() }
                    }
                    Spacer()
                    control(player.isPlaying ? "pause.fill" : "play.fill", help: "Play/Pause", size: 18) {
                        player.togglePlayback()
                    }
                    Spacer()
                }
                .padding(10)
                .transition(.opacity)
            }
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.18)) { hovering = h } }
    }

    private func control(_ symbol: String, help: String, size: CGFloat = 12, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size * 2.4, height: size * 2.4)
                .contentTransition(.symbolEffect(.replace))
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
