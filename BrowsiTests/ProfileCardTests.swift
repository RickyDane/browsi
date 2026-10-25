import Foundation
import Testing
@testable import Browsi

struct ProfileCardTests {
    @Test func memoryFormatting() {
        #expect(MacInfo.formatMemory(17_179_869_184) == "16 GB")
        #expect(MacInfo.formatMemory(38_654_705_664) == "36 GB")
    }

    @Test func fallbackNames() {
        #expect(MacInfo.fallbackName(for: "MacBookPro18,3") == "MacBook Pro")
        #expect(MacInfo.fallbackName(for: "MacBookAir10,1") == "MacBook Air")
        #expect(MacInfo.fallbackName(for: "Macmini9,1") == "Mac mini")
        #expect(MacInfo.fallbackName(for: "Mac16,6") == "Mac")
    }

    @Test func symbols() {
        #expect(MacInfo.symbol(for: "MacBook Pro (14-inch, 2024)") == "laptopcomputer")
        #expect(MacInfo.symbol(for: "Mac Studio (2025)") == "macstudio")
        #expect(MacInfo.symbol(for: "iMac (24-inch, 2024)") == "desktopcomputer")
    }

    @Test func productNameStripsNul() {
        #expect(MacInfo.productName(from: Data("MacBook Air (13-inch, M3, 2024)\0".utf8)) == "MacBook Air (13-inch, M3, 2024)")
        #expect(MacInfo.productName(from: Data([0])) == nil)
    }

    @Test func currentMacIsReadable() {
        let mac = MacInfo.read()
        #expect(!mac.modelName.isEmpty)
        #expect(!mac.modelIdentifier.isEmpty)
        #expect(mac.osVersion.hasPrefix("macOS \(mac.systemVersion)"))
        #expect(mac.memoryBytes > 0)
    }

    @Test func limbHeight() {
        #expect(ProfileCard.limbY(atX: 50, diameter: 100) == 0)
        #expect(ProfileCard.limbY(atX: 0, diameter: 100) == 50)
        #expect(ProfileCard.limbY(atX: -20, diameter: 100) == 50)
    }
}
