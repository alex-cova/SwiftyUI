import SwiftUI

/// Spacing and motion for the rendered sketch. These match Hextech's workbench scale so a
/// mock drawn here looks the same as it did before the renderer moved out of the app.
enum RenderSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
}

enum RenderMotion {
    static let standard: Animation = .snappy(duration: 0.2)
    static let emphasized: Animation = .snappy(duration: 0.28)
    static let reduced: Animation = .easeOut(duration: 0.1)
}

private struct RenderAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? RenderMotion.reduced : animation, value: value)
    }
}

extension View {
    /// `.animation(_:value:)` that drops to a short fade under Reduce Motion.
    func renderAnimation<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(RenderAnimationModifier(animation: animation, value: value))
    }
}
