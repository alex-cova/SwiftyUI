import Foundation

/// A single scalar value pulled out of the source: a string/number/bool literal, or a
/// leading-dot token like `.red` / `.center` / `.title`. The renderer and `MockupTokens`
/// resolve tokens to real SwiftUI values; anything unrecognized falls back to a default.
public nonisolated enum MockValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    /// `.red`, `.center`, `.title`, `Color.red` → `.token("red")` etc. Base is dropped.
    case token(String)
    /// `.system(size:weight:)` — the one font factory worth capturing structurally.
    case systemFont(size: Double, weight: String?)
    /// `LinearGradient(...)` / `.radialGradient(...)` and friends.
    case gradient(MockGradient)
    case unknown
}

/// A gradient shape style captured from `LinearGradient`/`RadialGradient`/`AngularGradient`
/// (or their `.linearGradient` shorthand). Points are left as tokens (`.top`, `.bottomTrailing`).
public nonisolated struct MockGradient: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case linear
        case radial
        case angular
    }

    public var kind: Kind
    public var colors: [MockValue]
    /// Unit-point token names (`top`, `bottomTrailing`) — kept as strings to keep `MockValue`
    /// non-recursive.
    public var startPoint: String?
    public var endPoint: String?
}

public nonisolated extension MockValue {
    /// String view of a literal — numbers render without a trailing `.0`.
    var asString: String? {
        switch self {
        case let .string(value): value
        case let .number(value): value == value.rounded() ? String(Int(value)) : String(value)
        case let .bool(value): String(value)
        default: nil
        }
    }

    var asNumber: Double? {
        if case let .number(value) = self { return value }
        return nil
    }

    var asBool: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }
}

/// Vector primitive a `MockNode.shape` renders.
public nonisolated enum MockShape: Sendable, Equatable {
    case rectangle
    case roundedRectangle(cornerRadius: Double)
    case circle
    case capsule
    case ellipse
    /// `ConcentricRectangle()` — iOS 26's corner style that concentrically matches its container.
    case concentric
    /// `UnevenRoundedRectangle(topLeadingRadius:bottomLeadingRadius:bottomTrailingRadius:topTrailingRadius:)`.
    case unevenRoundedRectangle(topLeading: Double, bottomLeading: Double, bottomTrailing: Double, topTrailing: Double)
}

/// `.regular` / `.clear` / `.identity`, optionally tinted and made interactive — captured from a
/// `.glassEffect(...)` argument's member-access chain (`.regular.tint(.blue).interactive()`).
public nonisolated struct MockGlass: Sendable, Equatable {
    public enum Variant: Sendable, Equatable {
        case regular
        case clear
        case identity
    }

    public var variant: Variant = .regular
    public var tint: MockValue?
    public var interactive: Bool = false
}

/// `.buttonStyle(_:)` — iOS 26 adds `.glass` / `.glassProminent` alongside the existing styles.
public nonisolated enum MockButtonStyle: Sendable, Equatable {
    case automatic
    case plain
    case bordered
    case borderedProminent
    case borderless
    case glass
    case glassProminent
}

public nonisolated enum MockTabViewStyle: Sendable, Equatable {
    case automatic
    case page
    case sidebarAdaptable
    case grouped
}

/// `.tabBarMinimizeBehavior(_:)`. `.onScrollDown` / `.onScrollUp` are iOS-only in real SwiftUI —
/// captured here anyway so the mock can sketch the compact pill form on any chrome.
public nonisolated enum MockTabBarMinimizeBehavior: Sendable, Equatable {
    case automatic
    case onScrollDown
    case onScrollUp
    case never
}

/// Where a `ToolbarItem`/`ToolbarItemGroup`/`ToolbarSpacer` sits, collapsed from the many real
/// `ToolbarItemPlacement` cases (`.topBarLeading`, `.navigation`, `.cancellationAction`, …) down
/// to the four visual buckets that actually differ in a static sketch.
public nonisolated enum MockToolbarPlacement: Sendable, Equatable {
    case leading
    case trailing
    case principal
    case bottomBar
}

