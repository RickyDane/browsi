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
}
