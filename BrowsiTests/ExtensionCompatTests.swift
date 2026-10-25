import Testing
import AppKit
import WebKit
@testable import Browsi

struct ManifestPatchTests {
    @Test func compatRunsBeforeBackground() {
        let classic = ExtensionPackage.patchManifest(["background": ["service_worker": "bg.js"]])
        #expect((classic?.manifest["background"] as? [String: Any])?["service_worker"] as? String == "browsi-background.js")
        #expect(classic?.wrapper == "importScripts('/browsi-compat.js', '/bg.js');\n")
        let module = ExtensionPackage.patchManifest(["background": ["service_worker": "/js/bg.js", "type": "module"]])
        #expect(module?.wrapper == "import './browsi-compat.js';\nimport '/js/bg.js';\n")
        let mv2 = ExtensionPackage.patchManifest(["background": ["scripts": ["a.js", "b.js"]]])
        #expect((mv2?.manifest["background"] as? [String: Any])?["scripts"] as? [String] == ["browsi-compat.js", "a.js", "b.js"])
        #expect(mv2?.wrapper == nil)
        #expect(ExtensionPackage.patchManifest(["name": "x"]) == nil)
        #expect(ExtensionPackage.patchManifest(["background": ["service_worker": "browsi-background.js"]]) == nil, "idempotent")
    }
}

@MainActor
@Suite(.serialized)
struct ChromeCompatLiveTests {
    private func adRequest() async throws -> String? {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let tab = Tab(url: nil)
        let c = TabWebController(tab: tab, delegate: nil)
        c.webView.frame = window.contentView!.bounds
        window.contentView!.addSubview(c.webView)
        c.webView.loadHTMLString("<p>x</p>", baseURL: URL(string: "https://news.browsi.test/"))
        for _ in 0..<100 where c.webView.isLoading || c.webView.url == nil { try? await Task.sleep(for: .milliseconds(50)) }
        return try await c.webView.callAsyncJavaScript("""
          try { await fetch('https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js', { mode: 'no-cors', cache: 'no-store' }); return 'loaded'; }
          catch (e) { return 'blocked'; }
        """, contentWorld: .page) as? String
    }

    // AdBlock (gighmmpiobklfepjocnamgkkbiglidom) is known not to start in WebKit (duplicate declarations across its scripts).
    @Test(arguments: [("AdGuard", "bgnkhhnnamicmpeenaelnjfhikgbkllg")])
    func chromeAdBlockerStartsAndBlocks(name: String, id: String) async throws {
        let blocking = Preferences.shared.contentBlockingEnabled
        Preferences.shared.contentBlockingEnabled = false   // only the extension may block
        defer { Preferences.shared.contentBlockingEnabled = blocking }
        let manager = ExtensionManager.shared
        manager.confirmInstall = { _ in true }
        let record = try await manager.installFromStore(id)
        defer { manager.remove(record.id) }
        let context = try #require(manager.contexts[record.id])
        try? await Task.sleep(for: .seconds(20))   // background setup + filter/rule registration
        let errors = context.errors.map(\.localizedDescription)
        print("COMPAT", name, "errors:", errors)
        let fatal = errors.filter { $0.contains("TypeError") || $0.contains("ReferenceError") || $0.contains("failed to load") }
        #expect(fatal.isEmpty, "\(name) background started without errors")
        let r = try await adRequest()
        print("COMPAT", name, "ad request:", r ?? "nil")
        #expect(r == "blocked")
    }
}

@MainActor
@Suite(.serialized)
struct SafariExtensionTests {
    /// Builds a minimal Safari web extension app bundle: Fake.app/Contents/PlugIns/Ext.appex.
    private func makeApp(in root: URL) throws -> URL {
        let appex = root.appending(path: "Fake Blocker.app/Contents/PlugIns/Fake Extension.appex/Contents")
        try FileManager.default.createDirectory(at: appex.appending(path: "Resources"), withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "dev.browsi.tests.fake.extension", "CFBundleName": "Fake Extension",
            "CFBundlePackageType": "XPC!",
            "NSExtension": ["NSExtensionPointIdentifier": "com.apple.Safari.web-extension",
                            "NSExtensionPrincipalClass": "SafariWebExtensionHandler"],
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: appex.appending(path: "Info.plist"))
        try Data("""
        { "manifest_version": 3, "name": "Fake Safari Extension", "version": "2.0",
          "content_scripts": [{ "matches": ["https://safari.browsi.test/*"], "js": ["content.js"] }],
          "host_permissions": ["https://safari.browsi.test/*"] }
        """.utf8).write(to: appex.appending(path: "Resources/manifest.json"))
        try Data("document.documentElement.dataset.safariExt = 'ran';".utf8)
            .write(to: appex.appending(path: "Resources/content.js"))
        let bundle = root.appending(path: "Fake Blocker.app/Contents/PlugIns/Fake Extension.appex")
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", "-", bundle.path(percentEncoded: false)]
        try sign.run(); sign.waitUntilExit()
        return bundle
    }

    @Test func discoversAndRunsSafariWebExtension() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "apps-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let appex = try makeApp(in: root)
        let found = ExtensionManager.discoverSafariExtensions(in: [root])
        #expect(found.map(\.name) == ["Fake Extension"])
        #expect(found.first?.appName == "Fake Blocker")

        let manager = ExtensionManager.shared
        manager.confirmInstall = { _ in true }
        let record = try await manager.installSafariExtension(at: appex.path(percentEncoded: false))
        defer { manager.remove(record.id) }
        let context = try #require(manager.contexts[record.id])
        #expect(context.webExtension.displayName == "Fake Safari Extension")
        #expect(FileManager.default.fileExists(atPath: appex.path(percentEncoded: false)), "remove must not delete the app")

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let tab = Tab(url: nil)
        let c = TabWebController(tab: tab, delegate: nil)
        c.webView.frame = window.contentView!.bounds
        window.contentView!.addSubview(c.webView)
        c.webView.loadHTMLString("<p>hi</p>", baseURL: URL(string: "https://safari.browsi.test/"))
        for _ in 0..<100 where c.webView.isLoading || c.webView.url == nil { try? await Task.sleep(for: .milliseconds(50)) }
        try? await Task.sleep(for: .milliseconds(400))
        let ran = try await c.webView.evaluateJavaScript("document.documentElement.dataset.safariExt || 'no'") as? String
        #expect(ran == "ran", "Safari extension content script injected")
    }

    @Test func scanningApplicationsWorksInSandbox() {
        let apps = (try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? []
        print("SAFARI-SCAN apps:", apps.count, "extensions:", ExtensionManager.discoverSafariExtensions().map(\.name))
        #expect(!apps.isEmpty, "sandboxed app can read /Applications")
    }
}
