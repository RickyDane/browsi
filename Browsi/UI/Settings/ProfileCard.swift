import SwiftUI

/// Profile card: a view from orbit. Black sky with fine stars, a planet's horizon across the lower
/// half, and the user's name above the Mac's specs. The card tilts towards the cursor and the
/// sunlight on the atmosphere follows it, with stars, horizon and text on separate parallax depths.
struct ProfileCard: View {
    var name: String
    var handle: String
    var mac: MacInfo
    /// Hue of the atmosphere (the selected space's hue).
    var hue: Double

    static let size = CGSize(width: 480, height: 302)       // ID-1 card proportions
    private static let corner: CGFloat = 22
    private static let planetDiameter: CGFloat = 1640
    private static let horizonY: CGFloat = 200               // top of the limb, in card coordinates
    private static let restingLight = CGPoint(x: 0.74, y: 0.3)

    /// Cursor position in unit coordinates; nil when the pointer is outside the card.
    @State private var pointer: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var still: Bool { systemReduceMotion || Motion.reduceMotion }

    /// -1…1 offset of the pointer from the card's centre.
    private var tilt: CGSize {
        guard let p = pointer, !still else { return .zero }
        return CGSize(width: (p.x - 0.5) * 2, height: (p.y - 0.5) * 2)
    }

    private var light: CGPoint { still ? Self.restingLight : (pointer ?? Self.restingLight) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
        ZStack(alignment: .topLeading) {
            Sky()
                .frame(width: Self.size.width + 24, height: Self.size.height + 24)
                .offset(x: -12 - tilt.width * 5, y: -12 - tilt.height * 5)
            horizon
                .offset(x: tilt.width * 7, y: tilt.height * 4)
            content
                .offset(x: tilt.width * 2.5, y: tilt.height * 2.5)
            sheen
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .clipShape(shape)
        .overlay(edge(shape))
        .environment(\.colorScheme, .dark)
        .contentShape(shape)
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                let p = CGPoint(x: min(max(location.x / Self.size.width, 0), 1),
                                y: min(max(location.y / Self.size.height, 0), 1))
                withAnimation(Motion.snappy) { pointer = p }
            case .ended:
                withAnimation(Motion.smooth) { pointer = nil }
            }
        }
        .rotation3DEffect(.degrees(-tilt.height * 5), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
        .rotation3DEffect(.degrees(tilt.width * 7), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        .scaleEffect(pointer == nil || still ? 1 : 1.015)
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        .shadow(color: .black.opacity(pointer == nil ? 0.28 : 0.38), radius: pointer == nil ? 18 : 26,
                x: -tilt.width * 10, y: 14 - tilt.height * 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name). \(mac.modelName), \(mac.chip), \(mac.memory) memory, \(mac.osVersion)")
    }

    // MARK: Layers

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().interpolation(.high)
                    .frame(width: 18, height: 18)
                Text("Browsi")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                Image(systemName: mac.symbol)
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("@\(handle)")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.bottom, 86)

            HStack(alignment: .top, spacing: 22) {
                spec("Model", mac.modelName).layoutPriority(1)
                spec("Chip", mac.shortChip)
                spec("Memory", mac.memory)
                spec("macOS", mac.systemVersion)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 22)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }

    private func spec(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1).minimumScaleFactor(0.75)
        }
    }

    private var horizon: some View {
        let d = Self.planetDiameter
        let origin = CGPoint(x: Self.size.width * 0.42 - d / 2, y: Self.horizonY)
        return Horizon(hue: hue, lightX: light.x * Self.size.width - origin.x, lit: pointer == nil ? 0 : 1)
            .frame(width: d, height: d)
            .offset(x: origin.x, y: origin.y)
            .allowsHitTesting(false)
    }

    /// Faint specular reflection on the card surface.
    private var sheen: some View {
        RadialGradient(colors: [.white.opacity(0.07), .clear],
                       center: UnitPoint(x: light.x, y: light.y), startRadius: 0, endRadius: 300)
            .blendMode(.plusLighter)
            .opacity(pointer == nil ? 0 : 1)
            .allowsHitTesting(false)
    }

    /// Hairline edge, brightest on the side nearest the light.
    private func edge(_ shape: RoundedRectangle) -> some View {
        shape.strokeBorder(RadialGradient(colors: [.white.opacity(pointer == nil ? 0.16 : 0.32), .white.opacity(0.06)],
                                          center: UnitPoint(x: light.x, y: light.y), startRadius: 0, endRadius: 360),
                           lineWidth: 0.75)
            .allowsHitTesting(false)
    }

    // MARK: Helpers

    /// Height of a circle's top edge at `x`, measured from the top of its bounding box.
    nonisolated static func limbY(atX x: CGFloat, diameter d: CGFloat) -> CGFloat {
        let r = d / 2, dx = min(abs(x - r), r)
        return r - (r * r - dx * dx).squareRoot()
    }
}

