import AppKit
import Testing
@testable import Browsi

struct AppearanceTests {
    @Test func glowScaleKeepsDefaultLookAndSpansRange() {
        #expect(StarfieldView.glowScale(0) == 0)
        #expect(abs(StarfieldView.glowScale(0.85) - 1) < 1e-9)
        #expect(abs(StarfieldView.glowScale(1) - 1.8) < 1e-9)
        #expect(StarfieldView.glowScale(0.4) < StarfieldView.glowScale(0.6))
    }

    @Test func everyAppIconHasAnAsset() {
        for icon in AppIconChoice.allCases {
            #expect(icon.image != nil, "missing asset \(icon.assetName)")
        }
    }

    @Test func spaceIconsIncludePulsarAsDefault() {
        #expect(AppIconChoice.defaultChoice == .pulsar)
        let spaceIcons: [AppIconChoice] = [
            .pulsar, .orbitalB, .softSaturn, .transit,
            .moonGate, .orbitCursor, .solarSail, .binary,
            .gravityB, .novaBloom, .deepfield, .starTrail,
            .redDwarf, .lagrange, .ionRibbon, .cosmicEye
        ]
        #expect(spaceIcons.allSatisfy { AppIconChoice.allCases.contains($0) })
        #expect(Set(AppIconChoice.allCases.map(\.assetName)).count == AppIconChoice.allCases.count)
        #expect(AppIconChoice(rawValue: "nebulaSparkle") == .nebulaSparkle)
    }

    @Test func defaultIconIsAppliedExplicitlyAfterSwitching() throws {
        // AppKit's getter returns the bundle icon, not the last Dock override.
        // Capture what we send to the setter instead.
        var applied: [NSImage?] = []
        AppIconChoice.nebulaSparkle.apply(using: { applied.append($0) })
        AppIconChoice.defaultChoice.apply(using: { applied.append($0) })
        let expected = try #require(AppIconChoice.pulsar.image)
        #expect(applied.count == 2)
        #expect(applied[0]?.tiffRepresentation == AppIconChoice.nebulaSparkle.image?.tiffRepresentation)
        #expect(applied[1]?.tiffRepresentation == expected.tiffRepresentation)
    }

    @Test func iconCollectionsCoverOnlyTheApprovedIcons() {
        let icons = AppIconCollection.allCases.flatMap(\.icons)
        #expect(icons == AppIconChoice.allCases)
        #expect(Set(icons).count == 21)
        #expect(AppIconCollection.space.icons.count == 8)
        #expect(AppIconCollection.exploration.icons.count == 8)
        #expect(AppIconCollection.galaxy.icons.count == 5)
        #expect(AppIconChoice.defaultChoice.collection == .space)
        for collection in AppIconCollection.allCases {
            #expect(collection.icons.allSatisfy { $0.collection == collection })
        }
    }
}
