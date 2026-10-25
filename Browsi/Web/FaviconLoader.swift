import AppKit
import WebKit

/// Fetches & caches favicons by host.
final class FaviconLoader {
    static let shared = FaviconLoader()
    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.requestCachePolicy = .returnCacheDataElseLoad
        c.urlCache = URLCache(memoryCapacity: 4 << 20, diskCapacity: 50 << 20)
        return URLSession(configuration: c)
    }()

    init() { cache.countLimit = 500 }

    func cached(host: String) -> NSImage? { cache.object(forKey: host as NSString) }

    func favicon(for webView: WKWebView) async -> NSImage? {
        guard let pageURL = webView.url, let host = pageURL.host() else { return nil }
        if let img = cached(host: host) { return img }
        if let t = inFlight[host] { return await t.value }

        let js = """
        (() => { const l = [...document.querySelectorAll('link[rel~="icon"], link[rel="apple-touch-icon"]')];
          l.sort((a,b) => (parseInt((b.sizes&&b.sizes.value)||'0')) - (parseInt((a.sizes&&a.sizes.value)||'0')));
          return l.length ? l[0].href : null; })()
        """
        let href = try? await webView.evaluateJavaScript(js) as? String
        let candidates = [href.flatMap(URL.init(string:)),
                          URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL].compactMap { $0 }
        let session = self.session
        let task = Task<NSImage?, Never> {
            for url in candidates {
                if let (data, resp) = try? await session.data(from: url),
                   (resp as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                   let img = NSImage(data: data), img.isValid {
                    img.size = NSSize(width: 32, height: 32)
                    return img
                }
            }
            return nil
        }
        inFlight[host] = task
        let img = await task.value
        inFlight[host] = nil
        if let img { cache.setObject(img, forKey: host as NSString) }
        return img
    }
}
