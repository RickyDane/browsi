import SwiftUI

/// The wave-impact played when the user clicks "Sign in with Apple" or a passkey button:
/// the page itself ripples like water (Metal shader over a snapshot), shockwave rings and sparks
/// burst from the button, and a light flash blooms where it was pressed.
struct ImpactOverlay: View {
    let impact: LoginImpact
    static let duration: Double = 1.35

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = max(0, ctx.date.timeIntervalSince(impact.start))
            let reduce = Motion.reduceMotion
            ZStack {
                if !reduce, let snap = impact.snapshot {
                    rippledPage(snap, t: t)
                }
                Canvas { gc, size in
                    if reduce { drawGentleGlow(&gc, t: t) } else { drawBurst(&gc, size: size, t: t) }
                }
                .blendMode(.plusLighter)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Page ripple

    private func rippledPage(_ snap: NSImage, t: Double) -> some View {
        // Fully opaque while the main wave passes, then dissolves back into the live page.
        let opacity = t < 0.45 ? 1 : max(0, 1 - (t - 0.45) / 0.5)
        return Image(nsImage: snap)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .layerEffect(ShaderLibrary.default.browsiRipple(
                .float2(impact.origin), .float(t),
                .float(22), .float(17), .float(3.6), .float(1500)
            ), maxSampleOffset: CGSize(width: 64, height: 64))
            .opacity(opacity)
    }

    // MARK: Burst

    private var palette: [Color] {
        switch impact.kind {
        case .apple: [.white, Color(white: 0.85), Color(red: 0.62, green: 0.78, blue: 1), .white]
        case .passkey: [Color(red: 0.62, green: 0.4, blue: 1), Color(red: 0.25, green: 0.85, blue: 1),
                        Color(red: 1, green: 0.42, blue: 0.85), Color(red: 0.62, green: 0.4, blue: 1)]
        }
    }

    private func easeOut(_ x: Double) -> Double { 1 - pow(1 - min(max(x, 0), 1), 3) }

    private func drawBurst(_ gc: inout GraphicsContext, size: CGSize, t: Double) {
        let o = impact.origin
        let maxR = hypot(max(o.x, size.width - o.x), max(o.y, size.height - o.y)) + 40
        let colors = palette

        // 1. Flash: a bloom that spikes immediately and fades.
        let flash = t < 0.06 ? t / 0.06 : max(0, 1 - (t - 0.06) / 0.4)
        if flash > 0 {
            let r = 60 + 260 * easeOut(t / 0.5)
            var g = gc
            g.opacity = flash * 0.9
            g.fill(Path(ellipseIn: CGRect(x: o.x - r, y: o.y - r, width: r * 2, height: r * 2)),
                   with: .radialGradient(Gradient(colors: [colors[0].opacity(0.95), colors[1].opacity(0.35), .clear]),
                                         center: o, startRadius: 0, endRadius: r))
            // Glowing outline around the pressed button.
            let b = impact.buttonSize
            let grow = 1 + 0.25 * easeOut(t / 0.35)
            let rect = CGRect(x: o.x - b.width * grow / 2, y: o.y - b.height * grow / 2,
                              width: b.width * grow, height: b.height * grow)
            g.addFilter(.blur(radius: 6))
            g.stroke(Path(roundedRect: rect, cornerRadius: min(rect.height / 2, 14)),
                     with: .color(colors[0]), lineWidth: 4)
        }

        // 2. Shockwave rings.
        let rings: [(delay: Double, dur: Double, width: Double, alpha: Double)] = [
            (0.00, 0.85, 16, 1.0), (0.07, 0.95, 9, 0.8), (0.16, 1.05, 5, 0.6), (0.30, 1.0, 3, 0.45),
        ]
        for ring in rings {
            let p = (t - ring.delay) / ring.dur
            guard p > 0, p < 1 else { continue }
            let r = maxR * easeOut(p)
            let circle = Path(ellipseIn: CGRect(x: o.x - r, y: o.y - r, width: r * 2, height: r * 2))
            let shading = GraphicsContext.Shading.conicGradient(Gradient(colors: colors), center: o,
                                                               angle: .degrees(t * 240))
            let width = ring.width * (1 - p * 0.75)
            var glow = gc
            glow.opacity = ring.alpha * (1 - p) * 0.8
            glow.addFilter(.blur(radius: 10))
            glow.stroke(circle, with: shading, lineWidth: width * 2.2)
            var line = gc
            line.opacity = ring.alpha * (1 - p)
            line.stroke(circle, with: shading, lineWidth: width)
        }

        // 3. Sparks flying outward.
        let sparkP = t / 0.85
        if sparkP < 1 {
            var g = gc
            g.opacity = 1 - sparkP
            for i in 0..<32 {
                let seed = Double(i) * 12.9898
                let jitter = (sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1)
                let angle = Double(i) / 32 * 2 * .pi + jitter * 0.3
                let speed = 220 + abs(jitter) * 380
                let d = speed * easeOut(sparkP)
                let tail = 18 * (1 - sparkP) + 4
                let dir = CGPoint(x: cos(angle), y: sin(angle))
                var path = Path()
                path.move(to: CGPoint(x: o.x + dir.x * d, y: o.y + dir.y * d))
                path.addLine(to: CGPoint(x: o.x + dir.x * max(0, d - tail), y: o.y + dir.y * max(0, d - tail)))
                g.stroke(path, with: .color(colors[i % colors.count]),
                         style: StrokeStyle(lineWidth: 2.5 * (1 - sparkP) + 0.5, lineCap: .round))
            }
        }
    }

    /// Reduce Motion: a single soft glow, no movement.
    private func drawGentleGlow(_ gc: inout GraphicsContext, t: Double) {
        let o = impact.origin
        let a = t < 0.15 ? t / 0.15 : max(0, 1 - (t - 0.15) / 0.6)
        let r = 160.0
        var g = gc
        g.opacity = a * 0.7
        g.fill(Path(ellipseIn: CGRect(x: o.x - r, y: o.y - r, width: r * 2, height: r * 2)),
               with: .radialGradient(Gradient(colors: [palette[0], .clear]), center: o, startRadius: 0, endRadius: r))
    }
}

/// The content card takes the hit: a short punch-in plus a damped shake.
struct ImpactShake: ViewModifier {
    let trigger: UUID?

    func body(content: Content) -> some View {
        if Motion.reduceMotion {
            content
        } else {
            content.keyframeAnimator(initialValue: ShakeValues(), trigger: trigger) { view, v in
                view.scaleEffect(v.scale).offset(x: v.x, y: v.y)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(0.982, duration: 0.07)
                    SpringKeyframe(1.0, duration: 0.5, spring: .bouncy(duration: 0.5, extraBounce: 0.3))
                }
                KeyframeTrack(\.x) {
                    LinearKeyframe(-7, duration: 0.04)
                    LinearKeyframe(6, duration: 0.05)
                    LinearKeyframe(-4, duration: 0.06)
                    LinearKeyframe(2.5, duration: 0.07)
                    LinearKeyframe(-1, duration: 0.08)
                    CubicKeyframe(0, duration: 0.1)
                }
                KeyframeTrack(\.y) {
                    LinearKeyframe(3, duration: 0.05)
                    LinearKeyframe(-3, duration: 0.06)
                    LinearKeyframe(1.5, duration: 0.07)
                    CubicKeyframe(0, duration: 0.12)
                }
            }
        }
    }

    struct ShakeValues {
        var scale = 1.0
        var x = 0.0
        var y = 0.0
    }
}
