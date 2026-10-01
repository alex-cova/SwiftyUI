import CoreGraphics
import Foundation

/// Layout inset applied to mock content inside a device screen. Distinct from the physical
/// bezel insets: the home indicator stays on the visual bottom in landscape, so this is
/// computed from cutout / orientation rather than transposed with the chassis.
public nonisolated struct MockupSafeArea: Equatable, Sendable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat

    public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public static let zero = MockupSafeArea(top: 0, leading: 0, bottom: 0, trailing: 0)
}
