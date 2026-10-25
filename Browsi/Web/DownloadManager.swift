import AppKit
import WebKit

/// Saves downloads into the chosen folder (default ~/Downloads), optionally asking per file.
final class DownloadManager: NSObject, WKDownloadDelegate {
    static let shared = DownloadManager()
    private var destinations: [ObjectIdentifier: URL] = [:]
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
        if let url = destinations.removeValue(forKey: ObjectIdentifier(download)), Preferences.shared.revealDownloads {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        destinations.removeValue(forKey: ObjectIdentifier(download))
    }
}
