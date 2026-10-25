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
        self.claim = claim && !tab.isInFloatingPlayer
    }

    func makeNSView(context: Context) -> HostView { HostView() }

    func updateNSView(_ container: HostView, context: Context) {
        guard claim else { return }
        guard let webView else {
            container.subviews.forEach { $0.removeFromSuperview() }
            return
        }
        guard webView.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
        debugLog("attach \(webView.url?.host() ?? "-") bounds=\(NSStringFromRect(container.bounds)) inWindow=\(container.window != nil)")
        DispatchQueue.main.async { webView.window?.makeFirstResponder(webView) }
    }

    static func dismantleNSView(_ container: HostView, coordinator: ()) {
        container.subviews.forEach { $0.removeFromSuperview() }
    }

    /// Keeps the hosted web view exactly the container's size, even if it was attached at 0×0.
    final class HostView: NSView {
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
        }
        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            subviews.forEach { if $0.frame != bounds { $0.frame = bounds } }
        }
    }
}
