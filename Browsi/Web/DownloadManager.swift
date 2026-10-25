import AppKit
import WebKit
import SwiftUI
import UniformTypeIdentifiers

/// One entry in the download queue.
@Observable
final class DownloadItem: Identifiable {
    enum State: Equatable {
        case downloading, finished, failed(String), cancelled
    }

    let id: UUID
    var fileName: String
    var fileURL: URL?
    var state: State
    var progress: Double = 0
    var receivedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    let started: Date
    var context: DownloadContext
    /// Set while the on-device model is choosing a name.
    var isRenaming = false
    /// Name before the last smart rename (enables undo).
    var renamedFrom: String?
    /// Drives the old → new name morph in the queue.
    var renameMorph: RenameMorph?

    @ObservationIgnored weak var download: WKDownload?
    @ObservationIgnored var progressObservation: NSKeyValueObservation?

    init(id: UUID = UUID(), fileName: String, fileURL: URL?, state: State, started: Date = .now, context: DownloadContext) {
        self.id = id
        self.fileName = fileName
        self.fileURL = fileURL
        self.state = state
        self.started = started
        self.context = context
    }

    var isActive: Bool { state == .downloading }
    var fileExists: Bool { fileURL.map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } ?? false }
}

/// Saves downloads into the chosen folder (default ~/Downloads), keeps a queue/history of them,
/// and renames unclear file names with the on-device model (automatically or on request).
@Observable
final class DownloadManager: NSObject, WKDownloadDelegate {
    static let shared = DownloadManager()
    @ObservationIgnored weak var browser: BrowserState?
    private(set) var items: [DownloadItem] = []
    @ObservationIgnored private var byDownload: [ObjectIdentifier: DownloadItem] = [:]
    @ObservationIgnored private var scopedFolder: URL?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    var activeCount: Int { items.filter(\.isActive).count }
    /// Combined progress of all running downloads (0…1), nil when idle.
    var overallProgress: Double? {
        let active = items.filter(\.isActive)
        guard !active.isEmpty else { return nil }
        return active.map(\.progress).reduce(0, +) / Double(active.count)
    }

    override init() {
        super.init()
        load()
    }

