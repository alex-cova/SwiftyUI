import SwiftUI

/// Resolves the leading-dot tokens captured during lowering (`.red`, `.center`, `.title`, …)
/// to concrete SwiftUI values. Kept `nonisolated` and free of view code so the lowering tests
/// can exercise it too. Anything unrecognized returns `nil`, and the renderer supplies a
/// sensible default.
public nonisolated enum MockupTokens {
    // MARK: Colors

    public static func color(_ value: MockValue) -> Color? {
        guard case let .token(name) = value else { return nil }
        return namedColor(name)
    }

    public static func namedColor(_ name: String) -> Color? {
        switch name {
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "mint": .mint
        case "teal": .teal
        case "cyan": .cyan
        case "blue": .blue
        case "indigo": .indigo
        case "purple": .purple
        case "pink": .pink
        case "brown": .brown
        case "black": .black
        case "white": .white
        case "gray", "grey": .gray
        case "clear": .clear
        case "primary": .primary
        case "secondary": .secondary
        case "tertiary": Color.secondary.opacity(0.5)
        case "quaternary": Color.secondary.opacity(0.25)
        case "accentColor", "accent", "tint": .accentColor
        default: nil
        }
    }

    // MARK: Shape styles (colors + gradients + hierarchical)

    public static func shapeStyle(_ value: MockValue) -> AnyShapeStyle {
        switch value {
        case let .gradient(gradient):
            return AnyShapeStyle(linearOrOther(gradient))
        case let .token(name):
            if let color = namedColor(name) { return AnyShapeStyle(color) }
            return AnyShapeStyle(.foreground)
        case let .string(name):
            return AnyShapeStyle(namedColor(name) ?? .gray)
        default:
            return AnyShapeStyle(.foreground)
        }
    }

    public static func unitPoint(_ name: String?) -> UnitPoint? {
        switch name {
        case "top": .top
        case "bottom": .bottom
        case "leading": .leading
        case "trailing": .trailing
        case "topLeading": .topLeading
        case "topTrailing": .topTrailing
        case "bottomLeading": .bottomLeading
        case "bottomTrailing": .bottomTrailing
        case "center": .center
        default: nil
        }
    }

    private static func linearOrOther(_ gradient: MockGradient) -> some ShapeStyle {
        let colors = gradient.colors.map { namedColor(colorName($0)) ?? .gray }
        let stops = colors.isEmpty ? [Color.gray, Color.accentColor] : colors
        switch gradient.kind {
        case .linear:
            return AnyShapeStyle(LinearGradient(
                colors: stops,
                startPoint: unitPoint(gradient.startPoint) ?? .top,
                endPoint: unitPoint(gradient.endPoint) ?? .bottom
            ))
        case .radial:
            return AnyShapeStyle(RadialGradient(
                colors: stops,
                center: unitPoint(gradient.startPoint) ?? .center,
                startRadius: 0,
                endRadius: 160
            ))
        case .angular:
            return AnyShapeStyle(AngularGradient(
                colors: stops,
                center: unitPoint(gradient.startPoint) ?? .center
            ))
        }
    }

    private static func colorName(_ value: MockValue) -> String {
        switch value {
        case let .token(name): name
        case let .string(name): name
        default: ""
        }
    }

    // MARK: Fonts

    public static func font(_ value: MockValue) -> Font? {
        switch value {
        case let .systemFont(size, weight):
            return .system(size: size, weight: fontWeight(weight ?? "") ?? .regular)
        case let .token(name):
            return namedFont(name)
        default:
            return nil
        }
    }

    public static func namedFont(_ name: String) -> Font? {
        switch name {
        case "largeTitle": .largeTitle
        case "title": .title
        case "title2": .title2
        case "title3": .title3
        case "headline": .headline
        case "subheadline": .subheadline
        case "body": .body
        case "callout": .callout
        case "footnote": .footnote
        case "caption": .caption
        case "caption2": .caption2
        default: nil
        }
    }

    public static func fontWeight(_ value: MockValue) -> Font.Weight? {
        guard case let .token(name) = value else { return nil }
        return fontWeight(name)
    }

    public static func fontWeight(_ name: String) -> Font.Weight? {
        switch name {
        case "ultraLight": .ultraLight
        case "thin": .thin
        case "light": .light
        case "regular": .regular
        case "medium": .medium
        case "semibold": .semibold
        case "bold": .bold
        case "heavy": .heavy
        case "black": .black
        default: nil
        }
    }

    // MARK: Alignment

    public static func horizontalAlignment(_ value: MockValue?) -> HorizontalAlignment {
        guard case let .token(name) = value else { return .center }
        switch name {
        case "leading": return .leading
        case "trailing": return .trailing
        default: return .center
        }
    }

    public static func verticalAlignment(_ value: MockValue?) -> VerticalAlignment {
        guard case let .token(name) = value else { return .center }
        switch name {
        case "top": return .top
        case "bottom": return .bottom
        case "firstTextBaseline": return .firstTextBaseline
        case "lastTextBaseline": return .lastTextBaseline
        default: return .center
        }
    }

    public static func alignment(_ value: MockValue?) -> Alignment {
        guard case let .token(name) = value else { return .center }
        switch name {
        case "topLeading": return .topLeading
        case "top": return .top
        case "topTrailing": return .topTrailing
        case "leading": return .leading
        case "trailing": return .trailing
        case "bottomLeading": return .bottomLeading
        case "bottom": return .bottom
        case "bottomTrailing": return .bottomTrailing
        default: return .center
        }
    }

    public static func textAlignment(_ value: MockValue) -> TextAlignment {
        guard case let .token(name) = value else { return .leading }
        switch name {
        case "center": return .center
        case "trailing": return .trailing
        default: return .leading
        }
    }

    public static func edges(_ value: MockValue?) -> Edge.Set {
        guard case let .token(name) = value else { return .all }
        switch name {
        case "horizontal": return .horizontal
        case "vertical": return .vertical
        case "top": return .top
        case "bottom": return .bottom
        case "leading": return .leading
        case "trailing": return .trailing
        default: return .all
        }
    }

    // MARK: iOS 26 — Liquid Glass

    public static func glass(_ value: MockGlass) -> Glass {
        var glass: Glass
        switch value.variant {
        case .regular: glass = .regular
        case .clear: glass = .clear
        case .identity: glass = .identity
        }
        if let tint = value.tint, let color = self.color(tint) {
            glass = glass.tint(color)
        }
        if value.interactive {
            glass = glass.interactive()
        }
        return glass
    }

    // MARK: iOS 26 — shapes

    public static func anyShape(_ shape: MockShape) -> AnyShape {
        switch shape {
        case .rectangle: AnyShape(Rectangle())
        case let .roundedRectangle(radius): AnyShape(RoundedRectangle(cornerRadius: CGFloat(radius)))
        case .circle: AnyShape(Circle())
        case .capsule: AnyShape(Capsule())
        case .ellipse: AnyShape(Ellipse())
        case .concentric: AnyShape(ConcentricRectangle())
        case let .unevenRoundedRectangle(topLeading, bottomLeading, bottomTrailing, topTrailing):
            AnyShape(UnevenRoundedRectangle(
                topLeadingRadius: CGFloat(topLeading),
                bottomLeadingRadius: CGFloat(bottomLeading),
                bottomTrailingRadius: CGFloat(bottomTrailing),
                topTrailingRadius: CGFloat(topTrailing)
            ))
        }
    }

    // MARK: iOS 26 — symbols

    public static func symbolRenderingMode(_ mode: MockSymbolRenderingMode) -> SymbolRenderingMode {
        switch mode {
        case .monochrome: .monochrome
        case .hierarchical: .hierarchical
        case .palette: .palette
        case .multicolor: .multicolor
        }
    }

    public static func symbolColorRenderingMode(_ mode: MockSymbolColorRenderingMode) -> SymbolColorRenderingMode {
        switch mode {
        case .flat: .flat
        case .gradient: .gradient
        }
    }

    public static func symbolVariableValueMode(_ mode: MockSymbolVariableValueMode) -> SymbolVariableValueMode {
        switch mode {
        case .color: .color
        case .draw: .draw
        }
    }

    public static func imageScale(_ scale: MockImageScale) -> Image.Scale {
        switch scale {
        case .small: .small
        case .medium: .medium
        case .large: .large
        }
    }

    // MARK: iOS 26 — control sizing

    public static func controlSize(_ size: MockControlSize) -> ControlSize {
        switch size {
        case .mini: .mini
        case .small: .small
        case .regular: .regular
        case .large: .large
        case .extraLarge: .extraLarge
        }
    }

    public static func scrollEdgeEffectStyle(_ style: MockScrollEdgeStyle) -> ScrollEdgeEffectStyle {
        switch style {
        case .automatic: .automatic
        case .soft: .soft
        case .hard: .hard
        }
    }
}
