import SwiftUI
import WebKit

/// A calm ripple over the whole window (used for passkey sign-in).
struct CalmRipple: Identifiable {
    let id = UUID()
    /// Click point in window-content coordinates (top-left origin).
    let origin: CGPoint
    let tint: Color
    let start = Date()
    /// Picture of the whole window at the moment of the click; the waves distort this.
    var snapshot: NSImage?

    static let duration: Double = 3.0
    static let speed: Double = 330        // px / s
    static let wavelength: Double = 190
    static let amplitude: Double = 5
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
        let reduce = Motion.reduceMotion
        // Fade in/out only while the waves are flat, so the swap with the live window is invisible.
        let opacity = min(1, t / 0.12) * (1 - max(0, min(1, (t - 2.6) / 0.35)))
        ZStack {
            if !reduce, let snap = ripple.snapshot {
                Image(nsImage: snap)
                    .resizable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layerEffect(ShaderLibrary.default.browsiCalmRipple(
                        .float2(ripple.origin), .float(t),
                        .float(CalmRipple.amplitude), .float(CalmRipple.wavelength), .float(CalmRipple.speed)
                    ), maxSampleOffset: CGSize(width: 12, height: 12))
                    .opacity(opacity)
            }
            Canvas { gc, _ in drawRings(&gc, reduce: reduce) }
                .blendMode(.screen)
        }
    }

    /// Soft light rings riding on the crests.
    private func drawRings(_ gc: inout GraphicsContext, reduce: Bool) {
        let o = ripple.origin
        if reduce {
            let a = max(0, 1 - t / 1.2) * 0.35
            let r = 90.0
            gc.fill(Path(ellipseIn: CGRect(x: o.x - r, y: o.y - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(Gradient(colors: [ripple.tint.opacity(a), .clear]), center: o, startRadius: 0, endRadius: r))
            return
        }
        let fade = 1 - max(0, min(1, (t - 1.8) / 1.0))
        for i in 0..<4 {
            let r = t * CalmRipple.speed - Double(i) * CalmRipple.wavelength - CalmRipple.wavelength * 0.25
            guard r > 4 else { continue }
            let a = 0.16 * pow(0.6, Double(i)) * fade * min(1, r / 80)
            let rect = CGRect(x: o.x - r, y: o.y - r, width: r * 2, height: r * 2)
            var soft = gc
            soft.addFilter(.blur(radius: 10))
            soft.stroke(Path(ellipseIn: rect), with: .color(ripple.tint.opacity(a)), lineWidth: 22 - Double(i) * 4)
            gc.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(a * 0.7)), lineWidth: 1)
        }
        // A quiet glow where the finger landed.
        let g = max(0, 1 - t / 1.4) * 0.3, gr = 70.0
        gc.fill(Path(ellipseIn: CGRect(x: o.x - gr, y: o.y - gr, width: gr * 2, height: gr * 2)),
                with: .radialGradient(Gradient(colors: [ripple.tint.opacity(g), .clear]), center: o, startRadius: 0, endRadius: gr))
    }
}

/// Picture of the whole window: AppKit/SwiftUI chrome via cacheDisplay, with the web page
/// (which cacheDisplay can't capture) drawn in from WebKit's own snapshot.
@MainActor
enum WindowSnapshot {
    static func capture(content: NSView, webView: WKWebView?) async -> NSImage? {
        let bounds = content.bounds
        guard bounds.width > 0, let rep = content.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        content.cacheDisplay(in: bounds, to: rep)
        var page: (NSImage, CGRect)?
        if let webView, webView.window === content.window, !webView.isHidden,
           let shot = try? await webView.takeSnapshot(configuration: nil) {
            var r = webView.convert(webView.bounds, to: content)
            if content.isFlipped { r.origin.y = bounds.height - r.maxY }
            page = (shot, r)
        }
        return NSImage(size: bounds.size, flipped: false) { rect in
            rep.draw(in: rect)
            if let (img, r) = page {
                NSGraphicsContext.current?.saveGraphicsState()
                NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12).addClip()
                img.draw(in: r)
                NSGraphicsContext.current?.restoreGraphicsState()
            }
            return true
        }
    }
}
