import Testing
import Foundation
@testable import Browsi

@Suite(.serialized)
struct KeychainStoreTests {
    let store = KeychainStore(label: "Browsi-Tests-\(UUID().uuidString.prefix(8))")
    let host = "tests.browsi.invalid"

    @Test func roundTrip() throws {
        defer { try? store.deleteAll() }
        try store.save(Credential(host: host, username: "alice", password: "s3cret"))
        #expect(try store.password(host: host, username: "alice") == "s3cret")
        #expect(store.accounts(host: host).map(\.username) == ["alice"])

        try store.save(Credential(host: host, username: "alice", password: "changed"))
        #expect(try store.password(host: host, username: "alice") == "changed")
        #expect(store.accounts(host: host).count == 1)

        try store.save(Credential(host: host, username: "bob", password: "pw"))
        #expect(store.accounts(host: host).map(\.username) == ["alice", "bob"])

        try store.delete(host: host, username: "alice")
        #expect(throws: KeychainError.status(errSecItemNotFound)) {
            try store.password(host: host, username: "alice")
        }
        #expect(store.accounts().map(\.username) == ["bob"])
    }

    @Test func labelsIsolateStores() throws {
        let other = KeychainStore(label: "Browsi-Tests-Other-\(UUID().uuidString.prefix(8))")
        defer { try? store.deleteAll(); try? other.deleteAll() }
        try store.save(Credential(host: host, username: "carol", password: "x"))
        #expect(other.accounts(host: host).isEmpty)
    }

    /// Regression: another app's login-keychain entry for the same site + username blocked saving.
    @Test func coexistsWithOtherItemsForSameSiteAndUser() throws {
        let other = KeychainStore(label: "OtherApp-\(UUID().uuidString.prefix(6))")
        defer { try? store.deleteAll(); try? other.deleteAll() }
        try other.save(Credential(host: host, username: "dave", password: "theirs"))
        try store.save(Credential(host: host, username: "dave", password: "ours"))
        #expect(try store.password(host: host, username: "dave") == "ours")
        #expect(try other.password(host: host, username: "dave") == "theirs")
    }
}
