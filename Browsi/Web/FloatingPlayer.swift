import AppKit
import SwiftUI
import WebKit
import OSLog

private let log = Logger(subsystem: "dev.perlick.browsi", category: "FloatingPlayer")

/// When the user leaves a tab that is playing a video, the tab's own WKWebView is moved into a
/// floating, draggable, resizable panel with the video styled to fill it. Selecting the tab again
/// (or pressing "back to tab") moves the web view back. No reload, playback never stops.
@Observable
final class FloatingPlayer {
    private(set) weak var tab: Tab?
    @ObservationIgnored weak var browser: BrowserState?
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var requestGeneration = 0
    @ObservationIgnored private var panelGeneration = 0
    var isPlaying = true

    var isActive: Bool { tab != nil }

    // MARK: Scripts (run in the isolated client world, so pages can't interfere)

    private static let markAttr = "data-browsi-float"

    /// Finds the largest playing video and *extracts* it: the element is promoted into the
    /// browser's top layer (Popover API), which renders above everything else on the page regardless of
    /// stacking contexts, transforms or fixed headers, and is sized to the viewport. The element is not
    /// moved in the DOM, so the site's player keeps working. Returns [videoWidth, videoHeight] or null.
    private static func popOutJS(request: String) -> String { """
    (() => {
      const vids = [...document.querySelectorAll('video')].filter(v =>
        !v.paused && !v.ended && v.readyState >= 2 && v.videoWidth > 0 && v.videoHeight > 0);
      if (!vids.length) return null;
      vids.sort((a, b) => b.clientWidth * b.clientHeight - a.clientWidth * a.clientHeight);
      const v = vids[0];
      if (v.clientWidth * v.clientHeight < 240 * 135) return null;
      if (!document.getElementById('browsi-float-style')) {
        const s = document.createElement('style');
        s.id = 'browsi-float-style';
        s.textContent = `
          html, body { overflow: hidden !important; background: #000 !important; }
          /* Hide everything except the video (descendants may override visibility; the video does). */
          html[\(markAttr)-active] body * { visibility: hidden !important; }
          html[\(markAttr)-active] { visibility: hidden !important; }
          html[\(markAttr)-active] body video[\(markAttr)], video[\(markAttr)] {
            position: fixed !important; inset: 0 !important; left: 0 !important; top: 0 !important;
            right: 0 !important; bottom: 0 !important; margin: 0 !important; padding: 0 !important;
            border: 0 !important; outline: 0 !important; border-radius: 0 !important;
            width: 100vw !important; height: 100vh !important; min-width: 0 !important; min-height: 0 !important;
            max-width: none !important; max-height: none !important; transform: none !important;
            translate: none !important; scale: none !important; rotate: none !important;
            object-fit: contain !important; object-position: center !important;
            background: #000 !important; opacity: 1 !important; visibility: visible !important;
            filter: none !important; clip-path: none !important; mask: none !important;
            z-index: 2147483647 !important; display: block !important; overflow: hidden !important;
          }
          video[\(markAttr)]::backdrop { background: #000 !important; }`;
        (document.head || document.documentElement).appendChild(s);
      }
      v.setAttribute('\(markAttr)', '');
      v.dataset.browsiFloatRequest = '\(request)';
      document.documentElement.setAttribute('\(markAttr)-active', '');
      if (typeof v.showPopover === 'function') {
        if (!v.hasAttribute('popover')) { v.setAttribute('popover', 'manual'); v.dataset.browsiAddedPopover = '1'; }
        const keepOnTop = () => {
          try { if (v.isConnected && !v.matches(':popover-open')) v.showPopover(); }
          catch (e) { document.documentElement.dataset.browsiPopoverError = String(e); }
        };
        keepOnTop();
        // Sites like YouTube re-parent the player when the viewport shrinks, which closes the
        // popover. Re-open it whenever that happens.
        clearInterval(window.__browsiFloatTimer);
        window.__browsiFloatTimer = setInterval(keepOnTop, 200);
      }
      return [v.videoWidth, v.videoHeight];
    })()
    """ }

