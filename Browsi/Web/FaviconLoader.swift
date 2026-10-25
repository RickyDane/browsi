import AppKit
import WebKit

/// Fetches & caches favicons by host (in memory and on disk, so tabs restored after a relaunch
/// show their icon before they load).
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

    private let directory: URL? = {
        let dir = URL.applicationSupportDirectory.appending(path: "Browsi/Favicons", directoryHint: .isDirectory)
        return (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil ? dir : nil
    }()

    init() { cache.countLimit = 500 }

    private func fileURL(host: String) -> URL? {
        guard let name = host.lowercased().addingPercentEncoding(withAllowedCharacters: .alphanumerics), !name.isEmpty
        else { return nil }
        return directory?.appending(path: name + ".png")
    }

    func cached(host: String) -> NSImage? {
        if let img = cache.object(forKey: host as NSString) { return img }
        guard let url = fileURL(host: host), let img = NSImage(contentsOf: url), img.isValid else { return nil }
        img.size = NSSize(width: 32, height: 32)
        cache.setObject(img, forKey: host as NSString)
        return img
    }

    private func store(_ img: NSImage, host: String) {
        cache.setObject(img, forKey: host as NSString)
        guard let url = fileURL(host: host), let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url, options: .atomic)
    }

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
        if let img { store(img, host: host) }
        return img
    }
}
