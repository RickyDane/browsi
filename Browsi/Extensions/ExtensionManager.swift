import AppKit
import WebKit

/// An installed extension (the package lives in `ExtensionManager.directory`).
nonisolated struct InstalledExtension: Codable, Identifiable, Equatable, Sendable {
    var id: UUID                // also the extension context's uniqueIdentifier (keeps its storage)
    var fileName: String        // ZIP file or folder inside the extensions directory
    var enabled: Bool
    var storeID: String?        // Chrome Web Store ID, if installed from there
    var installed: Date
}

nonisolated enum ExtensionInstallError: LocalizedError, Equatable {
    case notAnExtension, downloadFailed(String), cancelled, invalid(String)

    var errorDescription: String? {
        switch self {
        case .notAnExtension: "That isn’t a browser extension (expected a Chrome Web Store link, .crx, .zip or folder)."
        case .downloadFailed(let m): "Couldn’t download the extension: \(m)"
        case .cancelled: "Installation cancelled."
        case .invalid(let m): "The extension couldn’t be loaded: \(m)"
        }
    }
}

/// Pure helpers for Chrome Web Store packages (unit tested).
nonisolated enum ExtensionPackage {
    /// Extracts the 32-letter extension ID from a Chrome Web Store link (or a bare ID).
    static func storeID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.wholeMatch(of: /[a-p]{32}/) != nil { return trimmed }
        guard let url = URL(string: trimmed), let host = url.host()?.lowercased(),
              host == "chromewebstore.google.com" || (host == "chrome.google.com" && url.path().hasPrefix("/webstore")) else { return nil }
        return url.pathComponents.last { $0.wholeMatch(of: /[a-p]{32}/) != nil }
    }

    static let storeHome = URL(string: "https://chromewebstore.google.com/category/extensions")!

    static func storeSearchURL(_ query: String) -> URL {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) else {
            return storeHome
        }
        return URL(string: "https://chromewebstore.google.com/search/\(encoded)")!
    }

    static func downloadURL(storeID: String) -> URL {
        var c = URLComponents(string: "https://clients2.google.com/service/update2/crx")!
        c.queryItems = [
            URLQueryItem(name: "response", value: "redirect"),
            URLQueryItem(name: "prodversion", value: "138.0.7204.0"),
            URLQueryItem(name: "acceptformat", value: "crx2,crx3"),
            URLQueryItem(name: "x", value: "id=\(storeID)&installsource=ondemand&uc"),
        ]
        return c.url!
    }

    /// CRX (v2/v3) → the ZIP inside it. A plain ZIP is returned unchanged.
    static func zipData(fromCRX raw: Data) throws -> Data {
        let data = Data(raw)
        if data.starts(with: [0x50, 0x4B]) { return data }   // "PK"
        guard data.count > 16, data.starts(with: Array("Cr24".utf8)) else { throw ExtensionInstallError.notAnExtension }
        func u32(_ o: Int) -> Int { Int(data[o]) | Int(data[o + 1]) << 8 | Int(data[o + 2]) << 16 | Int(data[o + 3]) << 24 }
        let start: Int
        switch u32(4) {
        case 3: start = 12 + u32(8)
        case 2: start = 16 + u32(8) + u32(12)
        default: throw ExtensionInstallError.notAnExtension
        }
        guard start < data.count, data[start...].starts(with: [0x50, 0x4B]) else { throw ExtensionInstallError.notAnExtension }
        return data.subdata(in: start..<data.count)
    }
}

/// Loads and manages Safari/Chrome-style web extensions (WKWebExtension, MV2 + MV3).
@Observable
final class ExtensionManager: NSObject {
    static let shared = ExtensionManager()

