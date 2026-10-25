import SwiftUI

/// Passkey sign-in effect ("Cipher grid"): one calm wave rolls out from the clicked button and leaves a
/// fine grid over the whole window. The grid holds while the passkey prompt (Touch ID / account picker)
/// is open; when it finishes, a release wave clears the grid outward from the button.
///
/// Drawn as a transparent overlay above the live window (no snapshot), so the page stays live underneath.
struct CalmRipple: Identifiable {
    let id = UUID()
    /// Click point in window-content coordinates (top-left origin).
    let origin: CGPoint
    let tint: Color
    let start = Date()
    /// When the passkey ceremony finished; nil while it's still running.
    var release: Date?

    static let speed: Double = 290          // pt / s
    /// Time from release until the overlay is fully gone.
    static let releaseDuration: Double = 2.6
    /// Shortest visible hold, so even an instant "no passkey" answer reads as one gesture.
    static let minimumHold: Double = 0.8
    /// If no passkey request reaches Browsi within this time after the click, release on our own.
    static let requestGrace: Double = 1.6
    /// Never hold longer than this, whatever happens.
    static let maximumHold: Double = 120

    /// Seconds after `start` at which the grid starts to clear (very large while holding).
    var releaseTime: Double { release.map { max(0, $0.timeIntervalSince(start)) } ?? 1e6 }
    var end: Date? { release.map { $0.addingTimeInterval(Self.releaseDuration) } }
}

struct CalmRippleOverlay: View {
    let ripple: CalmRipple

    var body: some View {
        TimelineView(.animation) { ctx in
            CalmRippleFrame(ripple: ripple, t: max(0, ctx.date.timeIntervalSince(ripple.start)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
    }
}

/// One frame at time `t` (separate so it can be rendered in tests).
struct CalmRippleFrame: View {
    let ripple: CalmRipple
    let t: Double

    var body: some View {
        if Motion.reduceMotion {
            reducedMotion
        } else {
            let rgb = NSColor(ripple.tint).usingColorSpace(.sRGB) ?? .systemTeal
            Rectangle()
                .fill(.black)   // any opaque fill: the shader ignores it and draws the overlay
                .colorEffect(ShaderLibrary.default.browsiPasskeyGrid(
                    .float2(ripple.origin), .float(t), .float(ripple.releaseTime),
                    .float(CalmRipple.speed), .float(CalmRipple.releaseDuration),
                    .float3(Float(rgb.redComponent), Float(rgb.greenComponent), Float(rgb.blueComponent))))
        }
    }

    /// Reduce Motion: a still, faint tint that fades in and out.
    private var reducedMotion: some View {
        let fadeIn = min(1, t / 0.4)
        let fadeOut = 1 - max(0, min(1, (t - ripple.releaseTime) / 0.6))
        return ripple.tint.opacity(0.08 * fadeIn * fadeOut)
    }
}
