import SwiftUI
import WebKit

/// Hosts one WKWebView. The web view is passed in explicitly (not looked up from the tab inside
/// `updateNSView`) so SwiftUI re-runs the update whenever a tab's web view is created or replaced.
struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView?
    /// When false the host leaves the web view alone (e.g. it lives in the floating player,
    /// or a peek is animating out after its web view was promoted to a tab).
    var claim = true

    init(tab: Tab, claim: Bool = true) {
        webView = tab.controller?.webView
        self.claim = claim && !tab.isInFloatingPlayer && !tab.isInElementFullscreen
    }

    func makeNSView(context: Context) -> HostView { HostView() }

    func updateNSView(_ container: HostView, context: Context) {
        guard claim else { container.pending = nil; return }
        guard let webView else {
            container.pending = nil
            container.subviews.forEach { $0.removeFromSuperview() }
            return
        }
        guard webView.superview !== container else { container.pending = nil; return }
        // In element fullscreen WebKit hosts the web view in its own window. Pulling it back here
        // would leave the fullscreen window showing a dead frame that ignores clicks.
        guard webView.fullscreenState == .notInFullscreen else { return }
        // A web view that was on screen before and is re-attached to a host outside any window (a freshly
        // built host, e.g. when coming back from the home page) never repaints once the host enters the
        // window: the page stays blank. Attach only once the host is in a window.
        guard container.window != nil else { container.pending = webView; return }
        container.attach(webView)
    }

    static func dismantleNSView(_ container: HostView, coordinator: ()) {
        container.pending = nil
        container.subviews.forEach { $0.removeFromSuperview() }
    }

    /// Keeps the hosted web view exactly the container's size, even if it was attached at 0×0.
    final class HostView: NSView {
        /// Web view waiting for this host to enter a window (see `updateNSView`).
        weak var pending: WKWebView?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
        }
        required init?(coder: NSCoder) { fatalError() }

        func attach(_ webView: WKWebView) {
            pending = nil
            subviews.forEach { $0.removeFromSuperview() }
            webView.removeFromSuperview()
            webView.frame = bounds
            webView.autoresizingMask = [.width, .height]
            addSubview(webView)
            debugLog("attach \(webView.url?.host() ?? "-") bounds=\(NSStringFromRect(bounds)) inWindow=\(window != nil)")
            DispatchQueue.main.async { webView.window?.makeFirstResponder(webView) }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, let webView = pending else { return }
            if webView.superview === self || webView.fullscreenState != .notInFullscreen { pending = nil; return }
            attach(webView)
        }

        override func layout() {
            super.layout()
            subviews.forEach { if $0.frame != bounds { $0.frame = bounds } }
        }
    }
}
