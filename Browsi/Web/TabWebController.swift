import AppKit
import WebKit
import UniformTypeIdentifiers

/// Events a tab reports back to the browser.
protocol TabEventsDelegate: AnyObject {
    func openInNewTab(_ request: URLRequest, from tab: Tab, background: Bool)
    func openPopup(configuration: WKWebViewConfiguration, from tab: Tab) -> WKWebView?
    func tabDidClose(_ tab: Tab)
    func tabDidFinishNavigation(_ tab: Tab)
    func tabTitleDidChange(_ tab: Tab)
    func peek(url: URL, from tab: Tab)
}

/// Owns one WKWebView and mirrors its state into a `Tab`.
final class TabWebController: NSObject {
    let webView: WKWebView
    unowned let tab: Tab
    weak var delegate: TabEventsDelegate?
    /// Peek previews don't record history and can't spawn nested peeks.
    var isPeek = false
    private var observations: [NSKeyValueObservation] = []

    init(tab: Tab, configuration: WKWebViewConfiguration = WebConfigFactory.make(), delegate: TabEventsDelegate?) {
        self.tab = tab
        self.delegate = delegate
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.isInspectable = Preferences.shared.webInspectorEnabled
        webView.customUserAgent = UserAgent.current
        webView.underPageBackgroundColor = .windowBackgroundColor
        webView.pageZoom = tab.zoom
        observe()
        ExtensionManager.shared.didOpen(self)
    }

    deinit {
        observations.forEach { $0.invalidate() }
    }

    private func observe() {
        func watch<V>(_ kp: KeyPath<WKWebView, V>) -> NSKeyValueObservation {
            webView.observe(kp, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.sync() }
            }
        }
        observations = [
            watch(\.title), watch(\.url), watch(\.estimatedProgress), watch(\.isLoading),
            watch(\.canGoBack), watch(\.canGoForward), watch(\.hasOnlySecureContent),
        ]
    }

    private func sync() {
        let oldTitle = tab.title
        if let t = webView.title, !t.isEmpty { tab.title = t }
        if let u = webView.url { tab.url = u }
        tab.progress = webView.estimatedProgress
        tab.isLoading = webView.isLoading
        tab.canGoBack = webView.canGoBack
        tab.canGoForward = webView.canGoForward
        tab.isSecure = webView.url?.scheme == "https" && webView.hasOnlySecureContent
        if oldTitle != tab.title { delegate?.tabTitleDidChange(tab) }
    }

    // MARK: Commands

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }

    func restore(interactionState: Any?, fallback: URL?) {
        if let interactionState {
            webView.interactionState = interactionState
        } else if let fallback {
            load(fallback)
        }
    }

    /// Silences media immediately (used while a view animates out before `tearDown`).
    func silence() {
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)
    }

    /// Stops everything the page is doing. Dropping the last reference to a WKWebView does not
    /// reliably stop audio (other objects/tasks can keep it alive), so pages are unloaded explicitly.
    func tearDown() {
        ExtensionManager.shared.didClose(self)
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        silence()
        webView.closeAllMediaPresentations(completionHandler: nil)
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
        webView.removeFromSuperview()
    }

    func setZoom(_ z: Double) {
        tab.zoom = min(3, max(0.5, z))
        webView.pageZoom = tab.zoom
    }

    func applyContentBlocking() {
        ContentBlocker.shared.apply(to: webView.configuration.userContentController, host: webView.url?.host())
    }
}

// MARK: - WKNavigationDelegate