/// Near-black sky with slowly twinkling stars (shares the star renderer with the window background).
private struct Sky: View {
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !appearsActive || Motion.reduceMotion)) { ctx in
            Canvas { g, size in
                g.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                    Gradient(colors: [Color(red: 0.016, green: 0.018, blue: 0.034), Color(red: 0.008, green: 0.009, blue: 0.016)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                StarfieldView.drawStars(&g, size, count: 120, t: ctx.date.timeIntervalSinceReferenceDate * 0.6, brightness: 0.7)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A planet seen edge-on from orbit: dark surface, thin atmosphere, and sunlight at `lightX`
/// (in the planet's own coordinates) that brightens the limb and spills onto the surface.
private struct Horizon: View {
    var hue: Double
    var lightX: CGFloat
    /// 0 at rest, 1 while hovered (the sun is a little brighter).
    var lit: Double

    var body: some View {
        GeometryReader { geo in
            let d = geo.size.width
            let lightY = ProfileCard.limbY(atX: lightX, diameter: d)
            let air = Color(hue: hue, saturation: 0.38, brightness: 1)
            ZStack {
                // Scattered light above the limb (the surface below covers the inner half).
                Circle().stroke(air.opacity(0.16), lineWidth: 26).blur(radius: 18)
                Circle().stroke(air.opacity(0.28 + 0.12 * lit), lineWidth: 10).blur(radius: 14)
                    .mask(glow(width: 520, height: 260, at: CGPoint(x: lightX, y: lightY), size: geo.size))

                Circle().fill(Color(red: 0.01, green: 0.012, blue: 0.022))

                // Day side bleeding over the horizon.
                glow(width: 620, height: 200, at: CGPoint(x: lightX, y: lightY + 20), size: geo.size)
                    .foregroundStyle(air.opacity(0.13 + 0.05 * lit))
                    .clipShape(Circle())

                // The limb: a hairline all round, a bright arc near the sun.
                Circle().strokeBorder(air.opacity(0.28), lineWidth: 0.75)
                Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.25)
                    .mask(glow(width: 320, height: 120, at: CGPoint(x: lightX, y: lightY), size: geo.size))
                Circle().strokeBorder(air, lineWidth: 3).blur(radius: 3)
                    .opacity(0.55 + 0.25 * lit)
                    .mask(glow(width: 420, height: 160, at: CGPoint(x: lightX, y: lightY), size: geo.size))
                // Thin warm layer under the blue, as at an orbital sunrise.
                Circle().inset(by: 2.2).stroke(Color(red: 1, green: 0.62, blue: 0.32), lineWidth: 1.5).blur(radius: 1.2)
                    .opacity(0.5 + 0.3 * lit)
                    .mask(glow(width: 220, height: 90, at: CGPoint(x: lightX, y: lightY), size: geo.size))

                // The sun, just cresting the limb.
                ZStack {
                    Circle().fill(.white.opacity(0.22 + 0.1 * lit)).frame(width: 70, height: 70).blur(radius: 22)
                    Circle().fill(.white).frame(width: 5, height: 5).blur(radius: 1.2)
                }
                .position(x: lightX, y: lightY - 1)
            }
        }
    }

    /// A soft elliptical spot, used both as a light and as a mask.
    private func glow(width: CGFloat, height: CGFloat, at point: CGPoint, size: CGSize) -> some View {
        Ellipse()
            .frame(width: width, height: height)
            .blur(radius: height / 3)
            .position(point)
            .frame(width: size.width, height: size.height)
    }
}
