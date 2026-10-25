import AppKit

/// Imports passwords exported from Chrome (chrome://password-manager → Settings → Export passwords).
/// Also understands Safari / Passwords-app and Firefox CSV exports (columns are matched by name).
nonisolated enum PasswordImporter {
    struct Result: Equatable, Sendable {
        var added = 0, updated = 0, skipped = 0
    }

    /// RFC 4180 CSV: quoted fields, doubled quotes, commas/newlines inside quotes, CRLF.
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var inQuotes = false
        var it = text.replacingOccurrences(of: "\r\n", with: "\n").makeIterator()
        var pending: Character?
        while let c = pending ?? it.next() {
            pending = nil
            if inQuotes {
                if c == "\"" {
                    if let n = it.next() {
                        if n == "\"" { field.append("\"") } else { inQuotes = false; pending = n }
                    } else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r": row.append(field); field = ""; rows.append(row); row = []
                default: field.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }

    /// Extracts credentials; returns nil when the CSV doesn't look like a password export.
    static func credentials(fromCSV text: String) -> [Credential]? {
        let rows = parseCSV(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        guard let header = rows.first?.map({ $0.lowercased().trimmingCharacters(in: .whitespaces) }) else { return nil }
        func col(_ names: String...) -> Int? { names.lazy.compactMap { header.firstIndex(of: $0) }.first }
        guard let u = col("url", "origin", "website", "login_uri"), let p = col("password", "login_password") else { return nil }
        let user = col("username", "login_username", "user")
        return rows.dropFirst().compactMap { r in
            guard r.count > max(u, p) else { return nil }
            let password = r[p]
            guard !password.isEmpty, let host = host(from: r[u]) else { return nil }
            let username = user.flatMap { $0 < r.count ? r[$0] : nil } ?? ""
            return Credential(host: host, username: username, password: password)
        }
    }

    /// Host for a saved login URL; app-only entries (android://…) have none.
    static func host(from raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: s.contains("://") ? s : "https://" + s),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host(), !host.isEmpty else { return nil }
        return host.lowercased()
    }

    /// Saves to the Keychain; same host + username replaces the old password.
    static func importCredentials(_ list: [Credential], into store: KeychainStore) -> Result {
        var result = Result()
        var seen = Set<String>()
        for c in list {
            guard seen.insert(c.id).inserted else { result.skipped += 1; continue }
            let existing = try? store.password(host: c.host, username: c.username)
            if existing == c.password { result.skipped += 1; continue }
            do {
                try store.save(c)
                if existing == nil { result.added += 1 } else { result.updated += 1 }
            } catch {
                result.skipped += 1
            }
        }
        return result
    }
}

/// UI flow: guide → pick CSV → import → offer to trash the plaintext export.
@MainActor
enum ChromePasswordImport {
    static var chromeURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome")
    }

    /// Opens Chrome's password manager settings, where "Export passwords" lives.
    static func openChromeExport() {
        guard let chrome = chromeURL, let url = URL(string: "chrome://password-manager/settings") else { return }
        NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
    }

    static func chooseAndImport(store: KeychainStore) -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.directoryURL = URL.downloadsDirectory
        panel.message = "Choose the passwords file you exported from Chrome (usually “Chrome Passwords.csv”)"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let list = PasswordImporter.credentials(fromCSV: text) else {
            return "That file isn’t a password export."
        }
        let r = PasswordImporter.importCredentials(list, into: store)

        let alert = NSAlert()
        alert.messageText = "Imported \(r.added + r.updated) password\(r.added + r.updated == 1 ? "" : "s")"
        alert.informativeText = "\(r.added) new, \(r.updated) updated, \(r.skipped) unchanged or skipped.\n\nThe exported file contains your passwords in plain text. Move it to the Trash?"
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Keep File")
        if alert.runModal() == .alertFirstButtonReturn {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        return nil
    }
}
