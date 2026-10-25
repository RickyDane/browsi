import AppKit
import WebKit

/// Saves downloads into the chosen folder (default ~/Downloads), optionally asking per file.
final class DownloadManager: NSObject, WKDownloadDelegate {
    static let shared = DownloadManager()
    weak var browser: BrowserState?
    private var destinations: [ObjectIdentifier: URL] = [:]
    private var contexts: [ObjectIdentifier: DownloadContext] = [:]
    private var scopedFolder: URL?

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

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        if Preferences.shared.askWhereToSave {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = suggestedFilename
            panel.directoryURL = folder
            let response: NSApplication.ModalResponse
            if let window = download.webView?.window {
                response = await panel.beginSheetModal(for: window)
            } else {
                response = panel.runModal()
            }
            guard response == .OK, let url = panel.url else { return nil }
            try? FileManager.default.removeItem(at: url)
            destinations[ObjectIdentifier(download)] = url
            return url
        }

        // Remember where it came from for smart renaming (the user didn't pick a name).
        contexts[ObjectIdentifier(download)] = DownloadContext(
            originalName: suggestedFilename, mimeType: response.mimeType,
            sourceURL: download.originalRequest?.url ?? response.url,
            pageTitle: download.webView?.title, pageURL: download.webView?.url)

        let dir = folder
        let base = (suggestedFilename as NSString).deletingPathExtension
        let ext = (suggestedFilename as NSString).pathExtension
        var url = dir.appending(path: suggestedFilename)
        var n = 1
        while FileManager.default.fileExists(atPath: url.path()) {
            url = dir.appending(path: ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        destinations[ObjectIdentifier(download)] = url
        return url
    }

    func downloadDidFinish(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        let context = contexts.removeValue(forKey: key)
        guard let url = destinations.removeValue(forKey: key) else { return }
        Task {
            var final = url
            if let context, Preferences.shared.smartRenameDownloads {
                final = await smartRename(url, context: context)
            }
            if Preferences.shared.revealDownloads { NSWorkspace.shared.activateFileViewerSelecting([final]) }
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        destinations.removeValue(forKey: ObjectIdentifier(download))
        contexts.removeValue(forKey: ObjectIdentifier(download))
    }

    /// Asks the on-device model for a better name and renames the file. Returns the final URL.
    func smartRename(_ url: URL, context: DownloadContext) async -> URL {
        guard SmartRenamer.status == .available else { return url }
        var ctx = context
        ctx.originalName = url.lastPathComponent
        ctx.contentSnippet = await SmartRenamer.contentSnippet(of: url, mimeType: ctx.mimeType)
        guard let name = await SmartRenamer.suggestFileName(for: ctx) else { return url }
        let target = Self.uniqueURL(in: url.deletingLastPathComponent(), fileName: name)
        do {
            try FileManager.default.moveItem(at: url, to: target)
            browser?.showToast("apple.intelligence", "Saved as “\(target.lastPathComponent)”")
            debugLog("smart rename: \(url.lastPathComponent) → \(target.lastPathComponent)")
            return target
        } catch {
            debugLog("smart rename move failed: \(error)")
            return url
        }
    }

    nonisolated static func uniqueURL(in dir: URL, fileName: String) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var url = dir.appending(path: fileName)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path()) {
            url = dir.appending(path: ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }
}