/// One item lowered from a `.toolbar { }` closure.
public nonisolated struct MockToolbarItem: Sendable, Equatable {
    public var placement: MockToolbarPlacement
    public var content: MockNode?
    /// `ToolbarSpacer(_:placement:)` — splits the shared glass group; carries no content.
    public var isSpacer: Bool = false
}

public nonisolated enum MockScrollEdgeStyle: Sendable, Equatable {
    case automatic
    case soft
    case hard
}

public nonisolated enum MockPresentationSizing: Sendable, Equatable {
    case automatic
    case form
    case page
    case fitted
}

public nonisolated enum MockSymbolRenderingMode: Sendable, Equatable {
    case monochrome
    case hierarchical
    case palette
    case multicolor
}

public nonisolated enum MockSymbolColorRenderingMode: Sendable, Equatable {
    case flat
    case gradient
}

public nonisolated enum MockSymbolVariableValueMode: Sendable, Equatable {
    case color
    case draw
}

/// `.symbolEffect(...)`. The canvas is static, so each case renders its *end state* rather than
/// animating — see `MockNodeView.imageView(for:)`.
public nonisolated enum MockSymbolEffect: Sendable, Equatable {
    case appear
    case disappear
    case bounce
    case pulse
    case variableColor
    case wiggle
    case breathe
    case rotate
    case replace
    case drawOn
    case drawOff
}

public nonisolated enum MockImageScale: Sendable, Equatable {
    case small
    case medium
    case large
}

public nonisolated enum MockListStyle: Sendable, Equatable {
    case automatic
    case plain
    case inset
    case grouped
    case insetGrouped
    case sidebar
}

public nonisolated enum MockToggleStyle: Sendable, Equatable {
    case automatic
    case swiftSwitch
    case button
    case checkbox
}

public nonisolated enum MockLabelStyle: Sendable, Equatable {
    case automatic
    case iconOnly
    case titleOnly
    case titleAndIcon
}

public nonisolated enum MockProgressViewStyle: Sendable, Equatable {
    case automatic
    case linear
    case circular
}

public nonisolated enum MockControlSize: Sendable, Equatable {
    case mini
    case small
    case regular
    case large
    case extraLarge
}

/// Where an `Image` node's bitmap comes from. `.system` is an SF Symbol name; `.asset` is a
/// name in the workspace's shared image library (`MockupAssetLibrary`), resolved by the
/// renderer — the engine only carries the name so it stays pure and `Sendable`.
public nonisolated enum MockImageSource: Sendable, Equatable {
    case system(String)
    case asset(String)
}

/// `.aspectRatio(contentMode:)`'s content mode, captured structurally like `MockPickerStyle`.
public nonisolated enum MockContentMode: Sendable, Hashable {
    case fit
    case fill
}

/// How a `Picker` presents its choices. Captured from the constructor or a `.pickerStyle`
/// modifier so a segmented picker in the source looks segmented in the preview.
public nonisolated enum MockPickerStyle: Sendable, Hashable {
    case automatic
    case segmented
    case menu
    case inline
    case wheel
    case palette
}

/// Mark style of a lowered `Chart`. The data is synthetic — only the shape is kept, so the
/// preview shows a plausible bar / line / area sketch without pulling in `Charts`.
public nonisolated enum MockChartKind: Sendable, Equatable {
    case bar
    case line
    case area
}

/// One tab of a lowered `TabView`. `title` / `systemImage` come from the child's `.tabItem`, or
/// from an iOS 26 `Tab(_:systemImage:)` / `Tab(role:)` child directly.
public nonisolated struct MockTab: Sendable, Equatable {
    public var title: String
    public var systemImage: String?
    public var content: MockNode
    /// `Tab(role: .search) { }` — drawn with the search affordance instead of an icon.
    public var isSearchRole: Bool = false
    /// Set when this tab came from inside a `TabSection("Group") { }`, so the tab bar can group it.
    public var sectionTitle: String?
}

