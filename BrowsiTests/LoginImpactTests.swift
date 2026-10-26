import Testing
import AppKit
import SwiftUI
import Metal
import WebKit
import AuthenticationServices
@testable import Browsi

private final class AppBundleToken {}

@MainActor
@Suite(.serialized)
struct LoginImpactTests {
    private func loadPage(_ html: String, in window: NSWindow) async throws -> (BrowserState, Browsi.Tab, WKWebView) {
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        let tab = browser.newTab(url: nil)
        let webView = try #require(tab.controller?.webView)
        webView.frame = window.contentView!.bounds
        window.contentView!.addSubview(webView)
        webView.loadHTMLString(html, baseURL: URL(string: "https://login.example.com/"))
        let end = ContinuousClock.now + .seconds(5)
        while (webView.isLoading || webView.url == nil), ContinuousClock.now < end {
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: .milliseconds(200))
        return (browser, tab, webView)
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 800, height: 600), styleMask: [.titled],
                         backing: .buffered, defer: false)
        w.orderFront(nil)
        return w
    }

    @Test func classifiesRealWorldButtons() async throws {
        let window = makeWindow(); defer { window.orderOut(nil) }
        let html = """
        <button id=a1>Sign in with Apple</button>
        <a id=a2 href="#" role=button><img alt="Continue with Apple"></a>
        <div id=a3 role=button aria-label="Sign in with Apple"></div>
        <div id=appleid-signin role=button></div>
        <button id=a4>Mit Apple fortfahren</button>
        <button id=a5 class="btn apple-login">  </button>
        <button id=p1>Sign in with a passkey</button>
        <button id=p2>Use passkey</button>
        <button id=p3>Mit Passkey anmelden</button>
        <input id=p4 type=submit value="Use a security key">
        <button id=p5>Create a passkey</button>
        <button id=n1>Sign in</button>
        <button id=n2>Continue with Google</button>
        <a id=n3 href="https://apple.com">Apple</a>
        <button id=n4>Forgot password?</button>
        <button id=n5>Apple pie recipe</button>
        """
        let (_, _, webView) = try await loadPage(html, in: window)
        let result = try await webView.evaluateJavaScript("""
          JSON.stringify(Object.fromEntries([...document.querySelectorAll('[id]')].map(e => [e.id, window.__browsiClassify(e)])))
        """, contentWorld: .defaultClient) as? String
        let map = try JSONSerialization.jsonObject(with: Data(try #require(result).utf8)) as? [String: String?] ?? [:]
        for id in ["a1", "a2", "a3", "appleid-signin", "a4", "a5"] { #expect(map[id] == "apple", "\(id)") }
        for id in ["p1", "p2", "p3", "p4", "p5"] { #expect(map[id] == "passkey", "\(id)") }
        for id in ["n1", "n2", "n3", "n4", "n5"] { #expect(map[id] == .some(nil), "\(id) must not trigger") }
    }

    @Test func appleClickPlaysPasskeyWaveAtPointer() async throws {
        let window = makeWindow(); defer { window.orderOut(nil) }
        let (browser, tab, webView) = try await loadPage("""
            <button style="position:fixed;left:300px;top:250px;width:200px;height:44px">Sign in with Apple</button>
            """, in: window)
        _ = tab
        let local = NSPoint(x: 400, y: webView.isFlipped ? 272 : webView.bounds.height - 272)   // centre of the button
        func click(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: webView.convert(local, to: nil), modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        webView.mouseDown(with: click(.leftMouseDown))
        webView.mouseUp(with: click(.leftMouseUp))

        let end = ContinuousClock.now + .seconds(3)
        while browser.calmRipple == nil, ContinuousClock.now < end { try? await Task.sleep(for: .milliseconds(30)) }
        let ripple = try #require(browser.calmRipple, "clicking Sign in with Apple must start the same wave as passkeys")
        #expect(abs(ripple.origin.x - 400) < 60 && abs(ripple.origin.y - 272) < 60, "origin \(ripple.origin)")
        #expect(ripple.tabID == tab.id)
        let pageOrigin = try #require(ripple.pageOrigin)
        #expect(abs(pageOrigin.x - 400) < 60 && abs(pageOrigin.y - 272) < 60)
    }

    @Test func untrustedScriptClicksDoNothing() async throws {
        let window = makeWindow(); defer { window.orderOut(nil) }
        let (browser, _, webView) = try await loadPage("<button id=b>Sign in with a passkey</button>", in: window)
        _ = try await webView.evaluateJavaScript("document.getElementById('b').click()")
        try? await Task.sleep(for: .milliseconds(400))
        #expect(browser.calmRipple == nil)
    }

    @Test func gridShaderIsCompiledIntoApp() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let library = try device.makeDefaultLibrary(bundle: Bundle(for: TabWebController.self))
        #expect(library.functionNames.contains("browsiPasskeyGrid"))
    }

    @Test func passkeyStatusMapping() {
        #expect(PasskeySupport.map(entitled: false, .authorized) == .missingEntitlement)
        #expect(PasskeySupport.map(entitled: true, .authorized) == .authorized)
        #expect(PasskeySupport.map(entitled: true, .denied) == .denied)
        #expect(PasskeySupport.map(entitled: true, .notDetermined) == .notDetermined)
        // Test builds are ad-hoc signed without the entitlement.
        #expect(PasskeySupport.shared.status == .missingEntitlement)
    }

    @Test func webAuthnIsExposedToPages() async throws {
        let window = makeWindow(); defer { window.orderOut(nil) }
        let (_, _, webView) = try await loadPage("<p>x</p>", in: window)
        let caps = try await webView.callAsyncJavaScript(
            "return JSON.stringify(await PublicKeyCredential.getClientCapabilities())", contentWorld: .page) as? String
        #expect(caps?.contains(#""passkeyPlatformAuthenticator":true"#) == true)
        #expect(caps?.contains(#""conditionalGet":false"#) == true, "Browsi's built-in authenticator is active")
    }

    // MARK: Passkey cipher grid

    @Test func passkeyGridHoldsWhilePromptIsOpenThenClears() async throws {
        let window = makeWindow(); defer { window.orderOut(nil) }
        let (browser, _, webView) = try await loadPage("<p>login</p>", in: window)
        browser.playCalmRipple(at: CGPoint(x: 400, y: 300), in: webView)
        let ripple = try #require(browser.calmRipple)
        browser.passkeyCeremony(started: true)
        try? await Task.sleep(for: .seconds(CalmRipple.requestGrace + 0.4))
        #expect(browser.calmRipple?.release == nil, "grid must hold while the passkey prompt is open")

        browser.passkeyCeremony(started: false)
        let release = try #require(browser.calmRipple?.release, "finishing the prompt releases the grid")
        #expect(abs(release.timeIntervalSinceNow) < 0.2)
        try? await Task.sleep(for: .seconds(CalmRipple.releaseDuration + 0.3))
        #expect(browser.calmRipple?.id != ripple.id, "overlay removes itself after clearing")
    }

    @Test func passkeyGridReleasesItselfWithoutRequest() async throws {
        let window = makeWindow(); defer { window.orderOut(nil) }
        let (browser, _, webView) = try await loadPage("<p>login</p>", in: window)
        browser.playCalmRipple(at: CGPoint(x: 100, y: 100), in: webView)
        #expect(browser.calmRipple?.release == nil)
        try? await Task.sleep(for: .seconds(CalmRipple.requestGrace + 0.3))
        #expect(browser.calmRipple?.release != nil, "no passkey request → don't hold the grid")
    }

    @Test func nativeCipherHoldsForAppleSheetAndFadesOnClose() async throws {
        let window = makeWindow(); defer { window.orderOut(nil) }
        let (browser, tab, webView) = try await loadPage("<p>login</p>", in: window)
        browser.playCalmRipple(at: CGPoint(x: 100, y: 100), in: webView)
        browser.appleSignIn = AppleSignInState(tab: tab, source: tab, mode: .inPlace)
        try await Task.sleep(for: .seconds(CalmRipple.requestGrace + 0.2))
        #expect(browser.calmRipple?.release == nil, "Apple sign-in keeps the same holding grid")
        browser.endAppleSignIn()
        #expect(browser.calmRipple?.release != nil)
        try await Task.sleep(for: .seconds(CalmRipple.releaseDuration + 0.2))
        #expect(browser.calmRipple == nil)
    }

    @Test func nativeCipherDoesNotStartForAnUnselectedWebView() async throws {
        let window = makeWindow(); defer { window.orderOut(nil) }
        let (browser, _, webView) = try await loadPage("<p>login</p>", in: window)
        _ = browser.newTab(url: nil)
        browser.playCalmRipple(at: .zero, in: webView)
        #expect(browser.calmRipple == nil)
    }

    @Test func nativeCipherCapturesOnlyTheCurrentGenerationAndDiscardsItsSnapshot() async throws {
        let window = makeWindow(); defer { window.orderOut(nil) }
        let (browser, tab, webView) = try await loadPage("<h1>Snapshot fixture</h1>", in: window)
        browser.passkeyCeremony(started: true)
        defer { browser.passkeyCeremony(started: false) }
        browser.playCalmRipple(at: CGPoint(x: 100, y: 100), in: webView)
        browser.playCalmRipple(at: CGPoint(x: 300, y: 200), in: webView)
        let ripple = try #require(browser.calmRipple)
        let timeout = ContinuousClock.now + .seconds(1)
        while browser.calmRipple?.snapshot == nil, ContinuousClock.now < timeout {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(browser.calmRipple?.id == ripple.id)
        #expect(browser.calmRipple?.tabID == tab.id)
        #expect(browser.calmRipple?.pageOrigin == CGPoint(x: 300, y: 200))
        if !Motion.reduceMotion {
            #expect(browser.calmRipple?.snapshot != nil)
        }
        let duration = NativeCipher.settlingDuration(origin: CGPoint(x: 300, y: 200), size: webView.bounds.size)
        try await Task.sleep(for: .seconds(max(0, duration - Date().timeIntervalSince(ripple.start)) + 0.2))
        #expect(browser.calmRipple?.snapshot == nil, "temporary page image must be discarded after the impact")
        #expect(browser.calmRipple?.release == nil, "the grid can hold without retaining a snapshot")
    }

    @Test func nativeCipherWarpActuallyBendsPixelsAndRestoresThem() throws {
        let size = CGSize(width: 160, height: 120)
        func render(age: Double) throws -> NSBitmapImageRep {
            let page = Canvas { context, bounds in
                context.fill(Path(CGRect(origin: .zero, size: bounds)), with: .color(.black))
                for x in stride(from: 0, to: 160, by: 8) {
                    context.fill(Path(CGRect(x: x, y: 0, width: 3, height: 120)), with: .color(.white))
                }
            }
            .frame(width: size.width, height: size.height)
            .layerEffect(ShaderLibrary.default.browsiPasskeyWarp(
                .float2(size), .float2(CGPoint(x: 30, y: 30)), .float(age),
                .float(1e6), .float(0.75), .float(NativeCipher.depth)),
                maxSampleOffset: CGSize(width: 18, height: 14))
            let renderer = ImageRenderer(content: page)
            renderer.scale = 1
            return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        }
        let before = try render(age: 0)
        let during = try render(age: 1)
        let after = try render(age: 10)
        var bending = 0.0, remaining = 0.0
        for y in 0..<120 {
            for x in 0..<160 {
                let a = try #require(before.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let b = try #require(during.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let c = try #require(after.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                bending += abs(a.redComponent - b.redComponent)
                remaining += abs(a.redComponent - c.redComponent)
            }
        }
        #expect(bending > 10, "a true page warp, not only a grid overlay")
        #expect(remaining < 160 * 120 * 0.002, "the impact must not leave the page pushed down")
    }

    @Test func nativeCipherGridIsWhiteAndStillWhileHolding() throws {
        let ripple = CalmRipple(origin: CGPoint(x: 20, y: 20))
        func render(at t: Double) throws -> NSBitmapImageRep {
            let renderer = ImageRenderer(content: CalmRippleFrame(ripple: ripple, t: t).frame(width: 120, height: 80))
            renderer.scale = 1
            return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        }
        let first = try render(at: 4)
        let later = try render(at: 5)
        var whiteDots = 0
        for y in 0..<80 {
            for x in 0..<120 {
                let a = try #require(first.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let b = try #require(later.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                #expect(a == b, "holding grid must not flicker or breathe")
                if a.alphaComponent > 0.5 {
                    #expect(abs(a.redComponent - a.blueComponent) < 0.04, "white, not the space's accent color")
                    whiteDots += 1
                }
            }
        }
        #expect(whiteDots > 0)
    }

    @Test func instantAnswerStillShowsMinimumHold() async throws {
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        browser.calmRipple = CalmRipple(origin: .zero)
        // A real authenticator call (rejected at once: unknown type) must start and end the hold.
        _ = await PasskeyAuthenticator.handle(["type": "nope"], origin: WebOrigin(scheme: "https", host: "x.example", port: 443),
                                              sameOriginAsTop: true)
        let ripple = try #require(browser.calmRipple)
        let release = try #require(ripple.release)
        #expect(abs(release.timeIntervalSince(ripple.start) - CalmRipple.minimumHold) < 0.05)
    }

    @Test func passkeyGridRendersHoldAndClearsCompletely() throws {
        func alphaAt(_ ripple: CalmRipple, t: Double, _ points: [CGPoint]) throws -> [Int] {
            let renderer = ImageRenderer(content: CalmRippleFrame(ripple: ripple, t: t).frame(width: 600, height: 400))
            renderer.scale = 1
            let cg = try #require(renderer.cgImage)
            let rep = NSBitmapImageRep(cgImage: cg)
            return points.map { p in
                // Max alpha in a 12×12 cell around the point (the grid is made of thin lines and dots).
                var m = 0
                for dx in 0..<12 { for dy in 0..<12 {
                    m = max(m, Int((rep.colorAt(x: Int(p.x) + dx, y: Int(p.y) + dy)?.alphaComponent ?? 0) * 255))
                } }
                return m
            }
        }
        var ripple = CalmRipple(origin: CGPoint(x: 20, y: 20))
        let near = CGPoint(x: 60, y: 60), far = CGPoint(x: 580, y: 380)
        let holding = try alphaAt(ripple, t: 1.0, [near, far])
        #expect(holding[0] > 8, "grid covers the area the wave has passed")
        #expect(holding[1] == 0, "nothing ahead of the wave")
        ripple.release = ripple.start.addingTimeInterval(1.0)
        let done = try alphaAt(ripple, t: 1.0 + CalmRipple.releaseDuration + 0.05, [near, far])
        #expect(done == [0, 0], "fully clear after release")
    }

    @Test func passkeyGridShaderIsCompiledIntoApp() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let library = try device.makeDefaultLibrary(bundle: Bundle(for: TabWebController.self))
        #expect(library.functionNames.contains("browsiPasskeyGrid"))
        #expect(library.functionNames.contains("browsiPasskeyWarp"))
    }
}