    @ObservationIgnored let controller: WKWebExtensionController
    @ObservationIgnored weak var browser: BrowserState?
    @ObservationIgnored let window = ExtensionWindowAdapter()
    private(set) var records: [InstalledExtension] = []
    private(set) var contexts: [UUID: WKWebExtensionContext] = [:]
    private(set) var loadErrors: [UUID: String] = [:]
    /// Bumped when an action's icon/badge changes so toolbar buttons refresh.
    private(set) var actionRevision = 0
    var status: String?
    /// Toolbar button frames (window coordinates, top-left origin) for anchoring popups.
    @ObservationIgnored var actionAnchors: [UUID: CGRect] = [:]

    /// Approves an install (shows name + requested access). Replaced in tests.
    @ObservationIgnored var confirmInstall: @MainActor (WKWebExtension) async -> Bool = { ext in
        let alert = NSAlert()
        alert.messageText = "Add “\(ext.displayName ?? "extension")” to Browsi?"
        var lines: [String] = []
        let hosts = ext.allRequestedMatchPatterns.map(\.string).sorted()
        if hosts.contains(where: { $0.contains("<all_urls>") || $0.hasPrefix("*://*/") }) {
            lines.append("• Read and change all your data on all websites")
        } else if !hosts.isEmpty {
            lines.append("• Read and change your data on: " + hosts.prefix(6).joined(separator: ", ") + (hosts.count > 6 ? "…" : ""))
        }
        let perms = ext.requestedPermissions.map(\.rawValue).sorted()
        if !perms.isEmpty { lines.append("• Permissions: " + perms.joined(separator: ", ")) }
        alert.informativeText = lines.isEmpty ? "This extension doesn’t request special access." : lines.joined(separator: "\n")
        if let icon = ext.icon(for: CGSize(width: 64, height: 64)) { alert.icon = icon }
        alert.addButton(withTitle: "Add Extension")
        alert.addButton(withTitle: "Cancel")
        if let w = NSApp.keyWindow { return await alert.beginSheetModal(for: w) == .alertFirstButtonReturn }
        return alert.runModal() == .alertFirstButtonReturn
    }

    static let featured: [(name: String, id: String, symbol: String, blurb: String)] = [
        ("uBlock Origin Lite", "ddkjiahejlhfcafbddmgiahcphecmpfh", "shield.lefthalf.filled", "Efficient ad & tracker blocker"),
        ("Dark Reader", "eimadpbcbfnmbkopoojfekhnkhdbieeh", "moon.fill", "Dark mode for every website"),
        ("SponsorBlock", "mnjggcdmjocbbbhaepdhchncahnbgone", "forward.fill", "Skip sponsor segments on YouTube"),
        ("Return YouTube Dislike", "gebbhagfogifgggkldgodflihgfeippi", "hand.thumbsdown.fill", "Shows YouTube dislike counts"),
        ("Bitwarden", "nngceckbapebfimnlniiiahkandclblb", "lock.shield.fill", "Open-source password manager"),
    ]