/// A `.frame(...)` application, capturing both the fixed-size and the flexible overloads.
public nonisolated struct MockFrame: Sendable, Equatable {
    public var width: Double?
    public var height: Double?
    public var minWidth: Double?
    public var maxWidth: MockDimension?
    public var minHeight: Double?
    public var maxHeight: MockDimension?
    public var alignment: MockValue?
}

public nonisolated enum MockDimension: Sendable, Equatable {
    case infinity
    case points(Double)
}

/// A view modifier lowered from a `.modifier(args)` call in the chain. Only the whitelisted
/// subset is represented; an unrecognized modifier is dropped and reported as a diagnostic.
public nonisolated enum MockModifier: Sendable, Equatable {
    /// `nil` length means the argument-less `.padding()` (system default inset).
    case padding(edges: MockValue?, length: Double?)
    case frame(MockFrame)
    case foregroundStyle(MockValue)
    case font(MockValue)
    case fontWeight(MockValue)
    case bold
    case italic
    case background(MockNode)
    case overlay(node: MockNode, alignment: MockValue?)
    case cornerRadius(Double)
    case clipShape(MockShape)
    case opacity(Double)
    case shadow(color: MockValue?, radius: Double, x: Double, y: Double)
    case border(color: MockValue, width: Double)
    case multilineTextAlignment(MockValue)
    case lineLimit(Int)
    case tint(MockValue)
    /// `.navigationTitle("…")` — the renderer draws a large-title header above the view.
    case navigationTitle(String)
    /// `.pickerStyle(.segmented)` — folded onto a `.picker` node by the renderer; a no-op on
    /// anything else.
    case pickerStyle(MockPickerStyle)
    /// `.searchable(text:)` — the renderer draws a search field above the view.
    case searchable(prompt: String?)
    /// `.sheet` / `.fullScreenCover`. `autoPresent` is true when `isPresented` folded to true.
    case sheet(content: MockNode?, targetName: String?, isCover: Bool, autoPresent: Bool)
    /// Mockup-only: tap shows the named scene (`struct: View`, `#Preview` title, or file).
    case onClickShow(String)
    /// `Shape.fill(_:)` — a shape method, not a `ViewModifier`, but captured in the chain.
    case fill(MockValue)
    case stroke(color: MockValue, lineWidth: Double)
    case strokeBorder(color: MockValue, lineWidth: Double)
    /// `.resizable()` — an `Image` method, not a real `ViewModifier`, but captured in the chain
    /// like `.fill`/`.stroke` since it only has meaning on an `.image` node.
    case resizable
    case aspectRatio(ratio: Double?, contentMode: MockContentMode)
    case clipped
    // MARK: iOS 26

    /// `.glassEffect(_:in:)`. `shape` is `nil` for the default capsule/rect-adaptive shape.
    case glassEffect(MockGlass, shape: MockShape?)
    case buttonStyle(MockButtonStyle)
    /// `.tabViewStyle(_:)` — folded onto a `.tabView` node by the renderer; a no-op elsewhere.
    case tabViewStyle(MockTabViewStyle)
    /// `.tabBarMinimizeBehavior(_:)` — folded onto a `.tabView` node; hand-drawn (no macOS API).
    case tabBarMinimizeBehavior(MockTabBarMinimizeBehavior)
    /// `.tabViewBottomAccessory { }` — folded onto a `.tabView` node; hand-drawn (no macOS API).
    case tabViewBottomAccessory(MockNode)
    /// `.toolbar { }`. Drawn alongside `.navigationTitle`'s header, or as its own bar.
    case toolbar([MockToolbarItem])
    case backgroundExtensionEffect
    case scrollEdgeEffectStyle(style: MockScrollEdgeStyle, edges: MockValue?)
    /// `.safeAreaBar(edge:) { }` / `.safeAreaInset(edge:) { }` — a pinned bar outside the safe area.
    case safeAreaBar(edge: MockValue?, node: MockNode)
    /// `.presentationSizing(_:)` / `.presentationDetents(_:)` — sizes the sheet/cover this chain
    /// eventually presents.
    case presentationSizing(MockPresentationSizing)
    case containerShape(MockShape)
    case symbolRenderingMode(MockSymbolRenderingMode)
    case symbolColorRenderingMode(MockSymbolColorRenderingMode)
    case symbolVariableValueMode(MockSymbolVariableValueMode)
    /// `.symbolEffect(...)` — the canvas is static, so this renders the effect's end state.
    case symbolEffect(MockSymbolEffect)
    case imageScale(MockImageScale)
    case listStyle(MockListStyle)
    case toggleStyle(MockToggleStyle)
    case labelStyle(MockLabelStyle)
    case progressViewStyle(MockProgressViewStyle)
    case controlSize(MockControlSize)
    case badge(MockValue)
    case alert(title: String, message: String?, buttonTitles: [String])
    case confirmationDialog(title: String, buttonTitles: [String])
}

