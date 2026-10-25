import SwiftUI

/// Night sky: deep-space gradient tinted by the space's hue, a faint nebula, twinkling stars and
/// (optionally) shooting stars at random intervals. Everything is derived from time + a fixed seed,
/// so it needs no state and costs one Canvas draw per frame (paused when the window is inactive).
struct StarfieldView: View {
    var hue: Double
    var starCount = 260
    var shootingStars = false
    var animated = true
    /// `Preferences.backgroundIntensity` (0…1); 0.85 is the default look.
    var intensity = 0.85
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animated || !appearsActive || Motion.reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                let k = Self.glowScale(intensity)
                Self.drawSky(&g, size, hue: hue, glow: k)
                Self.drawStars(&g, size, count: starCount, t: t, brightness: min(1, 0.45 + 0.55 * k))
                if shootingStars { Self.drawMeteors(&g, size, t: t) }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Drawing

    /// Maps intensity to a nebula multiplier: 0 → none, 0.85 → 1 (default), 1 → 1.8.
    nonisolated static func glowScale(_ intensity: Double) -> Double {
        let i = min(max(intensity, 0), 1)
        return i <= 0.85 ? i / 0.85 : 1 + (i - 0.85) / 0.15 * 0.8
    }

    static func drawSky(_ g: inout GraphicsContext, _ size: CGSize, hue: Double, glow: Double = 1) {
        let rect = CGRect(origin: .zero, size: size)
        g.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [Color(red: 0.02, green: 0.025, blue: 0.07),
                              Color(hue: hue, saturation: 0.55 * min(1, glow), brightness: 0.05 + 0.08 * glow),
                              Color(red: 0.03, green: 0.02, blue: 0.08)]),
            startPoint: .zero, endPoint: CGPoint(x: size.width * 0.4, y: size.height)))
        // Nebula glows.
        let r = max(size.width, size.height)
        for (cx, cy, dh, a) in [(0.78, 0.18, 0.0, 0.30), (0.15, 0.85, 0.12, 0.22), (0.5, 0.55, -0.08, 0.10)] {
            let c = CGPoint(x: size.width * cx, y: size.height * cy)
            g.fill(Path(rect), with: .radialGradient(
                Gradient(colors: [Color(hue: (hue + dh + 1).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.75).opacity(min(1, a * glow)), .clear]),
                center: c, startRadius: 0, endRadius: r * 0.55))
        }
    }

    static func drawStars(_ g: inout GraphicsContext, _ size: CGSize, count: Int, t: Double, brightness: Double = 1) {
        var rng = SeededRandom(seed: 0xB10_5E1)
        for _ in 0..<count {
            let x = rng.next() * size.width, y = rng.next() * size.height
            let big = rng.next() < 0.07
            let radius = big ? 1.1 + rng.next() * 0.9 : 0.35 + rng.next() * 0.75
            let speed = 0.6 + rng.next() * 2.2, phase = rng.next() * .pi * 2
            let base = 0.35 + rng.next() * 0.55
            let twinkle = 0.65 + 0.35 * sin(t * speed + phase)
            let tint = rng.next()
            let color: Color = tint < 0.15 ? Color(red: 0.75, green: 0.85, blue: 1)
                : tint < 0.25 ? Color(red: 1, green: 0.9, blue: 0.78) : .white
            let alpha = base * twinkle * brightness
            g.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                   with: .color(color.opacity(alpha)))
            if big {   // soft halo
                let h = radius * 4
                g.fill(Path(ellipseIn: CGRect(x: x - h, y: y - h, width: h * 2, height: h * 2)),
                       with: .radialGradient(Gradient(colors: [color.opacity(alpha * 0.35), .clear]),
                                             center: CGPoint(x: x, y: y), startRadius: 0, endRadius: h))
            }
        }
    }

    /// Up to one meteor per 2.6 s slot (≈45 % of slots), at a random moment, angle and place.
    static func drawMeteors(_ g: inout GraphicsContext, _ size: CGSize, t: Double) {
        let slotLength = 2.6, duration = 1.1
        let current = Int(floor(t / slotLength))
        for slot in (current - 1)...current {
            var rng = SeededRandom(seed: UInt64(bitPattern: Int64(slot)) &* 0x9E37_79B9 &+ 17)
            guard rng.next() < 0.45 else { continue }
            let start = Double(slot) * slotLength + rng.next() * (slotLength - 0.3)
            let p = (t - start) / duration
            guard p >= 0, p <= 1 else { continue }
            let from = CGPoint(x: size.width * (0.15 + rng.next() * 0.8), y: size.height * (0.02 + rng.next() * 0.45))
            let angle = (.pi / 180) * (150 + rng.next() * 35)       // heading down-left
            let travel = min(size.width, size.height) * (0.35 + rng.next() * 0.3)
            let eased = 1 - pow(1 - p, 2)
            let head = CGPoint(x: from.x + cos(angle) * travel * eased, y: from.y + sin(angle) * travel * eased)
            let tailLength = travel * 0.35 * min(1, p * 3)
            let tail = CGPoint(x: head.x - cos(angle) * tailLength, y: head.y - sin(angle) * tailLength)
            let fade = p < 0.8 ? 1 : (1 - p) / 0.2
            var path = Path()
            path.move(to: tail)
            path.addLine(to: head)
            g.stroke(path, with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.9 * fade)]),
                                                 startPoint: tail, endPoint: head),
                     style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            g.fill(Path(ellipseIn: CGRect(x: head.x - 6, y: head.y - 6, width: 12, height: 12)),
                   with: .radialGradient(Gradient(colors: [Color.white.opacity(0.9 * fade), Color(red: 0.6, green: 0.8, blue: 1).opacity(0)]),
                                         center: head, startRadius: 0, endRadius: 6))
        }
    }
}

/// Tiny deterministic PRNG (SplitMix64) for stable star positions.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
