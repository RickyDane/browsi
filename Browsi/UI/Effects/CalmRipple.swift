import SwiftUI

/// Native Cipher: one shallow, click-origin impact reveals white cipher dots over the page.
/// The page rebounds; only the grid holds during authentication, then fades without another wave.
struct CalmRipple: Identifiable {
    let id = UUID()
    /// Click point in window-content coordinates (top-left origin).
    let origin: CGPoint
    let tabID: UUID?
    let pageOrigin: CGPoint?
    /// Only used during the brief warp. The live WKWebView remains mounted underneath.
    var snapshot: NSImage?
    let start = Date()
    /// When the passkey ceremony finished; nil while it's still running.
    var release: Date?

    /// Time from release until the overlay is fully gone.
    static let releaseDuration = NativeCipher.releaseDuration
    /// Shortest visible hold, so even an instant "no passkey" answer reads as one gesture.
    static let minimumHold: Double = 0.8
    /// If no passkey request reaches Browsi within this time after the click, release on our own.
    static let requestGrace: Double = 1.6
    /// Never hold longer than this, whatever happens.
    static let maximumHold: Double = 120

    init(origin: CGPoint, tabID: UUID? = nil, pageOrigin: CGPoint? = nil) {
        self.origin = origin
        self.tabID = tabID
        self.pageOrigin = pageOrigin
    }

    /// Seconds after `start` at which the grid starts to clear (very large while holding).
    var releaseTime: Double { release.map { max(0, $0.timeIntervalSince(start)) } ?? 1e6 }
    var end: Date? { release.map { $0.addingTimeInterval(Self.releaseDuration) } }
}

struct CalmRippleOverlay: View {
    let ripple: CalmRipple
    let origin: CGPoint
    @State private var settled = false

    var body: some View {
        GeometryReader { geo in
            let duration = Motion.reduceMotion ? 0.4 * NativeCipher.playbackScale
                : NativeCipher.settlingDuration(origin: origin, size: geo.size)
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: settled && ripple.release == nil)) { ctx in
                let t = max(0, ctx.date.timeIntervalSince(ripple.start))
                let warping = !Motion.reduceMotion && t < duration && t < ripple.releaseTime + CalmRipple.releaseDuration
                ZStack {
                    if warping, let snapshot = ripple.snapshot {
                        Image(nsImage: snapshot).resizable()
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                    CalmRippleFrame(ripple: ripple, t: t, origin: origin)
                }
                .layerEffect(ShaderLibrary.default.browsiPasskeyWarp(
                    .float2(geo.size), .float2(origin), .float(t / NativeCipher.playbackScale),
                    .float(ripple.releaseTime / NativeCipher.playbackScale),
                    .float(CalmRipple.releaseDuration / NativeCipher.playbackScale), .float(NativeCipher.depth)),
                    maxSampleOffset: CGSize(width: geo.size.width * 0.1 + 2, height: geo.size.height * 0.1 + 2),
                    isEnabled: warping)
            }
            .task(id: ripple.id) {
                do {
                    try await Task.sleep(for: .seconds(max(0, duration - Date().timeIntervalSince(ripple.start))))
                    settled = true
                } catch { /* The page or effect was replaced. */ }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One frame at time `t` (separate so it can be rendered in tests).
struct CalmRippleFrame: View {
    let ripple: CalmRipple
    let t: Double
    var origin: CGPoint? = nil

    var body: some View {
        if Motion.reduceMotion {
            reducedMotion
        } else {
            GeometryReader { geo in
                Rectangle()
                    .fill(.black) // Opaque input; the shader returns a premultiplied transparent overlay.
                    .colorEffect(ShaderLibrary.default.browsiPasskeyGrid(
                        .float2(geo.size), .float2(origin ?? ripple.origin), .float(t / NativeCipher.playbackScale),
                        .float(ripple.releaseTime / NativeCipher.playbackScale),
                        .float(CalmRipple.releaseDuration / NativeCipher.playbackScale),
                        .float(NativeCipher.dotOpacity), .float(NativeCipher.darkening)))
            }
        }
    }

    /// Reduce Motion: no warp, travelling reveal, or flickering dots; only a subtle neutral fade.
    private var reducedMotion: some View {
        let fadeIn = NativeCipher.smooth(t / (0.4 * NativeCipher.playbackScale))
        let fadeOut = 1 - NativeCipher.smooth((t - ripple.releaseTime) / CalmRipple.releaseDuration)
        return Color.black.opacity(0.08 * fadeIn * fadeOut)
    }
}
