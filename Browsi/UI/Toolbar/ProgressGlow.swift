import SwiftUI

/// A glowing progress line along the top edge of the content card.
struct ProgressGlow: View {
    var progress: Double
    var isLoading: Bool
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(LinearGradient(colors: [tint.opacity(0.6), tint, .white.opacity(0.9)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: geo.size.width * max(0.04, progress), height: 3)
                .shadow(color: tint.opacity(0.9), radius: 6)
                .shadow(color: tint.opacity(0.5), radius: 14)
                .opacity(isLoading ? 1 : 0)
                .animation(.easeOut(duration: 0.25), value: progress)
                .animation(.easeOut(duration: isLoading ? 0.1 : 0.6).delay(isLoading ? 0 : 0.2), value: isLoading)
        }
        .frame(height: 3)
        .allowsHitTesting(false)
    }
}