    static var directory: URL {
        let dir = SessionStore.fileURL.deletingLastPathComponent().appending(path: "Extensions", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private static var recordsURL: URL { SessionStore.fileURL.deletingLastPathComponent().appending(path: "extensions.json") }
    private let persist: Bool

    init(persist: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil) {
        self.persist = persist
        let configuration = persist
            ? WKWebExtensionController.Configuration(identifier: UUID(uuidString: "6B0F5B0E-8E2A-4C59-9C1B-0B5E1A1D2C3E")!)
            : WKWebExtensionController.Configuration.nonPersistent()
        controller = WKWebExtensionController(configuration: configuration)
        super.init()
        controller.delegate = self
        if persist, let data = try? Data(contentsOf: Self.recordsURL),
           let saved = try? JSONDecoder().decode([InstalledExtension].self, from: data) {
            records = saved
        }
    }

    func start(browser: BrowserState) {
        self.browser = browser
        controller.didOpenWindow(window)
        controller.didFocusWindow(window)
        Task { for r in records where r.enabled { await load(r) } }
    }

    // MARK: Loading

    func url(of record: InstalledExtension) -> URL { Self.directory.appending(path: record.fileName) }

    @discardableResult
    func load(_ record: InstalledExtension) async -> Bool {
        guard contexts[record.id] == nil else { return true }
        do {
            let ext = try await WKWebExtension(resourceBaseURL: url(of: record))
            let context = WKWebExtensionContext(for: ext)
            context.uniqueIdentifier = record.id.uuidString
            context.isInspectable = Preferences.shared.webInspectorEnabled
            // The user approved the requested access when installing.
            for p in ext.requestedPermissions { context.setPermissionStatus(.grantedExplicitly, for: p) }
            for m in ext.allRequestedMatchPatterns { context.setPermissionStatus(.grantedExplicitly, for: m) }
            try controller.load(context)
            contexts[record.id] = context
            loadErrors[record.id] = nil
            // Tell the extension about tabs that already exist.
            for tab in browser?.allTabs ?? [] { if let c = tab.controller { context.didOpenTab(c) } }
            return true
        } catch {
            loadErrors[record.id] = error.localizedDescription
            debugLog("extension load failed: \(error)")
            return false
        }
    }

    func unload(_ id: UUID) {
        guard let context = contexts.removeValue(forKey: id) else { return }
        try? controller.unload(context)
    }

    // MARK: Installing

    /// Installs from a Chrome Web Store link/ID, a .crx/.zip file, or an unpacked folder.
    @discardableResult
    func install(from input: String) async throws -> InstalledExtension {
        if let id = ExtensionPackage.storeID(from: input) { return try await installFromStore(id) }
        let url = input.hasPrefix("/") ? URL(fileURLWithPath: input) : URL(string: input)
        guard let url, url.isFileURL else { throw ExtensionInstallError.notAnExtension }
        return try await installFile(url)
    }

    @discardableResult
    func installFromStore(_ storeID: String) async throws -> InstalledExtension {
        if let existing = records.first(where: { $0.storeID == storeID }) { return existing }
        status = "Downloading…"
        defer { status = nil }
        let (data, response) : (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(from: ExtensionPackage.downloadURL(storeID: storeID)) }
        catch { throw ExtensionInstallError.downloadFailed(error.localizedDescription) }
        guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
            throw ExtensionInstallError.downloadFailed("the Chrome Web Store didn’t return the package")
        }
        let zip = try ExtensionPackage.zipData(fromCRX: data)
        return try await register(zipData: zip, storeID: storeID)
    }

    @discardableResult
    func installFile(_ url: URL) async throws -> InstalledExtension {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir) else {
            throw ExtensionInstallError.notAnExtension
        }
        if isDir.boolValue {
            guard FileManager.default.fileExists(atPath: url.appending(path: "manifest.json").path(percentEncoded: false)) else {
                throw ExtensionInstallError.notAnExtension
            }
            let id = UUID()
            let dest = Self.directory.appending(path: id.uuidString, directoryHint: .isDirectory)
            try FileManager.default.copyItem(at: url, to: dest)
            return try await finish(id: id, fileName: id.uuidString, storeID: nil)
        }
        let data = try Data(contentsOf: url)
        return try await register(zipData: ExtensionPackage.zipData(fromCRX: data), storeID: nil)
    }

    private func register(zipData: Data, storeID: String?) async throws -> InstalledExtension {
        let id = UUID()
        let fileName = id.uuidString + ".zip"
        try zipData.write(to: Self.directory.appending(path: fileName), options: .atomic)
        return try await finish(id: id, fileName: fileName, storeID: storeID)
    }