/// The lowered mockup tree. A `kind` plus the modifier chain applied to it. Deliberately
/// structural and `Equatable` so `MockupEngineTests` can assert a snippet's shape without
/// instantiating any view.
public nonisolated struct MockNode: Sendable, Equatable {
    public var kind: Kind
    public var modifiers: [MockModifier] = []

    public init(kind: Kind, modifiers: [MockModifier] = []) {
        self.kind = kind
        self.modifiers = modifiers
    }

    public indirect enum Kind: Sendable, Equatable {
        case vstack(alignment: MockValue?, spacing: Double?, children: [MockNode])
        case hstack(alignment: MockValue?, spacing: Double?, children: [MockNode])
        case zstack(alignment: MockValue?, children: [MockNode])
        case scrollView(horizontal: Bool, children: [MockNode])
        case group(children: [MockNode])
        case list(children: [MockNode])
        case form(children: [MockNode])
        case section(header: String?, children: [MockNode])
        case grid(children: [MockNode])
        case gridRow(children: [MockNode])
        case text(String)
        case image(MockImageSource)
        case label(title: String, systemImage: String?)
        case button(title: String, children: [MockNode])
        case shape(MockShape)
        case color(MockValue)
        case spacer(minLength: Double?)
        case divider
        /// `editable` is true when the `text:` binding resolves to a `@State` literal, so the
        /// renderer can own real local state seeded from `initialText`.
        case textField(placeholder: String, initialText: String, editable: Bool)
        case secureField(placeholder: String, initialText: String, editable: Bool)
        case toggle(title: String, initialOn: Bool, editable: Bool)
        case picker(title: String, options: [String], selectedIndex: Int, style: MockPickerStyle)
        case slider(value: Double, lowerBound: Double, upperBound: Double)
        case stepper(title: String, value: Double)
        /// `value == nil` is the indeterminate spinner.
        case progressView(title: String?, value: Double?)
        case gauge(title: String?, value: Double)
        case menu(title: String, children: [MockNode])
        case datePicker(title: String)
        case colorPicker(title: String)
        case disclosureGroup(title: String, isExpanded: Bool, children: [MockNode])
        case contentUnavailable(title: String, systemImage: String, description: String?)
        /// `NavigationStack` / `NavigationView` / `NavigationSplitView` — the renderer draws a
        /// slim nav bar above the children.
        case navigationStack(children: [MockNode])
        /// `NavigationLink`. `destination` is inlined when the trailing view is known; `targetName`
        /// is the destination callee (`SettingsView`) used to jump to a named screen.
        case navigationLink(title: String, destination: MockNode?, targetName: String?)
        case tabView(tabs: [MockTab], selectedIndex: Int)
        case chart(kind: MockChartKind, count: Int)
        case forEach(count: Int, child: MockNode)
        /// An `if` / `else if` / `else`. `known` is set when the condition folded to a constant
        /// (`if true`, a resolved `@State` bool, a literal comparison); otherwise the renderer
        /// picks a branch from the viewer's `mockupBranchPreference`. `elseBranch` may itself be
        /// a `.conditional` for an `else if` chain.
        case conditional(then: MockNode?, elseBranch: MockNode?, known: Bool?)
        /// `GlassEffectContainer(spacing:) { }` — merges nearby glass shapes at render time.
        case glassEffectContainer(spacing: Double?, children: [MockNode])
        /// `editable` mirrors `.textField`'s live-state seeding.
        case textEditor(placeholder: String, initialText: String, editable: Bool)
        /// `WebView(url:)` — no networking (Mockup is offline-first); drawn as a browser-chrome
        /// placeholder card showing the URL.
        case webView(url: String)
        case labeledContent(title: String, value: String)
        case link(title: String, destination: String)
        /// Syntax outside the supported subset; rendered as a labeled placeholder box.
        case unsupported(label: String)
    }

    public static func leaf(_ kind: Kind) -> MockNode { MockNode(kind: kind) }
}

