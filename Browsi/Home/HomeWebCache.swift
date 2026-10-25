import SwiftUI
import WebKit

/// Keeps one WKWebView per home module alive while the home page comes and goes,
/// so modules don't reload on every tab switch. Released under memory pressure while hidden.
final class HomeWebCache: NSObject {
    static let shared = HomeWebCache()
    weak var browser: BrowserState?
    private var views: [UUID: WKWebView] = [:]
    private var visibleHomes = 0

    func webView(for module: HomeModule) -> WKWebView {
        if let v = views[module.id] {
            if abs(v.pageZoom - module.zoom) > 0.001 { v.pageZoom = module.zoom }
            return v
        }
        let v = WKWebView(frame: .zero, configuration: WebConfigFactory.make())
        v.navigationDelegate = self
        v.uiDelegate = self
        v.customUserAgent = UserAgent.current
        v.pageZoom = module.zoom
        v.allowsBackForwardNavigationGestures = false
        v.underPageBackgroundColor = .clear
        v.load(URLRequest(url: module.url))
        views[module.id] = v
        return v
    }

    func reload(_ id: UUID) { views[id]?.reload() }

    func currentURL(_ id: UUID) -> URL? { views[id]?.url }

    func drop(_ id: UUID) {
        guard let v = views.removeValue(forKey: id) else { return }
        v.stopLoading()
        v.pauseAllMediaPlayback(completionHandler: nil)
        v.loadHTMLString("", baseURL: nil)
        v.removeFromSuperview()
    }

    func homeAppeared() { visibleHomes += 1 }
    func homeDisappeared() { visibleHomes = max(0, visibleHomes - 1) }

    /// Frees all module web views if no home page is on screen.
    func purgeIfHidden() {
        guard visibleHomes == 0 else { return }
        views.keys.forEach(drop)
    }
}

extension HomeWebCache: WKNavigationDelegate, WKUIDelegate {
    /// Clicking a link inside a module opens it as a real tab instead of navigating the module.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        if action.navigationType == .linkActivated, action.targetFrame?.isMainFrame != false,
           let url = action.request.url, ["http", "https"].contains(url.scheme ?? "") {
            let background = action.modifierFlags.contains(.command) || action.buttonNumber == 2
            browser?.openFromHome(url, background: background)
            return (.cancel, preferences)
        }
        return (.allow, preferences)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { browser?.openFromHome(url, background: false) }
        return nil
    }
}

/// Hosts a module's cached web view (re-parented like `WebViewHost`).
struct ModuleWebView: NSViewRepresentable {
    let module: HomeModule

    func makeNSView(context: Context) -> WebViewHost.HostView { WebViewHost.HostView() }

    func updateNSView(_ container: WebViewHost.HostView, context: Context) {
        let webView = HomeWebCache.shared.webView(for: module)
        guard webView.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }

    static func dismantleNSView(_ container: WebViewHost.HostView, coordinator: ()) {
        container.subviews.forEach { $0.removeFromSuperview() }
    }
}
