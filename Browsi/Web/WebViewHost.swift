import SwiftUI
import WebKit

/// Hosts the selected tab's WKWebView. Only one web view is ever attached to the window.
struct WebViewHost: NSViewRepresentable {
    let tab: Tab

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        return v
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let webView = tab.controller?.webView else {
            container.subviews.forEach { $0.removeFromSuperview() }
            return
        }
        if webView.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            webView.frame = container.bounds
            webView.autoresizingMask = [.width, .height]
            container.addSubview(webView)
            DispatchQueue.main.async { webView.window?.makeFirstResponder(webView) }
        }
    }

    static func dismantleNSView(_ container: NSView, coordinator: ()) {
        container.subviews.forEach { $0.removeFromSuperview() }
    }
}