public nonisolated extension MockNode.Kind {
    var isShape: Bool {
        if case .shape = self { return true }
        return false
    }

    var isImage: Bool {
        if case .image = self { return true }
        return false
    }
}

public nonisolated extension MockModifier {
    /// `fill` / `stroke` / `strokeBorder` are applied to the shape directly in the renderer, so
    /// the generic modifier fold skips them for a shape node.
    var isShapeStyling: Bool {
        switch self {
        case .fill, .stroke, .strokeBorder: true
        default: false
        }
    }

    /// `.resizable()` is folded into the `Image` value itself (it isn't a real `ViewModifier`),
    /// so the generic modifier fold skips it the way `isShapeStyling` skips fill/stroke.
    /// `.symbolEffect` joins it here — its static "end state" is computed in `imageView(for:)`,
    /// not applied as a real (animating) `View` modifier.
    var isImageStyling: Bool {
        switch self {
        case .resizable, .symbolEffect: true
        default: false
        }
    }
}

public nonisolated extension MockNode {
    /// Total node count including self, for the "N elements" stat chip.
    var count: Int {
        1 + childNodes.reduce(0) { $0 + $1.count }
            + modifierNodes.reduce(0) { $0 + $1.count }
            + toolbarNodes.reduce(0) { $0 + $1.count }
    }

    var childNodes: [MockNode] {
        switch kind {
        case let .vstack(_, _, children),
             let .hstack(_, _, children),
             let .zstack(_, children),
             let .scrollView(_, children),
             let .group(children),
             let .list(children),
             let .form(children),
             let .section(_, children),
             let .grid(children),
             let .gridRow(children),
             let .button(_, children),
             let .menu(_, children),
             let .disclosureGroup(_, _, children),
             let .navigationStack(children),
             let .glassEffectContainer(_, children):
            return children
        case let .navigationLink(_, destination, _):
            return destination.map { [$0] } ?? []
        case let .forEach(_, child):
            return [child]
        case let .tabView(tabs, _):
            return tabs.map(\.content)
        case let .conditional(then, elseBranch, _):
            return [then, elseBranch].compactMap { $0 }
        default:
            return []
        }
    }

    private var modifierNodes: [MockNode] {
        modifiers.compactMap { modifier in
            switch modifier {
            case let .background(node): return node
            case let .overlay(node, _): return node
            case let .sheet(content, _, _, _): return content
            case let .tabViewBottomAccessory(node): return node
            case let .safeAreaBar(_, node): return node
            default: return nil
            }
        }
    }

    /// Content nodes carried by `.toolbar` items, so completeness checks (node counts,
    /// anti-drift `unsupported` scans) see inside them too.
    var toolbarNodes: [MockNode] {
        for modifier in modifiers {
            if case let .toolbar(items) = modifier {
                return items.compactMap(\.content)
            }
        }
        return []
    }
}
