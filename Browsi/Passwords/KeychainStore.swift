import Foundation
import Security

nonisolated struct Credential: Identifiable, Hashable, Sendable {
    var host: String
    var username: String
    var password: String
    var created: Date?
    var modified: Date?
    var id: String { host + "\u{1F}" + username }
}

nonisolated enum KeychainError: Error, Equatable {
    case status(OSStatus)
    case badData
}

/// Stores website logins as `kSecClassInternetPassword` items in the macOS keychain.
///
/// Prefers the modern data-protection keychain (requires a signing team / application
/// identifier); transparently falls back to the login (file-based) keychain when the
/// app is ad-hoc signed and that keychain is unavailable.
nonisolated struct KeychainStore: Sendable {
    /// Label marker so we only ever touch items this browser created.
    let label: String
    var synchronizable: Bool = false

    init(label: String = "Browsi", synchronizable: Bool = false) {
        self.label = label
        self.synchronizable = synchronizable
    }

    static let useDataProtection: Bool = {
        // Probe once by writing a throwaway item: without an application identifier
        // (ad-hoc signing) the DP keychain rejects writes with errSecMissingEntitlement.
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: "browsi.keychain-probe",
            kSecAttrAccount as String: "probe",
        ]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = Data()
        let s = SecItemAdd(add as CFDictionary, nil)
        SecItemDelete(q as CFDictionary)
        return s == errSecSuccess
    }()

    private func base(host: String? = nil, username: String? = nil) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrLabel as String: label,
        ]
        if Self.useDataProtection {
            q[kSecUseDataProtectionKeychain as String] = true
            q[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        }
        if let host { q[kSecAttrServer as String] = host }
        if let username { q[kSecAttrAccount as String] = username }
        return q
    }

    /// Adds or updates a credential.
    func save(_ c: Credential) throws {
        let pw = Data(c.password.utf8)
        let query = base(host: c.host, username: c.username)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: pw] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError.status(status) }

        var add = base(host: c.host, username: c.username)
        add[kSecAttrSynchronizable as String] = nil
        add[kSecAttrProtocol as String] = kSecAttrProtocolHTTPS
        add[kSecAttrComment as String] = "Saved by Browsi"
        add[kSecValueData as String] = pw
        if Self.useDataProtection {
            add[kSecAttrSynchronizable as String] = synchronizable
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        }
        let s = SecItemAdd(add as CFDictionary, nil)
        guard s == errSecSuccess else { throw KeychainError.status(s) }
    }

    /// Account names (no secrets) for a host, or for all hosts if nil.
    func accounts(host: String? = nil) -> [Credential] {
        var q = base(host: host)
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        q[kSecReturnAttributes as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let items = out as? [[String: Any]] else { return [] }
        return items.compactMap { a in
            guard let server = a[kSecAttrServer as String] as? String,
                  let account = a[kSecAttrAccount as String] as? String else { return nil }
            return Credential(host: server, username: account, password: "",
                              created: a[kSecAttrCreationDate as String] as? Date,
                              modified: a[kSecAttrModificationDate as String] as? Date)
        }
        .sorted { ($0.host, $0.username) < ($1.host, $1.username) }
    }

    func password(host: String, username: String) throws -> String {
        var q = base(host: host, username: username)
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecReturnData as String] = true
        var out: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &out)
        guard s == errSecSuccess else { throw KeychainError.status(s) }
        guard let data = out as? Data, let str = String(data: data, encoding: .utf8) else { throw KeychainError.badData }
        return str
    }

    func delete(host: String, username: String) throws {
        let s = SecItemDelete(base(host: host, username: username) as CFDictionary)
        guard s == errSecSuccess || s == errSecItemNotFound else { throw KeychainError.status(s) }
    }

    func deleteAll() throws {
        let s = SecItemDelete(base() as CFDictionary)
        guard s == errSecSuccess || s == errSecItemNotFound else { throw KeychainError.status(s) }
    }
}
