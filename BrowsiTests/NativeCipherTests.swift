import Foundation
import Testing
@testable import Browsi

struct NativeCipherTests {
    @Test func approvedAppearanceAndTiming() {
        #expect(NativeCipher.depth == 0.10)
        #expect(NativeCipher.dotOpacity == 0.72)
        #expect(NativeCipher.darkening == 0.30)
        #expect(NativeCipher.playbackScale == 0.65)
        #expect(NativeCipher.releaseDuration < 0.5)
    }

    @Test func impulseHasOnePeakAndNoSecondPull() {
        #expect(NativeCipher.impulse(localTime: -0.1) == 0)
        #expect(NativeCipher.impulse(localTime: 0) == 0)
        #expect(NativeCipher.impulse(localTime: 0.25) == 1)
        let tail = stride(from: 0.35, through: 1.5, by: 0.01).map { NativeCipher.impulse(localTime: $0) }
        #expect(zip(tail, tail.dropFirst()).allSatisfy { $0 >= $1 })
        #expect(NativeCipher.impulse(localTime: 1.1) == 0)
        #expect(NativeCipher.impulse(localTime: 5) == 0)
    }

    @Test func sourceReboundsWhileWaveStillCrossesPage() {
        let size = CGSize(width: 1200, height: 800)
        let origin = CGPoint(x: 100, y: 100)
        let far = CGPoint(x: 1100, y: 700)
        let elapsed = 1.1 * NativeCipher.playbackScale
        let sourceTime = NativeCipher.localTime(at: origin, origin: origin, size: size, elapsed: elapsed)
        let farTime = NativeCipher.localTime(at: far, origin: origin, size: size, elapsed: elapsed)
        #expect(NativeCipher.impulse(localTime: sourceTime) == 0)
        #expect(farTime < 0, "the far edge has not been touched yet")
        #expect(NativeCipher.settlingDuration(origin: origin, size: size) > elapsed)
    }

    @Test func snapshotLifetimeIncludesTheLastTrailingEdge() {
        let size = CGSize(width: 1200, height: 800)
        for origin in [CGPoint.zero, CGPoint(x: 600, y: 400), CGPoint(x: 1190, y: 790)] {
            let duration = NativeCipher.settlingDuration(origin: origin, size: size)
            for corner in [CGPoint.zero, CGPoint(x: 1200, y: 0), CGPoint(x: 0, y: 800), CGPoint(x: 1200, y: 800)] {
                let local = NativeCipher.localTime(at: corner, origin: origin, size: size, elapsed: duration)
                #expect(local >= 1.1 - 1e-9)
                #expect(NativeCipher.impulse(localTime: local) < 1e-9)
            }
        }
    }
}