    private static let restoreJS = """
    (() => {
      clearInterval(window.__browsiFloatTimer);
      document.querySelectorAll('[\(markAttr)]').forEach(v => {
        try { if (v.matches(':popover-open')) v.hidePopover(); } catch (e) {}
        if (v.dataset.browsiAddedPopover) { v.removeAttribute('popover'); delete v.dataset.browsiAddedPopover; }
        v.removeAttribute('\(markAttr)');
        delete v.dataset.browsiFloatRequest;
      });
      document.documentElement.removeAttribute('\(markAttr)-active');
      delete document.documentElement.dataset.browsiPopoverError;
      document.getElementById('browsi-float-style')?.remove();
      window.dispatchEvent(new Event('resize'));
    })()
    """

    /// Debug/test helper: true when only the extracted video is visible (nothing paints above it).
    static let isExtractedJS = """
    (() => {
      const v = document.querySelector('[\(markAttr)]'); if (!v) return false;
      const W = innerWidth, H = innerHeight;
      const pts = [[W/2,H/2],[8,8],[W-8,8],[8,H-8],[W-8,H-8],[W/2,12]];
      return pts.every(([x,y]) => document.elementFromPoint(x,y) === v);
    })()
    """

    private static let pauseJS = "document.querySelector('[\(markAttr)]')?.pause()"
    private static let toggleJS = """
    (() => { const v = document.querySelector('[\(markAttr)]'); if (!v) return null;
      if (v.paused) { v.play(); return true } v.pause(); return false })()
    """

    // MARK: Lifecycle

    /// WebKit evaluations cannot be cancelled once dispatched. Invalidate their native result;
    /// request-scoped restoration also prevents stale cleanup from undoing a newer extraction.
    func cancelPendingPopOut() {
        requestGeneration += 1
    }

    private func canPopOut(_ tab: Tab, webView: WKWebView) -> Bool {
        guard let browser else { return false }
        return Preferences.shared.floatingVideoEnabled && tab !== browser.selectedTab
            && browser.allTabs.contains(where: { $0 === tab })
            && tab.controller?.webView === webView && !tab.isInElementFullscreen
            && webView.fullscreenState == .notInFullscreen
    }

    /// Called after `tab` stopped being the visible tab.
    func considerPopOut(_ tab: Tab) {
        cancelPendingPopOut()
        debugLog("considerPopOut \(tab.displayTitle) enabled=\(Preferences.shared.floatingVideoEnabled) hasWebView=\(tab.controller != nil)")
        guard Preferences.shared.floatingVideoEnabled, tab !== self.tab,
              let webView = tab.controller?.webView, canPopOut(tab, webView: webView) else { return }
        debugLog("considerPopOut frame=\(NSStringFromRect(webView.frame)) inWindow=\(webView.window != nil)")
        let generation = requestGeneration
        let request = UUID().uuidString
        // Dispatch BEFORE returning to SwiftUI. Starting a Task or asking for playback state
        // first lets the host detach the view, which pauses the video before detection runs.
        webView.evaluateJavaScript(Self.popOutJS(request: request), in: nil, in: .defaultClient) { [weak self] result in
            MainActor.assumeIsolated {
                guard let self, self.requestGeneration == generation,
                      self.canPopOut(tab, webView: webView),
                      case .success(let value) = result,
                      let dims = value as? [Double], dims.count == 2, dims[0] > 0, dims[1] > 0 else {
                    let restore = """
                    (() => {
                      if (document.querySelector('[\(Self.markAttr)]')?.dataset.browsiFloatRequest !== '\(request)') return;
                      \(Self.restoreJS)
                    })()
                    """
                    webView.evaluateJavaScript(restore, in: nil, in: .defaultClient) { _ in }
                    return
                }
                self.present(tab: tab, webView: webView, aspect: NSSize(width: dims[0], height: dims[1]))
            }
        }
    }

