import Testing
import AppKit
import WebKit
@testable import Browsi

struct ExtensionPackageTests {
    @Test func parsesStoreLinks() {
        let id = "ddkjiahejlhfcafbddmgiahcphecmpfh"
        #expect(ExtensionPackage.storeID(from: "https://chromewebstore.google.com/detail/ublock-origin-lite/\(id)") == id)
        #expect(ExtensionPackage.storeID(from: "https://chromewebstore.google.com/detail/\(id)?hl=de") == id)
        #expect(ExtensionPackage.storeID(from: "https://chrome.google.com/webstore/detail/x/\(id)") == id)
        #expect(ExtensionPackage.storeID(from: id) == id)
        #expect(ExtensionPackage.storeID(from: "https://example.com/\(id)") == nil)
        #expect(ExtensionPackage.storeID(from: "hello") == nil)
    }

    @Test func stripsCRXHeaders() throws {
        let zip = Data([0x50, 0x4B, 0x03, 0x04, 9, 9, 9])
        func le(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 24 & 0xff)] }
        let crx3 = Data(Array("Cr24".utf8) + le(3) + le(5) + [1, 2, 3, 4, 5]) + zip
        #expect(try ExtensionPackage.zipData(fromCRX: crx3) == zip)
        let crx2 = Data(Array("Cr24".utf8) + le(2) + le(2) + le(3) + [1, 2, 7, 7, 7]) + zip
        #expect(try ExtensionPackage.zipData(fromCRX: crx2) == zip)
        #expect(try ExtensionPackage.zipData(fromCRX: zip) == zip)
        #expect(throws: ExtensionInstallError.notAnExtension) { try ExtensionPackage.zipData(fromCRX: Data("nope".utf8)) }
    }
}

@MainActor
@Suite(.serialized)
struct ExtensionRuntimeTests {
    private func page(_ html: String, base: String) async throws -> (NSWindow, Tab, TabWebController) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.orderFront(nil)
        let tab = Tab(url: nil)
        let c = TabWebController(tab: tab, delegate: nil)
        c.webView.frame = window.contentView!.bounds
        window.contentView!.addSubview(c.webView)
        c.webView.loadHTMLString(html, baseURL: URL(string: base))
        for _ in 0..<100 where c.webView.isLoading || c.webView.url == nil { try? await Task.sleep(for: .milliseconds(50)) }
        try? await Task.sleep(for: .milliseconds(400))
        return (window, tab, c)
    }

    /// A local MV3 extension: a content script edits pages and a declarativeNetRequest rule blocks a host.
    @Test func unpackedExtensionRunsContentScriptAndBlocksRequests() async throws {
        let manager = ExtensionManager.shared
        manager.confirmInstall = { _ in true }
        let dir = FileManager.default.temporaryDirectory.appending(path: "ext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("""
        { "manifest_version": 3, "name": "Browsi Test Extension", "version": "1.2.3",
          "permissions": ["declarativeNetRequest"], "host_permissions": ["<all_urls>"],
          "content_scripts": [{ "matches": ["https://ext.browsi.test/*"], "js": ["content.js"], "run_at": "document_end" }],
          "declarative_net_request": { "rule_resources": [{ "id": "r", "enabled": true, "path": "rules.json" }] } }
        """.utf8).write(to: dir.appending(path: "manifest.json"))
        try Data("document.documentElement.dataset.browsiExt = 'ran';".utf8).write(to: dir.appending(path: "content.js"))
        try Data("""
        [{ "id": 1, "priority": 1, "action": { "type": "block" },
           "condition": { "urlFilter": "||example.org^", "resourceTypes": ["xmlhttprequest", "other", "script", "image"] } }]
        """.utf8).write(to: dir.appending(path: "rules.json"))

        let record = try await manager.installFile(dir)
        defer { manager.remove(record.id) }
        let context = try #require(manager.contexts[record.id])
        #expect(context.isLoaded)
        #expect(context.webExtension.displayName == "Browsi Test Extension")
        #expect(context.webExtension.displayVersion == "1.2.3")
        try? await Task.sleep(for: .milliseconds(500))

        let (window, tab, c) = try await page("<p>hi</p>", base: "https://ext.browsi.test/")
        defer { window.orderOut(nil); _ = tab }
        let ran = try await c.webView.evaluateJavaScript("document.documentElement.dataset.browsiExt || 'no'") as? String
        #expect(ran == "ran", "content script injected")

        let result = try await c.webView.callAsyncJavaScript("""
          const probe = async (u) => { try { await fetch(u, { mode: 'no-cors', cache: 'no-store' }); return 'ok'; } catch (e) { return 'blocked'; } };
          return [await probe('https://example.org/'), await probe('https://example.com/')].join(',');
        """, contentWorld: .page) as? String
        #expect(result == "blocked,ok", "declarativeNetRequest rule applied")
    }
}

struct StoreLinkTests {
    @Test func storeSearchURLs() {
        #expect(ExtensionPackage.storeSearchURL("dark mode").absoluteString == "https://chromewebstore.google.com/search/dark%20mode")
        #expect(ExtensionPackage.storeSearchURL("a/b").absoluteString == "https://chromewebstore.google.com/search/a%2Fb")
        #expect(ExtensionPackage.storeSearchURL("  ") == ExtensionPackage.storeHome)
    }
}