    /// The configured download folder (security-scoped bookmark in the sandbox).
    var folder: URL {
        if let data = Preferences.shared.downloadFolderBookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale) {
                if scopedFolder != url {
                    scopedFolder?.stopAccessingSecurityScopedResource()
                    _ = url.startAccessingSecurityScopedResource()
                    scopedFolder = url
                }
                return url
            }
        }
        return URL.downloadsDirectory
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = folder
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? url.bookmarkData(options: .withSecurityScope) else { return }
        Preferences.shared.downloadFolderBookmark = data
    }

    // MARK: WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        let context = DownloadContext(
            originalName: suggestedFilename, mimeType: response.mimeType,
            sourceURL: download.originalRequest?.url ?? response.url,
            pageTitle: download.webView?.title, pageURL: download.webView?.url)

        var destination: URL
        var userChoseName = false
        if Preferences.shared.askWhereToSave {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = suggestedFilename
            panel.directoryURL = folder
            let result: NSApplication.ModalResponse
            if let window = download.webView?.window {
                result = await panel.beginSheetModal(for: window)
            } else {
                result = panel.runModal()
            }
            guard result == .OK, let url = panel.url else { return nil }
            try? FileManager.default.removeItem(at: url)
            destination = url
            userChoseName = true
        } else {
            destination = Self.uniqueURL(in: folder, fileName: suggestedFilename)
        }

        let item = DownloadItem(fileName: destination.lastPathComponent, fileURL: destination,
                                state: .downloading, context: context)
        item.download = download
        item.totalBytes = response.expectedContentLength
        if userChoseName { item.context.originalName = "" }   // never auto-rename a name the user picked
        item.progressObservation = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak item] p, _ in
            let fraction = p.fractionCompleted, done = p.completedUnitCount, total = p.totalUnitCount
            Task { @MainActor in
                item?.progress = fraction
                item?.receivedBytes = done
                if total > 0 { item?.totalBytes = total }
            }
        }
        byDownload[ObjectIdentifier(download)] = item
        withAnimation(Motion.snappy) { items.insert(item, at: 0) }
        browser?.launchDownloadFlight(for: destination.lastPathComponent)
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let item = byDownload.removeValue(forKey: ObjectIdentifier(download)) else { return }
        item.progressObservation = nil
        browser?.noteDownloadActivity()
        withAnimation(Motion.snappy) {
            item.state = .finished
            item.progress = 1
        }
        scheduleSave()
        Task {
            if Preferences.shared.smartRenameDownloads, !item.context.originalName.isEmpty {
                await smartRename(item, automatic: true)
            }
            if Preferences.shared.revealDownloads, let url = item.fileURL {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let item = byDownload.removeValue(forKey: ObjectIdentifier(download)) else { return }
        item.progressObservation = nil
        browser?.noteDownloadActivity()
        let cancelled = (error as NSError).code == NSURLErrorCancelled
        withAnimation(Motion.snappy) { item.state = cancelled ? .cancelled : .failed(error.localizedDescription) }
        scheduleSave()
    }

    // MARK: Queue actions

    func cancel(_ item: DownloadItem) {
        item.download?.cancel(nil)
    }

    func retry(_ item: DownloadItem) {
        guard let url = item.context.sourceURL else { return }
        remove(item)
        browser?.selectedTab?.controller?.webView.startDownload(using: URLRequest(url: url)) { $0.delegate = self }
    }

    func remove(_ item: DownloadItem) {
        withAnimation(Motion.snappy) { items.removeAll { $0 === item } }
        scheduleSave()
    }

    func clearFinished() {
        withAnimation(Motion.snappy) { items.removeAll { !$0.isActive } }
        scheduleSave()
    }

    func moveToTrash(_ item: DownloadItem) {
        if let url = item.fileURL { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        remove(item)
    }

    func reveal(_ item: DownloadItem) {
        if let url = item.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    func open(_ item: DownloadItem) {
        if let url = item.fileURL { NSWorkspace.shared.open(url) }
    }

    /// Renames to `newName` (extension kept if omitted). Returns false if the move failed.
    @discardableResult
    func rename(_ item: DownloadItem, to newName: String) -> Bool {
        guard let url = item.fileURL else { return false }
        var name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ext = url.pathExtension
        if !ext.isEmpty, (name as NSString).pathExtension.isEmpty { name += "." + ext }
        guard let clean = SmartRenamer.sanitize((name as NSString).deletingPathExtension) else { return false }
        name = (name as NSString).pathExtension.isEmpty ? clean : clean + "." + (name as NSString).pathExtension
        guard name != url.lastPathComponent else { return true }
        let target = Self.uniqueURL(in: url.deletingLastPathComponent(), fileName: name)
        do {
            try FileManager.default.moveItem(at: url, to: target)
        } catch {
            debugLog("rename failed: \(error)")
            return false
        }
        let morph = RenameMorph(from: url.lastPathComponent)
        withAnimation(Motion.snappy) {
            item.renamedFrom = url.lastPathComponent
            item.fileURL = target
            item.fileName = target.lastPathComponent
            item.renameMorph = morph
        }
        Task { [weak item] in
            try? await Task.sleep(for: .seconds(RenameMorph.duration + 0.1))
            if item?.renameMorph?.id == morph.id { item?.renameMorph = nil }
        }
        scheduleSave()
        return true
    }

    func undoRename(_ item: DownloadItem) {
        guard let old = item.renamedFrom else { return }
        rename(item, to: old)
        item.renamedFrom = nil
        scheduleSave()
    }

    /// Asks the on-device model for a better name. `automatic` respects the model's
    /// "name is already fine" judgement; a manual request always proposes a name.
    func smartRename(_ item: DownloadItem, automatic: Bool = false) async {
        guard item.state == .finished, let url = item.fileURL, !item.isRenaming,
              SmartRenamer.status == .available else {
            if !automatic, SmartRenamer.status != .available {
                browser?.showToast("apple.intelligence", "Apple Intelligence is unavailable")
            }
            return
        }
        withAnimation(Motion.snappy) { item.isRenaming = true }
        defer { withAnimation(Motion.snappy) { item.isRenaming = false } }
        var ctx = item.context
        ctx.originalName = url.lastPathComponent
        ctx.contentSnippet = await SmartRenamer.contentSnippet(of: url, mimeType: ctx.mimeType)
        guard let name = await SmartRenamer.suggestFileName(for: ctx, force: !automatic) else {
            if !automatic { browser?.showToast("checkmark.seal", "The name already looks good") }
            return
        }
        if rename(item, to: name) {
            browser?.showToast("apple.intelligence", "Renamed to “\(item.fileName)”")
        }
    }

    nonisolated static func uniqueURL(in dir: URL, fileName: String) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var url = dir.appending(path: fileName)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            url = dir.appending(path: ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }

    // MARK: Persistence (finished/failed history, last 100)

    private struct Record: Codable {
        var id: UUID, fileName: String, path: String?, state: String, started: Date
        var sourceURL: URL?, pageTitle: String?, pageURL: URL?, mimeType: String?, totalBytes: Int64
        var renamedFrom: String?
    }

    private static var storeURL: URL {
        SessionStore.fileURL.deletingLastPathComponent().appending(path: "downloads.json")
    }

    /// Test hook: replaces the queue.
    func reset(_ new: [DownloadItem] = []) { items = new }

    private func load() {
        guard !ProcessInfo.processInfo.environment.keys.contains("XCTestConfigurationFilePath"),
              let data = try? Data(contentsOf: Self.storeURL),
              let records = try? JSONDecoder().decode([Record].self, from: data) else { return }
        items = records.map { r in
            let state: DownloadItem.State = r.state == "finished" ? .finished : r.state == "cancelled" ? .cancelled : .failed("Interrupted")
            let item = DownloadItem(id: r.id, fileName: r.fileName, fileURL: r.path.map { URL(fileURLWithPath: $0) },
                                    state: state, started: r.started,
                                    context: DownloadContext(originalName: r.fileName, mimeType: r.mimeType,
                                                             sourceURL: r.sourceURL, pageTitle: r.pageTitle, pageURL: r.pageURL))
            item.totalBytes = r.totalBytes
            item.progress = state == .finished ? 1 : 0
            item.renamedFrom = r.renamedFrom
            return item
        }
    }

    private func scheduleSave() {
        guard !ProcessInfo.processInfo.environment.keys.contains("XCTestConfigurationFilePath") else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let records = items.filter { !$0.isActive }.prefix(100).map { i -> Record in
                let state: String = switch i.state {
                case .finished: "finished"
                case .cancelled: "cancelled"
                default: "failed"
                }
                return Record(id: i.id, fileName: i.fileName, path: i.fileURL?.path(percentEncoded: false), state: state, started: i.started,
                              sourceURL: i.context.sourceURL, pageTitle: i.context.pageTitle, pageURL: i.context.pageURL,
                              mimeType: i.context.mimeType, totalBytes: i.totalBytes, renamedFrom: i.renamedFrom)
            }
            if let data = try? JSONEncoder().encode(Array(records)) { try? data.write(to: Self.storeURL, options: .atomic) }
        }
    }
}

/// An in-flight file-name transition (old name → current name).
struct RenameMorph: Equatable {
    static let duration: TimeInterval = 1.1
    let id = UUID()
    let from: String
    let start = Date()
}