    private func present(tab: Tab, webView: WKWebView, aspect: NSSize) {
        if self.tab != nil { close(returnTo: nil) }
        panelGeneration += 1
        debugLog("present: floating \(tab.displayTitle) \(aspect.width)x\(aspect.height)")
        #if DEBUG
        Task {
            try? await Task.sleep(for: .seconds(1))
            let ok = try? await webView.evaluateJavaScript(Self.isExtractedJS, contentWorld: .defaultClient)
            debugLog("extracted=\(String(describing: ok))")
            let diag = try? await webView.evaluateJavaScript("""
              (() => { const v = document.querySelector('[\(Self.markAttr)]'); if (!v) return 'no video';
                const r = v.getBoundingClientRect(); const W = innerWidth, H = innerHeight;
                const d = e => e ? (e.tagName + (e.id ? '#' + e.id : '') + (e.className && typeof e.className === 'string' ? '.' + e.className.split(' ')[0] : '')) : 'null';
                return JSON.stringify({open: v.matches(':popover-open'), pop: v.getAttribute('popover'), rect: [r.x, r.y, r.width, r.height], vp: [W, H],
                  pts: [[W/2,H/2],[8,8],[W-8,8],[8,H-8],[W-8,H-8],[W/2,12]].map(([x,y]) => d(document.elementFromPoint(x,y))),
                  style: v.getAttribute('style'), err: document.documentElement.dataset.browsiPopoverError}) })()
            """, contentWorld: .defaultClient)
            debugLog("extract diag: \(String(describing: diag))")
            if let content = self.panel?.contentView, let host = content.subviews.last {
                let top = NSPoint(x: content.bounds.midX, y: content.bounds.maxY - 3)
                let hit = self.panel?.contentView?.superview?.hitTest(content.convert(top, to: content.superview))
                debugLog("controls frame=\(NSStringFromRect(host.frame)) content=\(NSStringFromRect(content.bounds)) topHit=\(hit.map { String(describing: type(of: $0)) } ?? "nil")")
            }
        }
        #endif
        self.tab = tab
        tab.isInFloatingPlayer = true
        isPlaying = true

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let content = panel.contentView!
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
            // A new session may reuse the panel while the previous close is still fading out.
            // Replace that fade as well as invalidating its completion handler.
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Motion.reduceMotion ? 0.1 : 0.22
                panel.animator().alphaValue = 1
            }
            panel.setFrame(NSRect(origin: panel.frame.origin, size: target.size), display: true, animate: true)
        }
        // Window reparenting can pause WebKit's media. Resume only the video we just captured,
        // never an arbitrary paused element on the page.
        webView.evaluateJavaScript("document.querySelector('[\(Self.markAttr)]')?.play().catch(() => {})", in: nil, in: .defaultClient) { _ in }
    }

    /// Ends the floating session. If `returnTo` is the floating tab, the video keeps playing
    /// and the web view goes back into the browser; otherwise the video is paused.
    func close(returnTo: Tab?) {
        cancelPendingPopOut()
        guard let tab, let panel else { return }
        panelGeneration += 1
        let generation = panelGeneration
        let webView = tab.controller?.webView
        let keepPlaying = returnTo === tab
        self.tab = nil
        tab.isInFloatingPlayer = false
        if let webView {
            if !keepPlaying { webView.evaluateJavaScript(Self.pauseJS, in: nil, in: .defaultClient) { _ in } }
            webView.evaluateJavaScript(Self.restoreJS, in: nil, in: .defaultClient) { _ in }
            // Do not defer ownership cleanup to the fade: a replacement session invalidates
            // that completion and would otherwise leave the old web view behind the new one.
            if !keepPlaying, webView.superview === panel.contentView { webView.removeFromSuperview() }
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Motion.reduceMotion ? 0.1 : 0.22
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                guard self.tab == nil, self.panelGeneration == generation else { return }
                panel.orderOut(nil)
            }
        })
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
        controls.safeAreaRegions = []   // cover the (hidden) title bar strip too
        content.addSubview(controls)
        panel.contentView = content
        // Hide the transparent title bar so it doesn't swallow clicks/hover over the top controls.
        panel.titlebarSeparatorStyle = .none
        panel.standardWindowButton(.closeButton)?.superview?.superview?.isHidden = true
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
        .ignoresSafeArea()
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
