import Testing
import Foundation
@testable import Browsi

struct PasswordImportTests {
    static let chromeCSV = """
    name,url,username,password,note\r
    github.com,https://github.com/login,alice,"p,ass""word",\r
    accounts.google.com,https://accounts.google.com/signin/v2,alice@gmail.com,s3cret,"multi
    line note"\r
    android app,android://hash@com.example.app/,bob,x,\r
    empty,https://empty.example,carol,,\r
    """

    @Test func parsesChromeExport() throws {
        let list = try #require(PasswordImporter.credentials(fromCSV: Self.chromeCSV))
        #expect(list.count == 2)
        #expect(list[0] == Credential(host: "github.com", username: "alice", password: "p,ass\"word"))
        #expect(list[1].host == "accounts.google.com" && list[1].password == "s3cret")
    }

    @Test func parsesSafariAndRejectsOtherCSVs() {
        let safari = "Title,URL,Username,Password,Notes,OTPAuth\nApple,https://appleid.apple.com,me@icloud.com,pw,,\n"
        #expect(PasswordImporter.credentials(fromCSV: safari)?.first?.host == "appleid.apple.com")
        #expect(PasswordImporter.credentials(fromCSV: "a,b\n1,2\n") == nil)
    }

    @Test func importsIntoKeychainAndUpdates() throws {
        let store = KeychainStore(label: "Browsi-Import-Tests-\(UUID().uuidString.prefix(6))")
        defer { try? store.deleteAll() }
        let first = PasswordImporter.importCredentials(try #require(PasswordImporter.credentials(fromCSV: Self.chromeCSV)), into: store)
        #expect(first == .init(added: 2, updated: 0, skipped: 0))
        #expect(try store.password(host: "github.com", username: "alice") == "p,ass\"word")
        let again = PasswordImporter.importCredentials([Credential(host: "github.com", username: "alice", password: "new"),
                                                        Credential(host: "accounts.google.com", username: "alice@gmail.com", password: "s3cret")],
                                                       into: store)
        #expect(again == .init(added: 0, updated: 1, skipped: 1))
    }
}

struct StarfieldTests {
    @Test func seededRandomIsStableAndInRange() {
        var a = SeededRandom(seed: 42), b = SeededRandom(seed: 42)
        let xs = (0..<100).map { _ in a.next() }
        #expect(xs == (0..<100).map { _ in b.next() })
        #expect(xs.allSatisfy { (0..<1).contains($0) })
    }

    @Test func shootingStarsAppearRegularly() {
        // Roughly 45 % of 2.6 s slots carry a meteor: expect a few per minute, not zero and not constant.
        var slots = 0
        for slot in 0..<1000 {
            var rng = SeededRandom(seed: UInt64(slot) &* 0x9E37_79B9 &+ 17)
            if rng.next() < 0.45 { slots += 1 }
        }
        #expect((350...550).contains(slots))
    }

    @Test @MainActor func spaceThemeIsDefaultAndDark() {
        #expect(Preferences.shared.spaceTheme)
        #expect(Preferences.shared.effectiveAppearance?.name == .darkAqua)
        #expect(!HomeStore.shared.isEditing, "home page starts locked")
    }
}
