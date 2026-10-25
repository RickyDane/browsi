import SwiftUI

/// Slowly drifting mesh gradient tinted by the active space. Pauses when the window is inactive.
struct MeshBackground: View {
    var hue: Double
    var animated: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animated || !appearsActive || Motion.reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate / 6
            MeshGradient(width: 3, height: 3, points: points(t), colors: colors)
        }
        .animation(Motion.smooth, value: hue)
        .ignoresSafeArea()
    }

    private func points(_ t: Double) -> [SIMD2<Float>] {
        func w(_ base: Float, _ phase: Double, _ amp: Float = 0.12) -> Float {
            base + amp * Float(sin(t + phase))
        }
        return [
            [0, 0], [w(0.5, 0), 0], [1, 0],
            [0, w(0.5, 1.3)], [w(0.5, 2.1, 0.2), w(0.5, 0.7, 0.2)], [1, w(0.5, 3.4)],
            [0, 1], [w(0.5, 4.2), 1], [1, 1],
        ]
    }

    private var colors: [Color] {
        let dark = scheme == .dark
        let b = dark ? 0.32 : 0.98
        let s = dark ? 0.55 : 0.35
        func c(_ dh: Double, _ db: Double = 0) -> Color {
            Color(hue: (hue + dh + 1).truncatingRemainder(dividingBy: 1), saturation: s, brightness: b + db)
        }
        return [c(0), c(0.05), c(0.1, -0.05),
                c(-0.05), c(0.02, -0.08), c(0.08),
                c(-0.1, -0.05), c(-0.03), c(0.04, -0.1)]
    }
}
