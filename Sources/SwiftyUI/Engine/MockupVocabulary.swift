import Foundation

/// The whitelisted SwiftUI vocabulary the Mockup engine understands, lifted into queryable data
/// for autocomplete.
///
/// **This table mirrors the `switch` cases in `MockupLowering.lowerConstructor` /
/// `MockupLowering.modifier(named:call:)` and the token lists in `MockupTokens`** — with one
/// exception: `ignoredModifierNames` (below) is the *source* the lowering's `default` case reads,
/// so that list exists exactly once. Everything else here does not drive the lowering — it is a
/// parallel description of it. `MockupCompletionTests` parses every `skeleton` and resolves every
/// token to catch the drift that hurts (offering something the engine can't lower). The reverse —
/// the engine gaining a constructor this table doesn't list — can't be caught automatically: when
/// you add a `case` to `lowerConstructor`, add it here too.
nonisolated enum MockupVocabulary {

    /// What a named argument (or a leading-dot positional) expects, so completion can offer the
    /// right token list after `label:` or `.`.
    nonisolated enum ValueKind: Sendable, Hashable, CaseIterable {
        case horizontalAlignment
        case verticalAlignment
        case alignment
        case textAlignment
        case color
        case font
        case fontWeight
        case edges
        case unitPoint
        case pickerStyle
        case dimension
        case number
        case string
        case bool
        case symbol
        /// A name in the workspace's shared image library (`Image("logo")`). The token list is
        /// empty here — the library is per-workspace, not a static vocabulary — completion
        /// serves it from `MockupCompletionIndex.assetNames` instead.
        case asset
        case contentMode
        /// `clipShape` / `containerShape`'s shape tokens: `.circle`, `.capsule`, `.rect`,
        /// `.buttonBorder`, `.containerRelative`, `.concentric`.
        case shape
        /// `ScrollView`'s axis: `.vertical` / `.horizontal`.
        case axis
        // MARK: iOS 26
        /// `.regular` / `.clear` / `.identity`, with `tint(_:)` / `interactive()` members.
        case glassStyle
        case buttonStyle
        case tabViewStyle
        case tabBarMinimizeBehavior
        case toolbarPlacement
        case scrollEdgeStyle
        case presentationSizing
        case symbolRenderingMode
        case symbolColorRenderingMode
        case symbolVariableValueMode
        case symbolEffect
        case imageScale
        case listStyle
        case toggleStyle
        case labelStyle
        case progressViewStyle
        case controlSize
        case other
    }

    nonisolated struct Label: Sendable, Hashable {
        let name: String
        let valueKind: ValueKind
    }

    nonisolated struct Constructor: Sendable, Hashable {
        let name: String
        let summary: String
        /// The text inserted when this completion is accepted. Doubles as a test fixture:
        /// it must lower with no warnings and no `unsupported` placeholder.
        let skeleton: String
        let labels: [Label]
        /// Kind of the first positional argument, for a leading-dot completion inside `Name(.…)`.
        let primaryValueKind: ValueKind
        /// The OS version this was introduced in, surfaced in the completion popup's
        /// documentation. `nil` for everything predating this pass.
        let since: String?

        init(name: String, summary: String, skeleton: String, labels: [Label], primaryValueKind: ValueKind, since: String? = nil) {
            self.name = name
            self.summary = summary
            self.skeleton = skeleton
            self.labels = labels
            self.primaryValueKind = primaryValueKind
            self.since = since
        }
    }

    nonisolated struct Modifier: Sendable, Hashable {
        let name: String
        let summary: String
        let skeleton: String
        let labels: [Label]
        let primaryValueKind: ValueKind
        /// `true` for modifiers the renderer acts on; `false` for ones it parses and ignores
        /// (styles, gestures, lifecycle) — still valid to type, ranked below the applied ones.
        let isApplied: Bool
        let since: String?

        init(
            name: String,
            summary: String,
            skeleton: String,
            labels: [Label],
            primaryValueKind: ValueKind,
            isApplied: Bool,
            since: String? = nil
        ) {
            self.name = name
            self.summary = summary
            self.skeleton = skeleton
            self.labels = labels
            self.primaryValueKind = primaryValueKind
            self.isApplied = isApplied
            self.since = since
        }
    }

    /// One member of a `ValueKind`'s namespace type — `Glass.tint(_:)`, `Glass.interactive()` —
    /// offered after a leading-dot token that itself has members (`.glassEffect(.regular.`).
    nonisolated struct TokenMember: Sendable, Hashable {
        let name: String
        /// Inserted after the base token (`regular.tint(.blue)`).
        let skeleton: String
        let summary: String
    }

    // MARK: - Constructors (mirrors `MockupLowering.lowerConstructor`)

    static let constructors: [Constructor] = [
        Constructor(name: "VStack", summary: "Vertical stack", skeleton: "VStack {\n    \n}",
                    labels: [Label(name: "alignment", valueKind: .horizontalAlignment),
                             Label(name: "spacing", valueKind: .number)],
                    primaryValueKind: .other),
        Constructor(name: "LazyVStack", summary: "Lazily-built vertical stack", skeleton: "LazyVStack {\n    \n}",
                    labels: [Label(name: "alignment", valueKind: .horizontalAlignment),
                             Label(name: "spacing", valueKind: .number)],
                    primaryValueKind: .other),
        Constructor(name: "HStack", summary: "Horizontal stack", skeleton: "HStack {\n    \n}",
                    labels: [Label(name: "alignment", valueKind: .verticalAlignment),
                             Label(name: "spacing", valueKind: .number)],
                    primaryValueKind: .other),
        Constructor(name: "LazyHStack", summary: "Lazily-built horizontal stack", skeleton: "LazyHStack {\n    \n}",
                    labels: [Label(name: "alignment", valueKind: .verticalAlignment),
                             Label(name: "spacing", valueKind: .number)],
                    primaryValueKind: .other),
        Constructor(name: "ZStack", summary: "Depth-layered stack", skeleton: "ZStack {\n    \n}",
                    labels: [Label(name: "alignment", valueKind: .alignment)],
                    primaryValueKind: .other),
        Constructor(name: "ScrollView", summary: "Scrolling container", skeleton: "ScrollView {\n    \n}",
                    labels: [], primaryValueKind: .axis),
        Constructor(name: "Group", summary: "Transparent grouping", skeleton: "Group {\n    \n}",
                    labels: [], primaryValueKind: .other),
        Constructor(name: "List", summary: "Scrolling list of rows", skeleton: "List {\n    \n}",
                    labels: [], primaryValueKind: .other),
        Constructor(name: "Form", summary: "Grouped settings form", skeleton: "Form {\n    \n}",
                    labels: [], primaryValueKind: .other),
        Constructor(name: "Section", summary: "Titled section of a list or form",
                    skeleton: "Section(\"Section\") {\n    \n}", labels: [], primaryValueKind: .string),
        Constructor(name: "Grid", summary: "Two-dimensional aligned grid", skeleton: "Grid {\n    \n}",
                    labels: [], primaryValueKind: .other),
        Constructor(name: "GridRow", summary: "One row of a Grid", skeleton: "GridRow {\n    \n}",
                    labels: [], primaryValueKind: .other),
        Constructor(name: "Text", summary: "A run of text", skeleton: "Text(\"Text\")",
                    labels: [], primaryValueKind: .string),
        Constructor(name: "Image", summary: "An SF Symbol or a workspace image asset",
                    skeleton: "Image(systemName: \"star\")",
                    labels: [Label(name: "systemName", valueKind: .symbol)], primaryValueKind: .asset),
        Constructor(name: "Label", summary: "Title paired with an icon",
                    skeleton: "Label(\"Label\", systemImage: \"star\")",
                    labels: [Label(name: "systemImage", valueKind: .symbol),
                             Label(name: "title", valueKind: .string)],
                    primaryValueKind: .string),
        Constructor(name: "Button", summary: "Tappable button", skeleton: "Button(\"Button\") {}",
                    labels: [Label(name: "title", valueKind: .string)], primaryValueKind: .string),
        Constructor(name: "Spacer", summary: "Flexible empty space", skeleton: "Spacer()",
                    labels: [Label(name: "minLength", valueKind: .number)], primaryValueKind: .other),
        Constructor(name: "Divider", summary: "Hairline rule", skeleton: "Divider()",
                    labels: [], primaryValueKind: .other),
        Constructor(name: "Rectangle", summary: "Rectangle shape", skeleton: "Rectangle()",
                    labels: [], primaryValueKind: .other),
        Constructor(name: "RoundedRectangle", summary: "Rounded rectangle shape",
                    skeleton: "RoundedRectangle(cornerRadius: 12)",
                    labels: [Label(name: "cornerRadius", valueKind: .number)], primaryValueKind: .other),
        Constructor(name: "Circle", summary: "Circle shape", skeleton: "Circle()",
                    labels: [], primaryValueKind: .other),
        Constructor(name: "Capsule", summary: "Capsule shape", skeleton: "Capsule()",
                    labels: [], primaryValueKind: .other),
        Constructor(name: "Ellipse", summary: "Ellipse shape", skeleton: "Ellipse()",
                    labels: [], primaryValueKind: .other),
        Constructor(name: "Color", summary: "A solid colour", skeleton: "Color(\"blue\")",
                    labels: [], primaryValueKind: .string),
        Constructor(name: "TextField", summary: "Single-line text entry",
                    skeleton: "TextField(\"Placeholder\", text: .constant(\"\"))",
                    labels: [Label(name: "text", valueKind: .other)], primaryValueKind: .string),
        Constructor(name: "SecureField", summary: "Masked text entry",
                    skeleton: "SecureField(\"Password\", text: .constant(\"\"))",
                    labels: [Label(name: "text", valueKind: .other)], primaryValueKind: .string),
        Constructor(name: "Toggle", summary: "On/off switch",
                    skeleton: "Toggle(\"Toggle\", isOn: .constant(true))",
                    labels: [Label(name: "isOn", valueKind: .bool)], primaryValueKind: .string),
        Constructor(name: "Picker", summary: "Choice among options",
                    skeleton: "Picker(\"Picker\", selection: .constant(0)) {\n    Text(\"Option\")\n}",
                    labels: [Label(name: "selection", valueKind: .other)], primaryValueKind: .string),
        Constructor(name: "Slider", summary: "Continuous value in a range",
                    skeleton: "Slider(value: .constant(0.5), in: 0...1)",
                    labels: [Label(name: "value", valueKind: .other),
                             Label(name: "in", valueKind: .other)],
                    primaryValueKind: .other),
        Constructor(name: "Stepper", summary: "Increment / decrement control",
                    skeleton: "Stepper(\"Stepper\", value: .constant(0))",
                    labels: [Label(name: "value", valueKind: .other)], primaryValueKind: .string),
        Constructor(name: "ProgressView", summary: "Progress bar or spinner",
                    skeleton: "ProgressView(\"Loading\", value: 0.5)",
                    labels: [Label(name: "value", valueKind: .number)], primaryValueKind: .string),
        Constructor(name: "Gauge", summary: "Value shown on a gauge",
                    skeleton: "Gauge(\"Gauge\", value: 0.5)",
                    labels: [Label(name: "value", valueKind: .number)], primaryValueKind: .string),
        Constructor(name: "Menu", summary: "Pull-down menu", skeleton: "Menu(\"Menu\") {\n    \n}",
                    labels: [Label(name: "title", valueKind: .string)], primaryValueKind: .string),
        Constructor(name: "DatePicker", summary: "Date field",
                    skeleton: "DatePicker(\"Date\", selection: .constant(.now))",
                    labels: [Label(name: "selection", valueKind: .other)], primaryValueKind: .string),
        Constructor(name: "ColorPicker", summary: "Colour well",
                    skeleton: "ColorPicker(\"Colour\", selection: .constant(.blue))",
                    labels: [Label(name: "selection", valueKind: .other)], primaryValueKind: .string),
        Constructor(name: "DisclosureGroup", summary: "Expandable section",
                    skeleton: "DisclosureGroup(\"Details\") {\n    \n}",
                    labels: [Label(name: "isExpanded", valueKind: .bool)], primaryValueKind: .string),
        Constructor(name: "ContentUnavailableView", summary: "Empty-state placeholder",
                    skeleton: "ContentUnavailableView(\"Nothing here\", systemImage: \"tray\")",
                    labels: [Label(name: "systemImage", valueKind: .symbol),
                             Label(name: "description", valueKind: .other)],
                    primaryValueKind: .string),
        Constructor(name: "NavigationStack", summary: "Navigation container",
                    skeleton: "NavigationStack {\n    \n}", labels: [], primaryValueKind: .other),
        Constructor(name: "NavigationLink", summary: "Push a destination or named screen",
                    skeleton: "NavigationLink(\"Detail\") {\n    Text(\"Detail\")\n}",
                    labels: [Label(name: "destination", valueKind: .other),
                             Label(name: "label", valueKind: .other)],
                    primaryValueKind: .string),
        Constructor(name: "NavigationView", summary: "Legacy navigation container",
                    skeleton: "NavigationView {\n    \n}", labels: [], primaryValueKind: .other),
        Constructor(name: "NavigationSplitView", summary: "Multi-column navigation container",
                    skeleton: "NavigationSplitView {\n    \n}", labels: [], primaryValueKind: .other),
        Constructor(name: "TabView", summary: "Tabbed container", skeleton: "TabView {\n    \n}",
                    labels: [Label(name: "selection", valueKind: .other)], primaryValueKind: .other),
        Constructor(name: "Chart", summary: "A Swift Charts sketch", skeleton: "Chart {\n    \n}",
                    labels: [], primaryValueKind: .other),
        Constructor(name: "ForEach", summary: "Repeat a view over a range",
                    skeleton: "ForEach(0..<3) {\n    Text(\"Item\")\n}", labels: [], primaryValueKind: .other),
        Constructor(name: "EmptyView", summary: "Renders nothing", skeleton: "EmptyView()",
                    labels: [], primaryValueKind: .other),
        Constructor(name: "LinearGradient", summary: "Straight-line colour gradient",
                    skeleton: "LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom)",
                    labels: [Label(name: "colors", valueKind: .other),
                             Label(name: "startPoint", valueKind: .unitPoint),
                             Label(name: "endPoint", valueKind: .unitPoint)],
                    primaryValueKind: .other),
        Constructor(name: "RadialGradient", summary: "Circular colour gradient",
                    skeleton: "RadialGradient(colors: [.blue, .purple], center: .center, startRadius: 0, endRadius: 160)",
                    labels: [Label(name: "colors", valueKind: .other), Label(name: "center", valueKind: .unitPoint)],
                    primaryValueKind: .other),
        Constructor(name: "AngularGradient", summary: "Sweep colour gradient",
                    skeleton: "AngularGradient(colors: [.blue, .purple], center: .center)",
                    labels: [Label(name: "colors", valueKind: .other), Label(name: "center", valueKind: .unitPoint)],
                    primaryValueKind: .other),
        Constructor(name: "TextEditor", summary: "Multi-line text entry",
                    skeleton: "TextEditor(text: .constant(\"\"))", labels: [Label(name: "text", valueKind: .other)],
                    primaryValueKind: .other),
        Constructor(name: "LabeledContent", summary: "A title paired with a trailing value",
                    skeleton: "LabeledContent(\"Title\", value: \"Value\")",
                    labels: [Label(name: "value", valueKind: .string)], primaryValueKind: .string, since: "iOS 16"),
        Constructor(name: "Link", summary: "A tappable URL", skeleton: "Link(\"Title\", destination: URL(string: \"https://example.com\")!)",
                    labels: [Label(name: "destination", valueKind: .other)], primaryValueKind: .string),
        Constructor(name: "WebView", summary: "Offline placeholder for an embedded web page",
                    skeleton: "WebView(url: \"https://example.com\")", labels: [Label(name: "url", valueKind: .string)],
                    primaryValueKind: .string),
        Constructor(name: "Tab", summary: "One tab of a TabView",
                    skeleton: "Tab(\"Home\", systemImage: \"house\") {\n    \n}",
                    labels: [Label(name: "systemImage", valueKind: .symbol), Label(name: "role", valueKind: .other)],
                    primaryValueKind: .string, since: "iOS 18"),
        Constructor(name: "TabSection", summary: "Groups tabs under a header in a TabView",
                    skeleton: "TabSection(\"Section\") {\n    \n}", labels: [], primaryValueKind: .string, since: "iOS 18"),
        // MARK: iOS 26
        Constructor(name: "GlassEffectContainer", summary: "Merges nearby Liquid Glass shapes",
                    skeleton: "GlassEffectContainer {\n    \n}", labels: [Label(name: "spacing", valueKind: .number)],
                    primaryValueKind: .other, since: "iOS 26"),
        Constructor(name: "ConcentricRectangle", summary: "Rounded rectangle matching its container's corner curve",
                    skeleton: "ConcentricRectangle()", labels: [], primaryValueKind: .other, since: "iOS 26"),
        Constructor(name: "UnevenRoundedRectangle", summary: "Rectangle with independently-rounded corners",
                    skeleton: "UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 12)",
                    labels: [Label(name: "topLeadingRadius", valueKind: .number), Label(name: "bottomLeadingRadius", valueKind: .number),
                             Label(name: "bottomTrailingRadius", valueKind: .number), Label(name: "topTrailingRadius", valueKind: .number)],
                    primaryValueKind: .other),
        Constructor(name: "ToolbarItem", summary: "One item in a .toolbar { } closure",
                    skeleton: "ToolbarItem(placement: .topBarTrailing) {\n    \n}",
                    labels: [Label(name: "placement", valueKind: .toolbarPlacement)], primaryValueKind: .other),
        Constructor(name: "ToolbarItemGroup", summary: "A group of toolbar items sharing a placement",
                    skeleton: "ToolbarItemGroup(placement: .topBarTrailing) {\n    \n}",
                    labels: [Label(name: "placement", valueKind: .toolbarPlacement)], primaryValueKind: .other),
        Constructor(name: "ToolbarSpacer", summary: "Splits a toolbar's shared glass background",
                    skeleton: "ToolbarSpacer(.fixed, placement: .topBarTrailing)",
                    labels: [Label(name: "placement", valueKind: .toolbarPlacement)], primaryValueKind: .other, since: "iOS 26"),
    ]

    // MARK: - Modifiers (mirrors `MockupLowering.modifier(named:call:)`)

    static let modifiers: [Modifier] = appliedModifiers + ignoredModifiers

    private static let appliedModifiers: [Modifier] = [
        Modifier(name: "padding", summary: "Inset the view", skeleton: "padding(16)",
                 labels: [], primaryValueKind: .edges, isApplied: true),
        Modifier(name: "frame", summary: "Pin or bound the view's size", skeleton: "frame(width: 200)",
                 labels: [Label(name: "width", valueKind: .number), Label(name: "height", valueKind: .number),
                          Label(name: "minWidth", valueKind: .number), Label(name: "minHeight", valueKind: .number),
                          Label(name: "idealWidth", valueKind: .number), Label(name: "idealHeight", valueKind: .number),
                          Label(name: "maxWidth", valueKind: .dimension), Label(name: "maxHeight", valueKind: .dimension),
                          Label(name: "alignment", valueKind: .alignment)],
                 primaryValueKind: .other, isApplied: true),
        Modifier(name: "foregroundStyle", summary: "Set the foreground colour or style",
                 skeleton: "foregroundStyle(.blue)", labels: [], primaryValueKind: .color, isApplied: true),
        Modifier(name: "foregroundColor", summary: "Set the foreground colour",
                 skeleton: "foregroundColor(.blue)", labels: [], primaryValueKind: .color, isApplied: true),
        Modifier(name: "font", summary: "Set the text font", skeleton: "font(.body)",
                 labels: [], primaryValueKind: .font, isApplied: true),
        Modifier(name: "fontWeight", summary: "Set the text weight", skeleton: "fontWeight(.bold)",
                 labels: [], primaryValueKind: .fontWeight, isApplied: true),
        Modifier(name: "bold", summary: "Bold the text", skeleton: "bold()",
                 labels: [], primaryValueKind: .other, isApplied: true),
        Modifier(name: "italic", summary: "Italicise the text", skeleton: "italic()",
                 labels: [], primaryValueKind: .other, isApplied: true),
        Modifier(name: "fill", summary: "Fill a shape", skeleton: "fill(.blue)",
                 labels: [], primaryValueKind: .color, isApplied: true),
        Modifier(name: "stroke", summary: "Stroke a shape's path",
                 skeleton: "stroke(.blue, lineWidth: 2)",
                 labels: [Label(name: "lineWidth", valueKind: .number)],
                 primaryValueKind: .color, isApplied: true),
        Modifier(name: "strokeBorder", summary: "Stroke a shape's inner border",
                 skeleton: "strokeBorder(.blue, lineWidth: 2)",
                 labels: [Label(name: "lineWidth", valueKind: .number)],
                 primaryValueKind: .color, isApplied: true),
        Modifier(name: "background", summary: "Place a view or colour behind",
                 skeleton: "background(.gray)", labels: [], primaryValueKind: .color, isApplied: true),
        Modifier(name: "overlay", summary: "Place a view or colour in front",
                 skeleton: "overlay(.gray)",
                 labels: [Label(name: "alignment", valueKind: .alignment)],
                 primaryValueKind: .color, isApplied: true),
        Modifier(name: "cornerRadius", summary: "Round the corners", skeleton: "cornerRadius(12)",
                 labels: [], primaryValueKind: .number, isApplied: true),
        Modifier(name: "clipShape", summary: "Clip to a shape", skeleton: "clipShape(.circle)",
                 labels: [], primaryValueKind: .shape, isApplied: true),
        Modifier(name: "opacity", summary: "Fade the view", skeleton: "opacity(0.8)",
                 labels: [], primaryValueKind: .number, isApplied: true),
        Modifier(name: "shadow", summary: "Drop a shadow", skeleton: "shadow(radius: 4)",
                 labels: [Label(name: "radius", valueKind: .number), Label(name: "color", valueKind: .color),
                          Label(name: "x", valueKind: .number), Label(name: "y", valueKind: .number)],
                 primaryValueKind: .other, isApplied: true),
        Modifier(name: "border", summary: "Draw a border", skeleton: "border(.gray, width: 1)",
                 labels: [Label(name: "width", valueKind: .number)],
                 primaryValueKind: .color, isApplied: true),
        Modifier(name: "multilineTextAlignment", summary: "Align wrapped text",
                 skeleton: "multilineTextAlignment(.center)", labels: [],
                 primaryValueKind: .textAlignment, isApplied: true),
        Modifier(name: "lineLimit", summary: "Cap the number of lines", skeleton: "lineLimit(2)",
                 labels: [], primaryValueKind: .number, isApplied: true),
        Modifier(name: "tint", summary: "Tint controls", skeleton: "tint(.blue)",
                 labels: [], primaryValueKind: .color, isApplied: true),
        Modifier(name: "navigationTitle", summary: "Large title above the view",
                 skeleton: "navigationTitle(\"Title\")", labels: [],
                 primaryValueKind: .string, isApplied: true),
        Modifier(name: "pickerStyle", summary: "Choose the picker presentation",
                 skeleton: "pickerStyle(.segmented)", labels: [],
                 primaryValueKind: .pickerStyle, isApplied: true),
        Modifier(name: "searchable", summary: "Search field above the view",
                 skeleton: "searchable(text: .constant(\"\"))",
                 labels: [Label(name: "text", valueKind: .other), Label(name: "prompt", valueKind: .string)],
                 primaryValueKind: .other, isApplied: true),
        Modifier(name: "sheet", summary: "Present a sheet on tap",
                 skeleton: "sheet(isPresented: .constant(false)) {\n    Text(\"Sheet\")\n}",
                 labels: [Label(name: "isPresented", valueKind: .bool)],
                 primaryValueKind: .other, isApplied: true),
        Modifier(name: "fullScreenCover", summary: "Present a full-screen cover on tap",
                 skeleton: "fullScreenCover(isPresented: .constant(false)) {\n    Text(\"Cover\")\n}",
                 labels: [Label(name: "isPresented", valueKind: .bool)],
                 primaryValueKind: .other, isApplied: true),
        Modifier(name: "popover", summary: "Present a popover on tap",
                 skeleton: "popover(isPresented: .constant(false)) {\n    Text(\"Popover\")\n}",
                 labels: [Label(name: "isPresented", valueKind: .bool)],
                 primaryValueKind: .other, isApplied: true),
        Modifier(name: "alert", summary: "Show an alert",
                 skeleton: "alert(\"Title\", isPresented: .constant(false)) {\n    Button(\"OK\") {}\n}",
                 labels: [Label(name: "isPresented", valueKind: .bool)], primaryValueKind: .string, isApplied: true),
        Modifier(name: "confirmationDialog", summary: "Show a confirmation dialog",
                 skeleton: "confirmationDialog(\"Are you sure?\", isPresented: .constant(false)) {\n    Button(\"Confirm\") {}\n}",
                 labels: [Label(name: "isPresented", valueKind: .bool)], primaryValueKind: .string, isApplied: true),
        Modifier(name: "badge", summary: "A small count or label in the corner", skeleton: "badge(\"3\")",
                 labels: [], primaryValueKind: .string, isApplied: true),
        Modifier(name: "listStyle", summary: "Choose the list's presentation", skeleton: "listStyle(.plain)",
                 labels: [], primaryValueKind: .listStyle, isApplied: true),
        Modifier(name: "toggleStyle", summary: "Choose the toggle's presentation", skeleton: "toggleStyle(.switch)",
                 labels: [], primaryValueKind: .toggleStyle, isApplied: true),
        Modifier(name: "labelStyle", summary: "Choose how a Label shows its title and icon",
                 skeleton: "labelStyle(.iconOnly)", labels: [], primaryValueKind: .labelStyle, isApplied: true),
        Modifier(name: "progressViewStyle", summary: "Choose the progress indicator's presentation",
                 skeleton: "progressViewStyle(.linear)", labels: [], primaryValueKind: .progressViewStyle, isApplied: true),
        Modifier(name: "controlSize", summary: "Scale a control up or down", skeleton: "controlSize(.small)",
                 labels: [], primaryValueKind: .controlSize, isApplied: true),
        Modifier(name: "symbolRenderingMode", summary: "Choose how an SF Symbol's layers render",
                 skeleton: "symbolRenderingMode(.hierarchical)", labels: [], primaryValueKind: .symbolRenderingMode, isApplied: true),
        Modifier(name: "imageScale", summary: "Scale an inline image relative to text",
                 skeleton: "imageScale(.large)", labels: [], primaryValueKind: .imageScale, isApplied: true),
        Modifier(name: "symbolEffect", summary: "Sketch an SF Symbol effect's resting state",
                 skeleton: "symbolEffect(.bounce)", labels: [], primaryValueKind: .symbolEffect, isApplied: true),
        Modifier(name: "containerShape", summary: "Clip a container to a shape",
                 skeleton: "containerShape(.circle)", labels: [], primaryValueKind: .shape, isApplied: true),
        // MARK: iOS 26
        Modifier(name: "glassEffect", summary: "A Liquid Glass material behind the view",
                 skeleton: "glassEffect(.regular)", labels: [Label(name: "in", valueKind: .shape)],
                 primaryValueKind: .glassStyle, isApplied: true, since: "iOS 26"),
        Modifier(name: "buttonStyle", summary: "Choose the button's presentation, including Liquid Glass",
                 skeleton: "buttonStyle(.glass)", labels: [], primaryValueKind: .buttonStyle, isApplied: true, since: "iOS 26"),
        Modifier(name: "tabViewStyle", summary: "Choose the TabView's presentation",
                 skeleton: "tabViewStyle(.sidebarAdaptable)", labels: [], primaryValueKind: .tabViewStyle, isApplied: true),
        Modifier(name: "tabBarMinimizeBehavior", summary: "Shrink the tab bar as the user scrolls",
                 skeleton: "tabBarMinimizeBehavior(.onScrollDown)", labels: [], primaryValueKind: .tabBarMinimizeBehavior,
                 isApplied: true, since: "iOS 26"),
        Modifier(name: "tabViewBottomAccessory", summary: "A bar above the tab bar (Now Playing-style)",
                 skeleton: "tabViewBottomAccessory {\n    Text(\"Accessory\")\n}", labels: [],
                 primaryValueKind: .other, isApplied: true, since: "iOS 26"),
        Modifier(name: "toolbar", summary: "Add items to the navigation bar",
                 skeleton: "toolbar {\n    ToolbarItem(placement: .topBarTrailing) {\n        Button(\"Add\") {}\n    }\n}",
                 labels: [], primaryValueKind: .other, isApplied: true),
        Modifier(name: "backgroundExtensionEffect", summary: "Extend a background image behind the safe area",
                 skeleton: "backgroundExtensionEffect()", labels: [], primaryValueKind: .other, isApplied: true, since: "iOS 26"),
        Modifier(name: "scrollEdgeEffectStyle", summary: "Choose the soft/hard fade where content meets a scroll edge",
                 skeleton: "scrollEdgeEffectStyle(.soft, for: .top)",
                 labels: [Label(name: "for", valueKind: .edges)], primaryValueKind: .scrollEdgeStyle,
                 isApplied: true, since: "iOS 26"),
        Modifier(name: "safeAreaBar", summary: "A glass bar pinned outside the safe area",
                 skeleton: "safeAreaBar(edge: .bottom) {\n    Text(\"Bar\")\n}",
                 labels: [Label(name: "edge", valueKind: .edges)], primaryValueKind: .other, isApplied: true, since: "iOS 26"),
        Modifier(name: "safeAreaInset", summary: "A bar pinned outside the safe area",
                 skeleton: "safeAreaInset(edge: .bottom) {\n    Text(\"Bar\")\n}",
                 labels: [Label(name: "edge", valueKind: .edges)], primaryValueKind: .other, isApplied: true),
        Modifier(name: "presentationSizing", summary: "Choose a presented sheet's size",
                 skeleton: "presentationSizing(.form)", labels: [], primaryValueKind: .presentationSizing,
                 isApplied: true, since: "iOS 18"),
        Modifier(name: "presentationDetents", summary: "Choose the heights a sheet may rest at",
                 skeleton: "presentationDetents([.medium, .large])", labels: [], primaryValueKind: .other, isApplied: true),
        Modifier(name: "symbolColorRenderingMode", summary: "Flat or gradient colour across an SF Symbol's layers",
                 skeleton: "symbolColorRenderingMode(.gradient)", labels: [], primaryValueKind: .symbolColorRenderingMode,
                 isApplied: true, since: "iOS 26"),
        Modifier(name: "symbolVariableValueMode", summary: "Show a variable SF Symbol's value as colour or fill",
                 skeleton: "symbolVariableValueMode(.color)", labels: [], primaryValueKind: .symbolVariableValueMode,
                 isApplied: true, since: "iOS 26"),
        Modifier(name: "onClickShow", summary: "Show a named view on tap",
                 skeleton: "onClickShow(\"Detail\")", labels: [],
                 primaryValueKind: .string, isApplied: true),
        Modifier(name: "resizable", summary: "Let an image be resized by its frame",
                 skeleton: "resizable()", labels: [], primaryValueKind: .other, isApplied: true),
        Modifier(name: "scaledToFit", summary: "Scale an image to fit its frame, preserving aspect ratio",
                 skeleton: "scaledToFit()", labels: [], primaryValueKind: .other, isApplied: true),
        Modifier(name: "scaledToFill", summary: "Scale an image to fill its frame, preserving aspect ratio",
                 skeleton: "scaledToFill()", labels: [], primaryValueKind: .other, isApplied: true),
        Modifier(name: "aspectRatio", summary: "Constrain the aspect ratio",
                 skeleton: "aspectRatio(contentMode: .fit)",
                 labels: [Label(name: "contentMode", valueKind: .contentMode)],
                 primaryValueKind: .number, isApplied: true),
        Modifier(name: "clipped", summary: "Clip content to the view's bounds",
                 skeleton: "clipped()", labels: [], primaryValueKind: .other, isApplied: true),
    ]

    /// Recognised by the lowering but with no bearing on a static mock. Kept in completion so the
    /// user knows they won't trip a diagnostic. Skeletons only need to parse — the lowering never
    /// warns on these regardless of arguments.
    ///
    /// This is the one table in this file that *drives* the lowering rather than mirroring it:
    /// `MockupLowering.modifier(named:call:)`'s `default` case checks `ignoredModifierNames`
    /// directly, so the ~90 names below exist exactly once instead of as two hand-kept copies.
    private static let ignoredModifierNamesList: [String] = [
        "id", "tag", "tabItem", "help", "accessibilityLabel", "accessibilityHint", "accessibilityValue",
        "onTapGesture", "onLongPressGesture", "onAppear", "onDisappear", "task", "onChange",
        "textFieldStyle", "menuStyle", "gaugeStyle", "datePickerStyle",
        "keyboardShortcut", "focused", "focusable", "animation", "transition", "contentShape",
        "gesture", "simultaneousGesture", "highPriorityGesture", "environment", "environmentObject",
        "preference", "navigationBarTitleDisplayMode", "navigationSubtitle",
        "disabled", "allowsHitTesting", "zIndex", "layoutPriority", "fixedSize",
        "drawingGroup", "compositingGroup", "redacted",
        "textSelection", "textCase", "minimumScaleFactor", "truncationMode", "kerning",
        "tracking", "baselineOffset", "monospacedDigit", "monospaced", "underline", "strikethrough",
        // MARK: iOS 26 and other recent additions — recognised, but nothing a static sketch
        // needs to draw differently (scroll-position tracking, gestures, styling knobs the
        // renderer doesn't model, lifecycle hooks).
        "onScrollGeometryChange", "onScrollPhaseChange", "onScrollVisibilityChange", "scrollPosition",
        "scrollTargetBehavior", "scrollTargetLayout", "scrollBounceBehavior", "scrollIndicators",
        "scrollDisabled", "contentMargins", "defaultScrollAnchor", "containerRelativeFrame",
        "matchedTransitionSource", "navigationTransition", "matchedGeometryEffect",
        "writingToolsBehavior", "textRenderer", "textEditorStyle", "pointerStyle", "hoverEffect",
        "contextMenu", "refreshable", "swipeActions", "menuIndicator", "menuOrder", "backgroundStyle",
        "scenePadding", "windowResizeAnchor", "interactiveDismissDisabled", "listSectionMargins",
        "listSectionSpacing", "listRowInsets", "listRowSpacing", "listRowSeparator", "listRowBackground",
        "labelIconToTitleSpacing", "formStyle", "defaultFocus", "focusEffectDisabled", "sensoryFeedback",
        "symbolVariant", "accessibilityLabeledPair", "containerBackground", "safeAreaPadding",
        "geometryGroup", "onGeometryChange", "allowsTightening", "dynamicTypeSize",
        "speechAdjustedPitch", "privacySensitive", "contentTransition", "transaction",
        "defaultAppStorage", "toolbarBackground", "toolbarColorScheme", "toolbarTitleDisplayMode",
        "toolbarVisibility", "tabViewSidebarHeader", "tabViewSidebarBottomBar", "glassEffectID",
        "glassEffectUnion", "glassEffectTransition", "scrollEdgeEffectHidden", "searchToolbarBehavior",
        "sharedBackgroundVisibility",
    ]

    /// Exposed so `MockupLowering.modifier(named:call:)` can check it directly — see the doc
    /// comment above.
    static let ignoredModifierNames: Set<String> = Set(ignoredModifierNamesList)

    private static let closureModifierNames: Set<String> = [
        "onTapGesture", "onLongPressGesture", "onAppear", "onDisappear", "task",
        "tabViewSidebarHeader", "tabViewSidebarBottomBar",
    ]

    private static let ignoredModifiers: [Modifier] = ignoredModifierNamesList.map { name in
        let skeleton: String
        if name == "onChange" {
            skeleton = "onChange(of: value) { }"
        } else if name == "scrollPosition" {
            skeleton = "scrollPosition(id: .constant(nil))"
        } else if closureModifierNames.contains(name) {
            skeleton = "\(name) { }"
        } else {
            skeleton = "\(name)()"
        }
        return Modifier(name: name, summary: "Recognised; no effect on the mockup",
                        skeleton: skeleton, labels: [], primaryValueKind: .other, isApplied: false)
    }

    // MARK: - Lookups

    private static let constructorsByName: [String: Constructor] =
        Dictionary(uniqueKeysWithValues: constructors.map { ($0.name, $0) })

    private static let modifiersByName: [String: Modifier] =
        Dictionary(uniqueKeysWithValues: modifiers.map { ($0.name, $0) })

    static func constructor(named name: String) -> Constructor? { constructorsByName[name] }

    static func modifier(named name: String) -> Modifier? { modifiersByName[name] }

    // MARK: - Token vocabularies (mirrors `MockupTokens`)

    static func tokens(for kind: ValueKind) -> [String] {
        switch kind {
        case .horizontalAlignment:
            return ["leading", "center", "trailing"]
        case .verticalAlignment:
            return ["top", "center", "bottom", "firstTextBaseline", "lastTextBaseline"]
        case .alignment:
            return ["topLeading", "top", "topTrailing", "leading", "center", "trailing",
                    "bottomLeading", "bottom", "bottomTrailing"]
        case .textAlignment:
            return ["leading", "center", "trailing"]
        case .color:
            return ["red", "orange", "yellow", "green", "mint", "teal", "cyan", "blue", "indigo",
                    "purple", "pink", "brown", "black", "white", "gray", "grey", "clear", "primary",
                    "secondary", "tertiary", "quaternary", "accentColor", "accent", "tint"]
        case .font:
            return ["largeTitle", "title", "title2", "title3", "headline", "subheadline", "body",
                    "callout", "footnote", "caption", "caption2"]
        case .fontWeight:
            return ["ultraLight", "thin", "light", "regular", "medium", "semibold", "bold",
                    "heavy", "black"]
        case .edges:
            return ["all", "horizontal", "vertical", "top", "bottom", "leading", "trailing"]
        case .unitPoint:
            return ["top", "bottom", "leading", "trailing", "topLeading", "topTrailing",
                    "bottomLeading", "bottomTrailing", "center"]
        case .pickerStyle:
            return ["automatic", "segmented", "menu", "inline", "wheel", "palette"]
        case .dimension:
            return ["infinity"]
        case .symbol:
            return Self.sfSymbols
        case .contentMode:
            return ["fit", "fill"]
        case .shape:
            return ["circle", "capsule", "rect", "buttonBorder", "containerRelative", "concentric"]
        case .axis:
            return ["vertical", "horizontal"]
        case .glassStyle:
            return ["regular", "clear", "identity"]
        case .buttonStyle:
            return ["automatic", "plain", "bordered", "borderedProminent", "borderless", "glass", "glassProminent"]
        case .tabViewStyle:
            return ["automatic", "page", "sidebarAdaptable", "grouped"]
        case .tabBarMinimizeBehavior:
            return ["automatic", "onScrollDown", "onScrollUp", "never"]
        case .toolbarPlacement:
            return ["topBarLeading", "topBarTrailing", "principal", "bottomBar", "navigation",
                    "primaryAction", "confirmationAction", "cancellationAction"]
        case .scrollEdgeStyle:
            return ["automatic", "soft", "hard"]
        case .presentationSizing:
            return ["automatic", "form", "page", "fitted"]
        case .symbolRenderingMode:
            return ["monochrome", "hierarchical", "palette", "multicolor"]
        case .symbolColorRenderingMode:
            return ["flat", "gradient"]
        case .symbolVariableValueMode:
            return ["color", "draw"]
        case .symbolEffect:
            return ["appear", "disappear", "bounce", "pulse", "variableColor", "wiggle", "breathe",
                    "rotate", "replace", "drawOn", "drawOff"]
        case .imageScale:
            return ["small", "medium", "large"]
        case .listStyle:
            return ["automatic", "plain", "inset", "grouped", "insetGrouped", "sidebar"]
        case .toggleStyle:
            return ["automatic", "switch", "button", "checkbox"]
        case .labelStyle:
            return ["automatic", "iconOnly", "titleOnly", "titleAndIcon"]
        case .progressViewStyle:
            return ["automatic", "linear", "circular"]
        case .controlSize:
            return ["mini", "small", "regular", "large", "extraLarge"]
        case .number, .string, .bool, .other, .asset:
            return []
        }
    }

    // MARK: - Token members (mirrors the chained-member helpers in `MockupLowering`)

    /// Members offered after a leading-dot token whose type has its own chainable API
    /// (`.glassEffect(.regular.` → `tint(_:)`, `interactive()`).
    static func members(of kind: ValueKind) -> [TokenMember] {
        switch kind {
        case .glassStyle:
            return [
                TokenMember(name: "tint", skeleton: "tint(.blue)", summary: "Tint the glass"),
                TokenMember(name: "interactive", skeleton: "interactive()", summary: "React to touch/hover"),
            ]
        default:
            return []
        }
    }

    /// Bare type names whose members double as tokens — `Color.red`, `Glass.regular.tint(_:)` —
    /// so a token site reached through `Type.` (not just a leading dot) still resolves.
    static let typeNamespaces: [String: ValueKind] = [
        "Color": .color,
        "Font": .font,
        "Glass": .glassStyle,
    ]

    /// Font factories the lowering accepts in addition to named styles (`largeTitle`, …).
    /// Kept out of `tokens(for: .font)` so `namedFont` anti-drift stays a 1:1 check.
    nonisolated struct FontFactory: Sendable, Hashable {
        let name: String
        /// Inserted after an existing leading dot, or with a leading dot when there isn't one.
        let skeleton: String
    }

    static let fontFactories: [FontFactory] = [
        FontFactory(name: "system", skeleton: "system(size: 17)"),
    ]

    /// Common mockup SF Symbols — not the full catalog. Offered inside `systemName:` /
    /// `systemImage:` strings and after those labels.
    static let sfSymbols: [String] = [
        "star", "star.fill", "heart", "heart.fill", "house", "house.fill",
        "person", "person.fill", "person.crop.circle", "person.crop.circle.fill",
        "gear", "gearshape", "gearshape.fill", "magnifyingglass",
        "plus", "minus", "xmark", "checkmark",
        "chevron.left", "chevron.right", "chevron.up", "chevron.down",
        "arrow.left", "arrow.right", "arrow.up", "arrow.down",
        "bell", "bell.fill", "envelope", "envelope.fill",
        "phone", "phone.fill", "camera", "camera.fill", "photo", "photo.fill",
        "trash", "trash.fill", "pencil", "square.and.pencil",
        "square.and.arrow.up", "square.and.arrow.down",
        "doc", "doc.fill", "folder", "folder.fill", "tray", "tray.fill",
        "bookmark", "bookmark.fill", "tag", "tag.fill",
        "cart", "cart.fill", "creditcard", "location", "location.fill",
        "map", "calendar", "clock", "clock.fill",
        "moon", "moon.fill", "sun.max", "sun.max.fill", "cloud",
        "wifi", "battery.100percent",
        "play.fill", "pause.fill", "backward.fill", "forward.fill",
        "speaker.wave.2.fill", "mic", "mic.fill",
        "paperplane", "paperplane.fill", "bubble.left", "bubble.left.fill",
        "ellipsis", "ellipsis.circle", "info.circle", "info.circle.fill",
        "questionmark.circle", "exclamationmark.triangle",
        "lock", "lock.fill", "lock.open", "eye", "eye.slash",
        "slider.horizontal.3", "list.bullet", "square.grid.2x2",
        "line.3.horizontal", "plus.circle.fill", "checkmark.circle.fill",
        "xmark.circle.fill", "sparkles", "paintbrush", "hammer",
        "iphone", "ipad", "laptopcomputer", "globe", "link",
    ]
}