extension TabWebController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        if action.shouldPerformDownload { return (.download, preferences) }

        if action.navigationType == .linkActivated {
            let flags = action.modifierFlags
            // ⌘-click / middle-click → new tab (⇧ inverts background/foreground)
            if flags.contains(.command) || action.buttonNumber == 2 {
                let background = Preferences.shared.commandClickOpensInBackground != flags.contains(.shift)
                delegate?.openInNewTab(action.request, from: tab, background: background)
                return (.cancel, preferences)
            }
            // ⇧-click → Link Peek
            if flags.contains(.shift), !flags.contains(.option), Preferences.shared.linkPeekEnabled,
               !isPeek, let url = action.request.url {
                delegate?.peek(url: url, from: tab)
                return (.cancel, preferences)
            }
        }

        if let url = action.request.url, let scheme = url.scheme?.lowercased(),
           !["http", "https", "about", "data", "blob", "file", "javascript", "webkit-extension"].contains(scheme) {
            NSWorkspace.shared.open(url)   // mailto:, facetime:, app links…
            return (.cancel, preferences)
        }

        if action.targetFrame?.isMainFrame == true {
            ContentBlocker.shared.apply(to: webView.configuration.userContentController,
                                        host: action.request.url?.host())
        }
        return (.allow, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if !response.canShowMIMEType { return .download }
        if let http = response.response as? HTTPURLResponse,
           let disp = http.value(forHTTPHeaderField: "Content-Disposition"), disp.lowercased().hasPrefix("attachment") {
            return .download
        }
        return .allow
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = DownloadManager.shared
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = DownloadManager.shared
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        sync()
        delegate?.tabDidFinishNavigation(tab)
        Task { [weak self] in
            guard let self else { return }
            if let icon = await FaviconLoader.shared.favicon(for: webView) { self.tab.favicon = icon }
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let host = webView.url?.host(), let icon = FaviconLoader.shared.cached(host: host) {
            tab.favicon = icon
        } else {
            tab.favicon = nil
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    private func showError(_ error: Error) {
        let e = error as NSError
        guard e.code != NSURLErrorCancelled, !(e.domain == "WebKitErrorDomain" && e.code == 102) else { return }
        let failing = (e.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.absoluteString ?? ""
        let html = ErrorPage.html(title: "Can’t open this page", message: e.localizedDescription, url: failing)
        webView.loadHTMLString(html, baseURL: URL(string: failing))
    }
}

// MARK: - WKUIDelegate

extension TabWebController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // target=_blank links with modifiers behave like regular links with modifiers.
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            let flags = navigationAction.modifierFlags
            if flags.contains(.command) || navigationAction.buttonNumber == 2 {
                let background = Preferences.shared.commandClickOpensInBackground != flags.contains(.shift)
                delegate?.openInNewTab(navigationAction.request, from: tab, background: background)
                return nil
            }
            if flags.contains(.shift), Preferences.shared.linkPeekEnabled, !isPeek {
                delegate?.peek(url: url, from: tab)
                return nil
            }
        }
        return delegate?.openPopup(configuration: configuration, from: tab)
    }

    func webViewDidClose(_ webView: WKWebView) {
        delegate?.tabDidClose(tab)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        let a = NSAlert()
        a.messageText = frame.securityOrigin.host
        a.informativeText = message
        await present(a)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let a = NSAlert()
        a.messageText = frame.securityOrigin.host
        a.informativeText = message
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        return await present(a) == .alertFirstButtonReturn
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
        let a = NSAlert()
        a.messageText = frame.securityOrigin.host
        a.informativeText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        a.accessoryView = field
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        return await present(a) == .alertFirstButtonReturn ? field.stringValue : nil
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        guard let window = webView.window else { return panel.runModal() == .OK ? panel.urls : nil }
        return await panel.beginSheetModal(for: window) == .OK ? panel.urls : nil
    }

    @discardableResult
    private func present(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        guard let window = webView.window else { return alert.runModal() }
        return await alert.beginSheetModal(for: window)
    }
}

enum ErrorPage {
    static func html(title: String, message: String, url: String) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        return """
        <!doctype html><meta charset=utf-8><title>\(esc(title))</title>
        <style>
        :root{color-scheme:light dark}
        body{margin:0;height:100vh;display:grid;place-items:center;font:15px -apple-system,system-ui;
             background:radial-gradient(circle at 30% 20%,rgba(140,120,255,.25),transparent 60%),
                        radial-gradient(circle at 80% 80%,rgba(80,180,255,.2),transparent 60%)}
        .c{max-width:440px;text-align:center;padding:40px;border-radius:28px;backdrop-filter:blur(30px);
           background:rgba(127,127,127,.08);border:1px solid rgba(127,127,127,.18);animation:in .5s cubic-bezier(.2,.9,.3,1.2)}
        @keyframes in{from{opacity:0;transform:scale(.94) translateY(8px)}}
        h1{font-size:22px;margin:12px 0 8px} p{opacity:.7;margin:0 0 6px} code{opacity:.5;font-size:12px;word-break:break-all}
        button{margin-top:18px;font:inherit;padding:8px 18px;border-radius:999px;border:0;background:#7d6bfa;color:#fff}
        </style>
        <div class=c><div style="font-size:42px">🌫️</div><h1>\(esc(title))</h1><p>\(esc(message))</p>
        <code>\(esc(url))</code><br><button onclick="location.href=\(esc("\"" + url.replacingOccurrences(of: "\"", with: "") + "\""))">Try Again</button></div>
        """
    }
}
