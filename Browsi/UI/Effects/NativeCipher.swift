import Foundation

/// Shared timing and appearance of the approved Native Cipher treatment.
nonisolated enum NativeCipher {
    static let depth = 0.10
    static let dotOpacity = 0.72
    static let darkening = 0.30
    static let playbackScale = 0.65
    static let releaseDuration = 0.75 * playbackScale

    static func smooth(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return x * x * (3 - 2 * x)
    }

    /// One passing impulse, with no delayed second pull and no permanent indentation.
    static func impulse(localTime: Double) -> Double {
        smooth(localTime / 0.19) * (1 - smooth((localTime - 0.34) / 0.76))
    }

    static func localTime(at point: CGPoint, origin: CGPoint, size: CGSize, elapsed: Double) -> Double {
        let distance = hypot(point.x - origin.x, point.y - origin.y)
        return elapsed / playbackScale - Double(distance) * 2 / max(1, Double(size.height)) / 1.15
    }

    /// Once the trailing edge has left the page, discard the temporary snapshot and pause rendering.
    static func settlingDuration(origin: CGPoint, size: CGSize) -> Double {
        let farX = max(abs(origin.x), abs(size.width - origin.x))
        let farY = max(abs(origin.y), abs(size.height - origin.y))
        let travel = Double(hypot(farX, farY)) * 2 / max(1, Double(size.height)) / 1.15
        return (travel + 1.1) * playbackScale
    }
}