    private func finish(id: UUID, fileName: String, storeID: String?) async throws -> InstalledExtension {
        let location = Self.directory.appending(path: fileName)
        let ext: WKWebExtension
        do { ext = try await WKWebExtension(resourceBaseURL: location) }
        catch {
            try? FileManager.default.removeItem(at: location)
            throw ExtensionInstallError.invalid(error.localizedDescription)
        }
        guard await confirmInstall(ext) else {
            try? FileManager.default.removeItem(at: location)
            throw ExtensionInstallError.cancelled
        }
        let record = InstalledExtension(id: id, fileName: fileName, enabled: true, storeID: storeID, installed: .now)
        records.append(record)
        save()
        await load(record)
        browser?.showToast("puzzlepiece.extension.fill", "Added \(ext.displayName ?? "extension")")
        return record
    }

    // MARK: Managing

    func setEnabled(_ id: UUID, _ enabled: Bool) {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        records[i].enabled = enabled
        save()
        if enabled { Task { await load(records[i]) } } else { unload(id) }
    }

    func remove(_ id: UUID) {
        guard let record = records.first(where: { $0.id == id }) else { return }
        unload(id)
        try? FileManager.default.removeItem(at: url(of: record))
        records.removeAll { $0.id == id }
        loadErrors[id] = nil
        save()
    }

    /// Opens the Chrome Web Store (optionally a search) in a browser tab and brings the browser to front.
    func openStore(search query: String = "") {
        guard let browser else { return }
        browser.newTab(url: ExtensionPackage.storeSearchURL(query))
        if let settings = NSApp.keyWindow, settings.title.contains("Extensions") || settings.identifier?.rawValue.contains("Settings") == true {
            settings.performClose(nil)
        }
        NSApp.windows.first { $0.isVisible && $0.canBecomeMain && !($0 is NSPanel) && $0 !== NSApp.keyWindow }?.makeKeyAndOrderFront(nil)
    }

    func openOptions(_ id: UUID) {
        guard let url = contexts[id]?.optionsPageURL else { return }
        browser?.newTab(url: url)
    }

    func displayName(_ id: UUID) -> String {
        contexts[id]?.webExtension.displayName ?? records.first { $0.id == id }?.storeID ?? "Extension"
    }

    /// Clicking an extension's toolbar button.
    func performAction(_ id: UUID) {
        contexts[id]?.performAction(for: browser?.selectedTab?.controller)
    }

    private func save() {
        guard persist, let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: Self.recordsURL, options: .atomic)
    }

    // MARK: Tab events

    func didOpen(_ tab: TabWebController) { controller.didOpenTab(tab) }
    func didClose(_ tab: TabWebController) { controller.didCloseTab(tab, windowIsClosing: false) }
    func didActivate(_ tab: TabWebController?, previous: TabWebController?) {
        guard let tab else { return }
        controller.didActivateTab(tab, previousActiveTab: previous)
    }
}

// MARK: - WKWebExtensionControllerDelegate

