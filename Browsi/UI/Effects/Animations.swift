import SwiftUI

/// Shared motion vocabulary. Falls back to simple fades when Reduce Motion is on.
enum Motion {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || Preferences.shared.reduceAnimations
    }

    static var snappy: Animation { reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.32, extraBounce: 0.06) }
    static var bouncy: Animation { reduceMotion ? .easeInOut(duration: 0.15) : .bouncy(duration: 0.45, extraBounce: 0.12) }
    static var smooth: Animation { reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.42) }
}

/// Scale + blur + fade: used by the palette and floating glass panels.
struct BlurScaleTransition: Transition {
    var scale: CGFloat = 0.92
    var blur: CGFloat = 14

    func body(content: Content, phase: TransitionPhase) -> some View {
        let reduce = Motion.reduceMotion
        content
            .scaleEffect(phase.isIdentity || reduce ? 1 : scale)
            .blur(radius: phase.isIdentity || reduce ? 0 : blur)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

extension AnyTransition {
    static var tabInsert: AnyTransition {
        Motion.reduceMotion ? .opacity : .asymmetric(
            insertion: .scale(scale: 0.6, anchor: .leading).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity))
    }
}

/// Pressable feel for custom buttons: squish on press, lift on hover.
struct SquishButtonStyle: ButtonStyle {
    var hoverBackground = true
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(6)
            .background {
                if hoverBackground {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.primary.opacity(configuration.isPressed ? 0.14 : hovering ? 0.08 : 0))
                }
            }
            .scaleEffect(configuration.isPressed && !Motion.reduceMotion ? 0.88 : 1)
            .animation(Motion.bouncy, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
            .contentShape(Rectangle())
    }
}
