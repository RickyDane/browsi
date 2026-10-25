import Testing
import AppKit
import WebKit
@testable import Browsi

@MainActor
@Suite(.serialized)
struct MiddleClickTests {
    @Test func middleClickOnHoveredTabClosesIt() {
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        let a = browser.newTab(url: nil)
        let b = browser.newTab(url: nil)
        let closer = MiddleClickCloser()
        closer.hover(a.id, true)
        #expect(closer.handle(isMiddle: true, isUp: false, x: 100, browser: browser))
        #expect(closer.handle(isMiddle: true, isUp: true, x: 100, browser: browser))
        #expect(!browser.allTabs.contains { $0 === a })
        #expect(browser.allTabs.contains { $0 === b })
    }

    @Test func ignoresOtherButtonsPagesAndDrags() {
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        let a = browser.newTab(url: nil)
        let b = browser.newTab(url: nil)
        let closer = MiddleClickCloser()
        closer.hover(a.id, true)
        #expect(!closer.handle(isMiddle: false, isUp: true, x: 100, browser: browser))     // other button
        #expect(!closer.handle(isMiddle: true, isUp: true, x: 900, browser: browser))      // over the page
        _ = closer.handle(isMiddle: true, isUp: false, x: 100, browser: browser)           // press on a…
        closer.hover(a.id, false); closer.hover(b.id, true)
        #expect(!closer.handle(isMiddle: true, isUp: true, x: 100, browser: browser))      // …release on b
        #expect(browser.allTabs.count == 2)
    }

    @Test func noHoverNoClose() {
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        _ = browser.newTab(url: nil)
        let closer = MiddleClickCloser()
        #expect(!closer.handle(isMiddle: true, isUp: false, x: 100, browser: browser))
        #expect(browser.allTabs.count == 1)
    }

    /// A real middle-click on a link inside a WKWebView must open the link in a new tab.
    @Test func middleClickOnLinkOpensNewTab() async throws {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let browser = BrowserState(library: LibraryStore(inMemory: true), restore: false)
        let tab = browser.newTab(url: nil)
        let webView = try #require(tab.controller?.webView)
        webView.frame = window.contentView!.bounds
        window.contentView!.addSubview(webView)
        webView.loadHTMLString("""
            <a href="https://example.com/target" style="position:fixed;inset:0;display:block;font-size:40px">link</a>
            <script>window.__events=[];['mousedown','mouseup','click','auxclick'].forEach(t=>addEventListener(t,e=>__events.push(t+':'+e.button),true))</script>
            """, baseURL: URL(string: "https://example.com/"))
        let deadline = ContinuousClock.now + .seconds(5)
        while webView.isLoading || webView.url == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: .milliseconds(300))

        let p = webView.convert(NSPoint(x: 300, y: 200), to: nil)
        // NSEvent.mouseEvent can't set buttonNumber, so build real middle-button events from CGEvents.
        func cgEvent(_ type: CGEventType) -> NSEvent {
            let cg = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero, mouseButton: .center)!
            cg.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            cg.setIntegerValueField(.mouseEventClickState, value: 1)
            cg.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.windowNumber))
            cg.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window.windowNumber))
            let screen = window.convertPoint(toScreen: p)
            let flipped = CGPoint(x: screen.x, y: (NSScreen.screens.first?.frame.height ?? 0) - screen.y)
            cg.location = flipped
            return NSEvent(cgEvent: cg)!
        }
        let down = cgEvent(.otherMouseDown), up = cgEvent(.otherMouseUp)
        #expect(down.buttonNumber == 2)
        webView.otherMouseDown(with: down)
        webView.otherMouseUp(with: up)

        let opened = await {
            let end = ContinuousClock.now + .seconds(3)
            while ContinuousClock.now < end {
                if browser.allTabs.count == 2 { return true }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return false
        }()
        #expect(opened, "middle-click on a link should open a new tab")
        #expect(browser.allTabs.contains { $0.url?.absoluteString == "https://example.com/target" || $0.controller?.webView.url?.absoluteString == "https://example.com/target" })
        #expect(browser.selectedTab === tab, "middle-click opens in the background by default")
    }
}

struct SmartRenameTests {
    @Test func sanitizeRemovesIllegalCharacters() {
        #expect(SmartRenamer.sanitize("  \"Acme: Invoice / 8823\"  ") == "Acme Invoice 8823")
        #expect(SmartRenamer.sanitize("...") == nil)
        #expect(SmartRenamer.sanitize("Report 📈 Q3") == "Report Q3")
        let long = String(repeating: "word ", count: 40)
        #expect((SmartRenamer.sanitize(long)?.count ?? 0) <= 80)
    }

    @Test func finalNameKeepsOriginalExtension() {
        #expect(SmartRenamer.finalName(suggested: "Acme Invoice 8823", original: "file_8f3a2c.pdf") == "Acme Invoice 8823.pdf")
        #expect(SmartRenamer.finalName(suggested: "Acme Invoice 8823.pdf", original: "x.PDF") == "Acme Invoice 8823.PDF")
        #expect(SmartRenamer.finalName(suggested: "notes", original: "README") == "notes")
        #expect(SmartRenamer.finalName(suggested: "same", original: "same.txt") == nil)
        #expect(SmartRenamer.finalName(suggested: "same", original: "same") == nil)
    }

    @Test func uniqueURLAvoidsCollisions() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data().write(to: dir.appending(path: "A.pdf"))
        #expect(DownloadManager.uniqueURL(in: dir, fileName: "A.pdf").lastPathComponent == "A 2.pdf")
        #expect(DownloadManager.uniqueURL(in: dir, fileName: "B.pdf").lastPathComponent == "B.pdf")
    }

    @MainActor
    @Test(.enabled(if: SmartRenamer.status == .available, "Apple Intelligence not available"))
    func onDeviceModelRenamesUnclearFile() async {
        let ctx = DownloadContext(
            originalName: "file_8f3a2c91.pdf", mimeType: "application/pdf",
            sourceURL: URL(string: "https://billing.acme.example/dl/8f3a2c91"),
            pageTitle: "Billing – Acme Corp", pageURL: URL(string: "https://billing.acme.example/invoices"),
            contentSnippet: "ACME CORP INVOICE Invoice number 8823 Invoice date 2026-10-02 Bill to: Ricky ... Total due 49.00 EUR")
        let name = await SmartRenamer.suggestFileName(for: ctx)
        print("SMART-RENAME →", name ?? "nil")
        #expect(name?.hasSuffix(".pdf") == true)
        #expect(name?.localizedCaseInsensitiveContains("8f3a2c91") == false)
    }
}