extension ExtensionManager: WKWebExtensionControllerDelegate {
    func webExtensionController(_ controller: WKWebExtensionController,
                                openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        [window]
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        window
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                openNewTabUsing configuration: WKWebExtension.TabConfiguration,
                                for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void) {
        guard let browser else { completionHandler(nil, nil); return }
        let tab = browser.newTab(url: configuration.url, background: !configuration.shouldBeActive)
        if configuration.shouldBePinned { browser.togglePin(tab) }
        completionHandler(tab.controller, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                openOptionsPageFor extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping ((any Error)?) -> Void) {
        if let url = extensionContext.optionsPageURL { browser?.newTab(url: url) }
        completionHandler(nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissions permissions: Set<WKWebExtension.Permission>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void) {
        let names = permissions.map(\.rawValue).sorted().joined(separator: ", ")
        Task {
            let ok = await Self.ask("“\(extensionContext.webExtension.displayName ?? "An extension")” wants additional permissions",
                                    detail: names)
            completionHandler(ok ? permissions : [], nil)
        }
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissionToAccess urls: Set<URL>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<URL>, Date?) -> Void) {
        let hosts = urls.compactMap { $0.host() }.sorted().joined(separator: ", ")
        Task {
            let ok = await Self.ask("Allow “\(extensionContext.webExtension.displayName ?? "An extension")” to access \(hosts)?",
                                    detail: "It will be able to read and change data on these websites.")
            completionHandler(ok ? urls : [], nil)
        }
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void) {
        let list = matchPatterns.map(\.string).sorted().joined(separator: ", ")
        Task {
            let ok = await Self.ask("Allow “\(extensionContext.webExtension.displayName ?? "An extension")” to access more websites?",
                                    detail: list)
            completionHandler(ok ? matchPatterns : [], nil)
        }
    }

    func webExtensionController(_ controller: WKWebExtensionController, didUpdate action: WKWebExtension.Action,
                                forExtensionContext context: WKWebExtensionContext) {
        actionRevision += 1
    }

    func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action,
                                for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        guard let popover = action.popupPopover,
              let window = NSApp.mainWindow ?? NSApp.keyWindow, let content = window.contentView else {
            completionHandler(nil); return
        }
        let id = UUID(uuidString: context.uniqueIdentifier)
        let anchor = id.flatMap { actionAnchors[$0] } ?? CGRect(x: 20, y: 80, width: 24, height: 24)
        let rect = content.isFlipped ? anchor
            : NSRect(x: anchor.minX, y: content.bounds.height - anchor.maxY, width: anchor.width, height: anchor.height)
        popover.behavior = .transient
        popover.show(relativeTo: rect, of: content, preferredEdge: .maxY)
        completionHandler(nil)
    }

    private static func ask(_ title: String, detail: String) async -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don’t Allow")
        if let w = NSApp.keyWindow { return await alert.beginSheetModal(for: w) == .alertFirstButtonReturn }
        return alert.runModal() == .alertFirstButtonReturn
    }
}

// MARK: - Window / tab adapters

/// Browsi has one browser window; extensions see the tabs that have a live web view.
final class ExtensionWindowAdapter: NSObject, WKWebExtensionWindow {
    private var browser: BrowserState? { ExtensionManager.shared.browser }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        (browser?.allTabs ?? []).compactMap(\.controller)
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        browser?.selectedTab?.controller
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }
    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        NSApp.mainWindow?.styleMask.contains(.fullScreen) == true ? .fullscreen : .normal
    }
    func isPrivate(for context: WKWebExtensionContext) -> Bool { false }
    func frame(for context: WKWebExtensionContext) -> CGRect { NSApp.mainWindow?.frame ?? .null }
    func screenFrame(for context: WKWebExtensionContext) -> CGRect { NSApp.mainWindow?.screen?.frame ?? .null }
}

extension TabWebController: WKWebExtensionTab {
    private var browser: BrowserState? { ExtensionManager.shared.browser }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { ExtensionManager.shared.window }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { webView }
    func title(for context: WKWebExtensionContext) -> String? { tab.title }
    func url(for context: WKWebExtensionContext) -> URL? { webView.url ?? tab.url }
    func isPinned(for context: WKWebExtensionContext) -> Bool { tab.isPinned }
    func isSelected(for context: WKWebExtensionContext) -> Bool { browser?.selectedTab === tab }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !webView.isLoading }
    func zoomFactor(for context: WKWebExtensionContext) -> Double { webView.pageZoom }
    func size(for context: WKWebExtensionContext) -> CGSize { webView.bounds.size }

    func activate(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        browser?.select(tab); completionHandler(nil)
    }
    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        browser?.close(tab, removePinned: true); completionHandler(nil)
    }
    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        load(url); completionHandler(nil)
    }
    func reload(fromOrigin: Bool, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if fromOrigin { webView.reloadFromOrigin() } else { webView.reload() }
        completionHandler(nil)
    }
    func goBack(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        webView.goBack(); completionHandler(nil)
    }
    func goForward(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        webView.goForward(); completionHandler(nil)
    }
    func setZoomFactor(_ zoomFactor: Double, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        setZoom(zoomFactor); completionHandler(nil)
    }
}
