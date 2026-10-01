import SwiftUI

/// Renders a lowered `MockNode` tree with real SwiftUI. Recursive and `AnyView`-heavy — this
/// is a live preview of a hand-typed sketch, not a hot path, so clarity wins over view-identity
/// purity. Unsupported nodes render as a labeled placeholder rather than vanishing.
@MainActor
public struct MockNodeView: View {
    public let node: MockNode

    public init(node: MockNode) {
        self.node = node
    }

    @Environment(\.mockupBranchPreference) private var branchPreference
    @Environment(\.mockupChrome) private var chrome
    @Environment(\.mockupFlow) private var flow
    @Environment(\.mockupStageFrame) private var stageFrame
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.mockupAssets) private var assets

    public var body: some View {
        var result = AnyView(base)
        for modifier in node.modifiers {
            // fill/stroke on a shape are folded into the shape itself in `base`.
            if node.kind.isShape, modifier.isShapeStyling { continue }
            // `.resizable()` is an `Image` method, not a real `ViewModifier` — folded into the
            // image itself in `imageView(for:)`.
            if node.kind.isImage, modifier.isImageStyling { continue }
            result = AnyView(apply(modifier, to: result))
        }
        return result
    }

    // MARK: - Base kind

    @ViewBuilder
    private var base: some View {
        switch node.kind {
        case let .vstack(alignment, spacing, children):
            VStack(alignment: MockupTokens.horizontalAlignment(alignment), spacing: spacing.map { CGFloat($0) }) {
                childViews(children)
            }
        case let .hstack(alignment, spacing, children):
            HStack(alignment: MockupTokens.verticalAlignment(alignment), spacing: spacing.map { CGFloat($0) }) {
                childViews(children)
            }
        case let .zstack(alignment, children):
            ZStack(alignment: MockupTokens.alignment(alignment)) {
                childViews(children)
            }
        case let .scrollView(horizontal, children):
            ScrollView(horizontal ? .horizontal : .vertical) {
                if horizontal {
                    HStack { childViews(children) }
                } else {
                    VStack { childViews(children) }
                }
            }
        case let .group(children):
            Group { childViews(children) }
        case let .list(children):
            if chrome.usesIOSChrome {
                MockupIOSList(children: children)
            } else {
                List { childViews(children) }
            }
        case let .form(children):
            if chrome.usesIOSChrome {
                MockupIOSList(children: children)
            } else {
                Form { childViews(children) }
            }
        case let .section(header, children):
            if chrome.usesIOSChrome {
                MockupIOSSection(header: header, rows: children)
            } else if let header {
                Section {
                    childViews(children)
                } header: {
                    Text(header)
                }
            } else {
                Section { childViews(children) }
            }
        case let .grid(children):
            Grid { childViews(children) }
        case let .gridRow(children):
            GridRow { childViews(children) }
        case let .text(string):
            Text(string)
        case let .image(source):
            imageView(for: source)
        case let .label(title, systemImage):
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        case let .button(title, children):
            if chrome.usesIOSChrome {
                MockupIOSButton(action: {
                    if let name = onClickShowTarget {
                        activateOnClickShow(name)
                    }
                }) {
                    if children.isEmpty {
                        Text(title)
                    } else {
                        HStack { childViews(children) }
                    }
                }
            } else {
                Button {
                    if let name = onClickShowTarget {
                        activateOnClickShow(name)
                    }
                } label: {
                    if children.isEmpty {
                        Text(title)
                    } else {
                        HStack { childViews(children) }
                    }
                }
            }
        case let .shape(shape):
            styledShape(shape)
        case let .color(value):
            Rectangle().fill(MockupTokens.shapeStyle(value))
        case let .spacer(minLength):
            Spacer(minLength: minLength.map { CGFloat($0) })
        case .divider:
            Divider()
        case let .textField(placeholder, initialText, editable):
            if chrome.usesIOSChrome {
                MockupIOSTextField(placeholder: placeholder, initialText: initialText, editable: editable)
            } else if editable {
                MockTextField(placeholder: placeholder, initialText: initialText)
            } else {
                TextField(placeholder, text: .constant(initialText))
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)
            }
        case let .secureField(placeholder, initialText, editable):
            if chrome.usesIOSChrome {
                MockupIOSTextField(
                    placeholder: placeholder,
                    initialText: initialText,
                    isSecure: true,
                    editable: editable
                )
            } else if editable {
                MockSecureField(placeholder: placeholder, initialText: initialText)
            } else {
                SecureField(placeholder, text: .constant(initialText))
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)
            }
        case let .toggle(title, initialOn, editable):
            if chrome.usesIOSChrome {
                MockupIOSSwitch(title: title, initialOn: initialOn, editable: editable)
            } else if editable {
                MockToggle(title: title, initialOn: initialOn)
            } else {
                Toggle(title, isOn: .constant(initialOn))
                    .disabled(true)
            }
        case let .picker(title, options, selectedIndex, style):
            if chrome.usesIOSChrome {
                MockupIOSPicker(
                    title: title,
                    options: options,
                    selectedIndex: selectedIndex,
                    style: effectivePickerStyle(fallback: style)
                )
            } else {
                MockPicker(title: title, options: options, selectedIndex: selectedIndex, style: effectivePickerStyle(fallback: style))
            }
        case let .slider(value, lowerBound, upperBound):
            if chrome.usesIOSChrome {
                MockupIOSSlider(value: value, lowerBound: lowerBound, upperBound: upperBound)
            } else {
                MockSlider(value: value, lowerBound: lowerBound, upperBound: upperBound)
            }
        case let .stepper(title, value):
            if chrome.usesIOSChrome {
                MockupIOSStepper(title: title, value: value)
            } else {
                MockStepper(title: title, value: value)
            }
        case let .progressView(title, value):
            if chrome.usesIOSChrome {
                MockupIOSProgress(title: title, value: value.map { max(0, min($0, 1)) })
            } else if let value {
                ProgressView(value: max(0, min(value, 1))) {
                    if let title { Text(title) }
                }
            } else if let title {
                ProgressView { Text(title) }
            } else {
                ProgressView()
            }
        case let .gauge(title, value):
            Gauge(value: max(0, min(value, 1))) {
                Text(title ?? "")
            }
        case let .menu(title, children):
            Menu {
                childViews(children)
            } label: {
                Label(title.isEmpty ? "Menu" : title, systemImage: "chevron.up.chevron.down")
            }
        case let .datePicker(title):
            DatePicker(title, selection: .constant(Self.sampleDate))
                .datePickerStyle(.compact)
                .disabled(true)
        case let .colorPicker(title):
            ColorPicker(title, selection: .constant(.accentColor))
                .disabled(true)
        case let .disclosureGroup(title, isExpanded, children):
            MockDisclosureGroup(title: title, isExpanded: isExpanded) {
                childViews(children)
            }
        case let .contentUnavailable(title, systemImage, description):
            ContentUnavailableView {
                Label(title.isEmpty ? "Nothing here" : title, systemImage: systemImage)
            } description: {
                if let description { Text(description) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .navigationStack(children):
            MockNavigationStack { childViews(children) }
        case let .navigationLink(title, destination, targetName):
            MockNavigationLink(title: title, destination: destination, targetName: targetName)
        case let .tabView(tabs, selectedIndex):
            MockTabView(
                tabs: tabs,
                selectedIndex: selectedIndex,
                style: effectiveTabViewStyle,
                minimizeBehavior: effectiveTabBarMinimizeBehavior,
                bottomAccessory: tabViewBottomAccessoryNode
            )
        case let .chart(kind, count):
            MockChartView(kind: kind, count: count)
                .frame(minHeight: 120)
        case let .forEach(count, child):
            ForEach(Array(0..<max(0, count)), id: \.self) { _ in
                MockNodeView(node: child)
            }
        case let .conditional(thenNode, elseBranch, known):
            conditionalView(then: thenNode, elseBranch: elseBranch, known: known)
        case let .glassEffectContainer(spacing, children):
            GlassEffectContainer(spacing: spacing.map { CGFloat($0) }) {
                childViews(children)
            }
        case let .textEditor(_, initialText, editable):
            textEditorView(initialText: initialText, editable: editable)
        case let .webView(url):
            MockWebView(url: url)
        case let .labeledContent(title, value):
            LabeledContent(title, value: value)
        case let .link(title, destination):
            MockLink(title: title, destination: destination)
        case let .unsupported(label):
            UnsupportedNodeBadge(label: label)
        }
    }

    @ViewBuilder
    private func childViews(_ children: [MockNode]) -> some View {
        ForEach(Array(children.enumerated()), id: \.offset) { _, child in
            MockNodeView(node: child)
        }
    }

    @ViewBuilder
    private func conditionalView(then thenNode: MockNode?, elseBranch: MockNode?, known: Bool?) -> some View {
        let showElse = known.map { !$0 } ?? (branchPreference == .elseBranch)
        if showElse {
            if let elseBranch {
                MockNodeView(node: elseBranch)
            }
        } else if let thenNode {
            MockNodeView(node: thenNode)
        }
    }

    // MARK: - Shapes

    @ViewBuilder
    private func styledShape(_ shape: MockShape) -> some View {
        let anyShape = MockNodeView.anyShape(for: shape)
        if let fill = shapeStyling(.fill) {
            anyShape.fill(MockupTokens.shapeStyle(fill.color))
        } else if let stroke = shapeStyling(.stroke) ?? shapeStyling(.strokeBorder) {
            anyShape.stroke(MockupTokens.shapeStyle(stroke.color), lineWidth: CGFloat(stroke.width))
        } else {
            anyShape
        }
    }

    private enum ShapeStyleSlot { case fill, stroke, strokeBorder }

    private func shapeStyling(_ slot: ShapeStyleSlot) -> (color: MockValue, width: Double)? {
        for modifier in node.modifiers.reversed() {
            switch (slot, modifier) {
            case let (.fill, .fill(value)):
                return (value, 0)
            case let (.stroke, .stroke(color, width)):
                return (color, width)
            case let (.strokeBorder, .strokeBorder(color, width)):
                return (color, width)
            default:
                continue
            }
        }
        return nil
    }

    public static func anyShape(for shape: MockShape) -> AnyShape {
        MockupTokens.anyShape(shape)
    }

    // MARK: - Images

    /// `.resizable()` is an `Image` method, not a `ViewModifier`, so it can't flow through the
    /// generic `apply(_:to:)` fold — it's read off the chain here instead. Without it, an asset
    /// image is capped to its native pixel size (shrinking to fit when there isn't room) so an
    /// oversized import can't blow up the device layout; see `MockupAssetImport.maxPixelSize`
    /// for the import-time half of that cap.
    @ViewBuilder
    private func imageView(for source: MockImageSource) -> some View {
        let hasResizable = node.modifiers.contains { if case .resizable = $0 { true } else { false } }
        switch source {
        case let .system(name):
            if hasResizable {
                Image(systemName: name).resizable().symbolEffectEndState(effectiveSymbolEffect)
            } else {
                Image(systemName: name).symbolEffectEndState(effectiveSymbolEffect)
            }
        case let .asset(name):
            if let nsImage = assets?.image(named: name) {
                if hasResizable {
                    Image(nsImage: nsImage).resizable()
                } else {
                    let size = assets?.pixelSize(named: name)
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            maxWidth: (size?.width).flatMap { $0 > 0 ? $0 : nil },
                            maxHeight: (size?.height).flatMap { $0 > 0 ? $0 : nil }
                        )
                }
            } else {
                UnsupportedNodeBadge(label: "missing image \"\(name)\"")
            }
        }
    }

    /// `.symbolEffect(...)` folded like `.resizable` — the canvas is static, so this reads as the
    /// effect's end state rather than an animation. `nil` when no `.symbolEffect` is in the chain.
    private var effectiveSymbolEffect: MockSymbolEffect? {
        for modifier in node.modifiers.reversed() {
            if case let .symbolEffect(effect) = modifier { return effect }
        }
        return nil
    }

    // MARK: - Modifiers

    @ViewBuilder
    private func apply(_ modifier: MockModifier, to view: AnyView) -> some View {
        switch modifier {
        case let .padding(edges, length):
            if let length {
                view.padding(MockupTokens.edges(edges), CGFloat(length))
            } else {
                view.padding(MockupTokens.edges(edges))
            }
        case let .frame(frame):
            view
                .frame(width: frame.width.map { CGFloat($0) }, height: frame.height.map { CGFloat($0) })
                .frame(
                    minWidth: frame.minWidth.map { CGFloat($0) },
                    maxWidth: frame.maxWidth?.cgFloatValue,
                    minHeight: frame.minHeight.map { CGFloat($0) },
                    maxHeight: frame.maxHeight?.cgFloatValue,
                    alignment: MockupTokens.alignment(frame.alignment)
                )
        case let .foregroundStyle(value):
            view.foregroundStyle(MockupTokens.shapeStyle(value))
        case let .font(value):
            view.font(MockupTokens.font(value) ?? .body)
        case let .fontWeight(value):
            view.fontWeight(MockupTokens.fontWeight(value) ?? .regular)
        case .bold:
            view.fontWeight(.bold)
        case .italic:
            view.italic()
        case let .fill(value):
            view.foregroundStyle(MockupTokens.shapeStyle(value))
        case .stroke, .strokeBorder:
            view
        case .resizable:
            // Folded into the image itself in `imageView(for:)` when `node.kind.isImage`; a
            // no-op fallback here for the anti-drift test that applies every modifier skeleton
            // to a plain `Text`.
            view
        case let .aspectRatio(ratio, contentMode):
            view.aspectRatio(ratio.map { CGFloat($0) }, contentMode: contentMode == .fill ? .fill : .fit)
        case .clipped:
            view.clipped()
        case let .background(backgroundNode):
            view.background {
                MockNodeView(node: backgroundNode)
            }
        case let .overlay(overlayNode, alignment):
            view.overlay(alignment: MockupTokens.alignment(alignment)) {
                MockNodeView(node: overlayNode)
            }
        case let .cornerRadius(radius):
            view.clipShape(RoundedRectangle(cornerRadius: CGFloat(radius)))
        case let .clipShape(shape):
            view.clipShape(MockNodeView.anyShape(for: shape))
        case let .opacity(value):
            view.opacity(value)
        case let .shadow(color, radius, x, y):
            view.shadow(
                color: color.flatMap(MockupTokens.color) ?? .black.opacity(0.33),
                radius: CGFloat(radius),
                x: CGFloat(x),
                y: CGFloat(y)
            )
        case let .border(color, width):
            view.border(MockupTokens.shapeStyle(color), width: CGFloat(width))
        case let .multilineTextAlignment(value):
            view.multilineTextAlignment(MockupTokens.textAlignment(value))
        case let .lineLimit(limit):
            view.lineLimit(limit)
        case let .tint(value):
            view.tint(MockupTokens.color(value) ?? .accentColor)
        case let .navigationTitle(title):
            VStack(alignment: .leading, spacing: chrome.usesIOSChrome ? 4 : RenderSpacing.sm) {
                Text(title)
                    .font(
                        chrome.usesIOSChrome
                            ? .system(size: MockupIOSTokens.largeTitleSize, weight: .bold)
                            : .largeTitle.weight(.bold)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, chrome.usesIOSChrome ? MockupIOSTokens.listMargin : 0)
                view
            }
        case .pickerStyle:
            // Folded onto the `.picker` base by `effectivePickerStyle`; a no-op elsewhere.
            view
        case let .searchable(prompt):
            VStack(spacing: chrome.usesIOSChrome ? 8 : RenderSpacing.sm) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text(prompt ?? "Search")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, chrome.usesIOSChrome ? 10 : 8)
                .padding(.vertical, chrome.usesIOSChrome ? 0 : 6)
                .frame(height: chrome.usesIOSChrome ? MockupIOSTokens.searchHeight : nil)
                .background(
                    chrome.usesIOSChrome
                        ? MockupIOSTokens.systemGray6(colorScheme)
                        : Color.primary.opacity(0.08),
                    in: .rect(cornerRadius: chrome.usesIOSChrome ? MockupIOSTokens.fieldCornerRadius : 8)
                )
                view
            }
            .padding(.horizontal, chrome.usesIOSChrome ? chrome.listMargin : 0)
        case let .sheet(content, targetName, isCover, autoPresent):
            view.modifier(MockSheetHost(
                content: content,
                targetName: targetName,
                isCover: isCover,
                autoPresent: autoPresent
            ))
        case let .onClickShow(name):
            if case .button = node.kind {
                view
            } else {
                view.modifier(MockOnClickShow(name: name))
            }
        // MARK: iOS 26
        case let .glassEffect(glass, shape):
            if let shape {
                view.glassEffect(MockupTokens.glass(glass), in: MockNodeView.anyShape(for: shape))
            } else {
                view.glassEffect(MockupTokens.glass(glass))
            }
        case let .buttonStyle(style):
            switch style {
            case .automatic: view.buttonStyle(.automatic)
            case .plain: view.buttonStyle(.plain)
            case .bordered: view.buttonStyle(.bordered)
            case .borderedProminent: view.buttonStyle(.borderedProminent)
            case .borderless: view.buttonStyle(.borderless)
            case .glass: view.buttonStyle(.glass)
            case .glassProminent: view.buttonStyle(.glassProminent)
            }
        case .tabViewStyle, .tabBarMinimizeBehavior, .tabViewBottomAccessory:
            // Folded onto the `.tabView` node directly by `effectiveTabViewStyle` and friends,
            // the way `.pickerStyle` is folded onto `.picker`; a no-op fallback here.
            view
        case let .toolbar(items):
            MockToolbarChrome(items: items) { view }
        case .backgroundExtensionEffect:
            view.backgroundExtensionEffect()
        case let .scrollEdgeEffectStyle(style, edges):
            view.scrollEdgeEffectStyle(MockupTokens.scrollEdgeEffectStyle(style), for: MockupTokens.edges(edges))
        case let .safeAreaBar(edge, barNode):
            let edgeName: String? = if case let .token(name)? = edge { name } else { nil }
            switch edgeName {
            case "top":
                view.safeAreaBar(edge: .top) { MockNodeView(node: barNode) }
            case "leading":
                view.safeAreaBar(edge: .leading) { MockNodeView(node: barNode) }
            case "trailing":
                view.safeAreaBar(edge: .trailing) { MockNodeView(node: barNode) }
            default:
                view.safeAreaBar(edge: .bottom) { MockNodeView(node: barNode) }
            }
        case .presentationSizing:
            // Read directly off the presented node by `MockupPresentationOverlay`; a no-op here.
            view
        case let .containerShape(shape):
            // `containerShape(_:)` needs a `RoundedRectangularShape`, which `AnyShape` can't
            // satisfy — clipping to the same shape is the closest a static sketch needs.
            view.clipShape(MockNodeView.anyShape(for: shape))
        case let .symbolRenderingMode(mode):
            view.symbolRenderingMode(MockupTokens.symbolRenderingMode(mode))
        case let .symbolColorRenderingMode(mode):
            view.symbolColorRenderingMode(MockupTokens.symbolColorRenderingMode(mode))
        case let .symbolVariableValueMode(mode):
            view.symbolVariableValueMode(MockupTokens.symbolVariableValueMode(mode))
        case .symbolEffect:
            // Static end state computed in `imageView(for:)`; no generic `View` effect here.
            view
        case let .imageScale(scale):
            view.imageScale(MockupTokens.imageScale(scale))
        case let .listStyle(style):
            if chrome.usesIOSChrome {
                view
            } else {
                switch style {
                case .automatic: view.listStyle(.automatic)
                case .plain: view.listStyle(.plain)
                case .inset: view.listStyle(.inset)
                // Real `GroupedListStyle` is unavailable on macOS; inset-grouped is the closest look.
                // Real `GroupedListStyle` / `InsetGroupedListStyle` are both unavailable on
                // macOS; inset is the closest look this chrome has.
                case .grouped, .insetGrouped: view.listStyle(.inset)
                case .sidebar: view.listStyle(.sidebar)
                }
            }
        case let .toggleStyle(style):
            if chrome.usesIOSChrome {
                view
            } else {
                switch style {
                case .automatic: view.toggleStyle(.automatic)
                case .swiftSwitch: view.toggleStyle(.switch)
                case .button: view.toggleStyle(.button)
                case .checkbox: view.toggleStyle(.checkbox)
                }
            }
        case let .labelStyle(style):
            if chrome.usesIOSChrome {
                view
            } else {
                switch style {
                case .automatic: view.labelStyle(.automatic)
                case .iconOnly: view.labelStyle(.iconOnly)
                case .titleOnly: view.labelStyle(.titleOnly)
                case .titleAndIcon: view.labelStyle(.titleAndIcon)
                }
            }
        case let .progressViewStyle(style):
            if chrome.usesIOSChrome {
                view
            } else {
                switch style {
                case .automatic: view.progressViewStyle(.automatic)
                case .linear: view.progressViewStyle(.linear)
                case .circular: view.progressViewStyle(.circular)
                }
            }
        case let .controlSize(size):
            view.controlSize(MockupTokens.controlSize(size))
        case let .badge(value):
            view.badge(Text(value.asString ?? ""))
        case let .alert(title, message, buttonTitles):
            view.overlay {
                MockAlertCard(title: title, message: message, buttonTitles: buttonTitles, isDialog: false)
            }
        case let .confirmationDialog(title, buttonTitles):
            view.overlay(alignment: .bottom) {
                MockAlertCard(title: title, message: nil, buttonTitles: buttonTitles, isDialog: true)
            }
        }
    }

    private var onClickShowTarget: String? {
        for modifier in node.modifiers {
            if case let .onClickShow(name) = modifier { return name }
        }
        return nil
    }

    private func activateOnClickShow(_ name: String) {
        flow?.show(name, from: stageFrame)
    }

    /// A `.pickerStyle(_:)` anywhere in this node's chain wins over the constructor default.
    private func effectivePickerStyle(fallback: MockPickerStyle) -> MockPickerStyle {
        for modifier in node.modifiers.reversed() {
            if case let .pickerStyle(style) = modifier { return style }
        }
        return fallback
    }

    /// A `.tabViewStyle(_:)` anywhere in this node's chain, folded onto the `.tabView` base the
    /// same way `.pickerStyle` folds onto `.picker`.
    private var effectiveTabViewStyle: MockTabViewStyle {
        for modifier in node.modifiers.reversed() {
            if case let .tabViewStyle(style) = modifier { return style }
        }
        return .automatic
    }

    private var effectiveTabBarMinimizeBehavior: MockTabBarMinimizeBehavior {
        for modifier in node.modifiers.reversed() {
            if case let .tabBarMinimizeBehavior(behavior) = modifier { return behavior }
        }
        return .automatic
    }

    private var tabViewBottomAccessoryNode: MockNode? {
        for modifier in node.modifiers.reversed() {
            if case let .tabViewBottomAccessory(accessory) = modifier { return accessory }
        }
        return nil
    }

    @ViewBuilder
    private func textEditorView(initialText: String, editable: Bool) -> some View {
        Group {
            if editable {
                MockTextEditor(initialText: initialText)
            } else {
                TextEditor(text: .constant(initialText))
                    .disabled(true)
            }
        }
        .scrollContentBackground(.hidden)
        .frame(minHeight: chrome.usesIOSChrome ? 120 : 100)
        .padding(8)
        .background(
            chrome.usesIOSChrome ? MockupIOSTokens.systemGray6(colorScheme) : Color.primary.opacity(0.05),
            in: .rect(cornerRadius: 10)
        )
    }

    private static let sampleDate = Date(timeIntervalSince1970: 1_700_000_000)
}

private extension MockDimension {
    var cgFloatValue: CGFloat {
        switch self {
        case .infinity: .infinity
        case let .points(value): CGFloat(value)
        }
    }
}

private extension View {
    /// `.symbolEffect(...)`'s static end state — the canvas can't animate, so `.appear` /
    /// `.drawOn` / `.replace` / `.bounce` / `.pulse` / `.wiggle` / `.breathe` / `.rotate` read as
    /// the image's normal resting frame, and `.disappear` / `.drawOff` fade it; `.variableColor`
    /// switches on multicolor rendering to hint at the partial-fill look.
    @ViewBuilder
    func symbolEffectEndState(_ effect: MockSymbolEffect?) -> some View {
        switch effect {
        case .disappear, .drawOff:
            self.opacity(0.3)
        case .variableColor:
            self.symbolRenderingMode(.multicolor)
        default:
            self
        }
    }
}

// MARK: - Interactive leaves

/// Real local state seeded from the source's `@State` initial value. Resets when the tree
/// shape changes on reparse — acceptable for a sketch preview.
private struct MockTextField: View {
    let placeholder: String
    @State private var text: String

    init(placeholder: String, initialText: String) {
        self.placeholder = placeholder
        _text = State(initialValue: initialText)
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
    }
}

private struct MockTextEditor: View {
    @State private var text: String

    init(initialText: String) {
        _text = State(initialValue: initialText)
    }

    var body: some View {
        TextEditor(text: $text)
    }
}

private struct MockToggle: View {
    let title: String
    @State private var isOn: Bool

    init(title: String, initialOn: Bool) {
        self.title = title
        _isOn = State(initialValue: initialOn)
    }

    var body: some View {
        Toggle(title, isOn: $isOn)
    }
}

private struct MockSecureField: View {
    let placeholder: String
    @State private var text: String

    init(placeholder: String, initialText: String) {
        self.placeholder = placeholder
        _text = State(initialValue: initialText)
    }

    var body: some View {
        SecureField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
    }
}

private struct MockPicker: View {
    let title: String
    let options: [String]
    let style: MockPickerStyle
    @State private var selection: Int

    init(title: String, options: [String], selectedIndex: Int, style: MockPickerStyle) {
        self.title = title
        self.options = options
        self.style = style
        _selection = State(initialValue: max(0, min(selectedIndex, options.count - 1)))
    }

    var body: some View {
        picker
            .modifier(PickerStyleModifier(style: style))
    }

    private var picker: some View {
        Picker(title, selection: $selection) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Text(option).tag(index)
            }
        }
    }

    private struct PickerStyleModifier: ViewModifier {
        let style: MockPickerStyle

        func body(content: Content) -> some View {
            switch style {
            case .automatic: content.pickerStyle(.automatic)
            case .segmented: content.pickerStyle(.segmented)
            case .menu: content.pickerStyle(.menu)
            case .inline: content.pickerStyle(.inline)
            case .wheel, .palette: content.pickerStyle(.automatic)
            }
        }
    }
}

private struct MockSlider: View {
    let lowerBound: Double
    let upperBound: Double
    @State private var value: Double

    init(value: Double, lowerBound: Double, upperBound: Double) {
        self.lowerBound = lowerBound
        self.upperBound = max(upperBound, lowerBound + 0.0001)
        _value = State(initialValue: min(max(value, lowerBound), upperBound))
    }

    var body: some View {
        Slider(value: $value, in: lowerBound...upperBound)
    }
}

private struct MockStepper: View {
    let title: String
    @State private var value: Double

    init(title: String, value: Double) {
        self.title = title
        _value = State(initialValue: value)
    }

    var body: some View {
        Stepper(value: $value, in: -999_999...999_999) {
            if title.isEmpty {
                Text(value == value.rounded() ? String(Int(value)) : String(value))
            } else {
                Text("\(title): \(value == value.rounded() ? String(Int(value)) : String(value))")
            }
        }
    }
}

private struct MockDisclosureGroup<Content: View>: View {
    let title: String
    @State private var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    init(title: String, isExpanded: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        _isExpanded = State(initialValue: isExpanded)
        self.content = content
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: RenderSpacing.xs) { content() }
        } label: {
            Text(title.isEmpty ? "Details" : title)
        }
    }
}

/// `NavigationStack` in the source is a layout hint: children fill the device. Back lives on
/// `MockupStage` so Play and canvas share one stack.
private struct MockNavigationStack<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.mockupChrome) private var chrome

    var body: some View {
        content()
            .padding(chrome.usesIOSChrome ? 0 : RenderSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct MockNavigationLink: View {
    let title: String
    let destination: MockNode?
    let targetName: String?
    @Environment(\.mockupChrome) private var chrome
    @Environment(\.mockupFlow) private var flow
    @Environment(\.mockupStageFrame) private var stageFrame
    @Environment(\.mockupInListRow) private var inRow

    var body: some View {
        Button(action: activate) {
            HStack(spacing: 8) {
                Text(title.isEmpty ? "Link" : title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if chrome.usesIOSChrome && !inRow {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(chrome.usesIOSChrome ? Color.primary : Color.accentColor)
    }

    private func activate() {
        if flow?.openNamed(title: title, destinationName: targetName, from: stageFrame) == true {
            return
        }
        guard let destination, MockupFlowRouting.isInlineable(destination) else {
            if let targetName {
                flow?.show(targetName, from: stageFrame)
            }
            return
        }
        flow?.pushInline(destination, name: targetName, from: stageFrame)
    }
}

/// `Link("Title", destination:)`. No networking (Mockup is offline-first) — styled like a link,
/// but inert; `destination` is shown as a tooltip-style caption rather than actually opened.
private struct MockLink: View {
    let title: String
    let destination: String
    @Environment(\.mockupChrome) private var chrome

    var body: some View {
        HStack(spacing: 4) {
            Text(title.isEmpty ? destination : title)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(chrome.usesIOSChrome ? Color.blue : Color.accentColor)
    }
}

/// `.sheet` / `.fullScreenCover` on a view: tap presents (or auto-presents when `isPresented`
/// folded true). Named-screen destinations jump; inline content overlays the stage.
private struct MockSheetHost: ViewModifier {
    let content: MockNode?
    let targetName: String?
    let isCover: Bool
    let autoPresent: Bool
    @Environment(\.mockupFlow) private var flow

    func body(content host: Content) -> some View {
        host
            .simultaneousGesture(TapGesture().onEnded { present() })
            .onAppear {
                if autoPresent { present() }
            }
    }

    private func present() {
        if let content, MockupFlowRouting.isInlineable(content) {
            flow?.present(sheet: content, cover: isCover, name: targetName)
            return
        }
        if let targetName {
            if let scene = flow?.scene(matching: targetName) {
                flow?.present(sheet: scene.root, cover: isCover, name: scene.name)
                return
            }
            flow?.present(sheet: .leaf(.text(targetName)), cover: isCover, name: targetName)
        }
    }
}

/// `.onClickShow("Name")` on a non-button: tap shows that scene.
private struct MockOnClickShow: ViewModifier {
    let name: String
    @Environment(\.mockupFlow) private var flow
    @Environment(\.mockupStageFrame) private var stageFrame

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
            .onTapGesture { flow?.show(name, from: stageFrame) }
    }
}

/// Selected tab's content plus a bottom tab strip. Tapping a tab switches the preview.
///
/// `minimizeBehavior` has no macOS API to call (`.onScrollDown` / `.onScrollUp` are iOS-only, and
/// there is no live scroll position to drive one anyway) — a non-`.automatic` behavior instead
/// shows the compact pill form permanently, as a representative sketch of what minimizing looks
/// like, rather than trying to simulate a live scroll-linked transition.
private struct MockTabView: View {
    let tabs: [MockTab]
    let style: MockTabViewStyle
    let minimizeBehavior: MockTabBarMinimizeBehavior
    let bottomAccessory: MockNode?
    @State private var selection: Int
    @Environment(\.mockupChrome) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        tabs: [MockTab],
        selectedIndex: Int,
        style: MockTabViewStyle,
        minimizeBehavior: MockTabBarMinimizeBehavior,
        bottomAccessory: MockNode?
    ) {
        self.tabs = tabs
        self.style = style
        self.minimizeBehavior = minimizeBehavior
        self.bottomAccessory = bottomAccessory
        _selection = State(initialValue: tabs.isEmpty ? 0 : max(0, min(selectedIndex, tabs.count - 1)))
    }

    private var isMinimized: Bool { minimizeBehavior != .automatic }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if tabs.indices.contains(selection) {
                    MockNodeView(node: tabs[selection].content)
                        .id(selection)
                        .transition(MockupRouteAnimation.tab.transition(reduceMotion: reduceMotion))
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .renderAnimation(RenderMotion.standard, value: selection)

            if !tabs.isEmpty {
                if let bottomAccessory {
                    GlassEffectContainer {
                        MockNodeView(node: bottomAccessory)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .padding(.horizontal, isMinimized ? 32 : 12)
                    .padding(.bottom, 6)
                }
                if style == .page {
                    pageDots
                } else if isMinimized {
                    minimizedBar
                } else if chrome.usesIOSChrome {
                    MockupIOSTabBar(tabs: tabs, selection: $selection)
                } else {
                    macTabBar
                }
            }
        }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, _ in
                Circle()
                    .fill(index == selection ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
                    .onTapGesture { selection = index }
            }
        }
        .padding(.vertical, 10)
    }

    /// The compact, floating pill form a minimizing tab bar settles into.
    private var minimizedBar: some View {
        GlassEffectContainer {
            HStack(spacing: 2) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    Button {
                        withAnimation(MockupRouteAnimation.tab.animation(reduceMotion: reduceMotion)) {
                            selection = index
                        }
                    } label: {
                        Image(systemName: tab.systemImage ?? "circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(index == selection ? Color.accentColor : Color.secondary)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .fixedSize()
        .padding(.bottom, 8)
    }

    private var macTabBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    Button {
                        withAnimation(MockupRouteAnimation.tab.animation(reduceMotion: reduceMotion)) {
                            selection = index
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tab.systemImage ?? "circle.fill")
                                .font(.body)
                            Text(tab.title)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(index == selection ? Color.accentColor : Color.secondary)
                        .padding(.top, 6)
                        .padding(.bottom, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(.ultraThinMaterial)
        }
    }
}

/// A synthetic bar / line / area sketch. Heights are a fixed function of the index so the shape
/// is stable across reparses.
private struct MockChartView: View {
    let kind: MockChartKind
    let count: Int

    private var samples: [Double] {
        (0..<max(1, count)).map { index in
            0.2 + 0.7 * abs(sin(Double(index) * 0.9 + 0.6))
        }
    }

    var body: some View {
        GeometryReader { geo in
            let values = samples
            let width = geo.size.width
            let height = geo.size.height
            switch kind {
            case .bar:
                HStack(alignment: .bottom, spacing: max(2, width / CGFloat(values.count) * 0.25)) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        Capsule()
                            .fill(Color.accentColor.gradient)
                            .frame(height: max(2, height * value))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            case .line, .area:
                ZStack {
                    if kind == .area {
                        chartPath(values, in: geo.size, closed: true)
                            .fill(Color.accentColor.opacity(0.25))
                    }
                    chartPath(values, in: geo.size, closed: false)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                }
            }
        }
    }

    private func chartPath(_ values: [Double], in size: CGSize, closed: Bool) -> Path {
        Path { path in
            guard values.count > 1 else { return }
            let stepX = size.width / CGFloat(values.count - 1)
            let points = values.enumerated().map { index, value in
                CGPoint(x: CGFloat(index) * stepX, y: size.height * (1 - value))
            }
            if closed {
                path.move(to: CGPoint(x: 0, y: size.height))
                path.addLine(to: points[0])
            } else {
                path.move(to: points[0])
            }
            for point in points.dropFirst() { path.addLine(to: point) }
            if closed {
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
            }
        }
    }
}

/// `WebView(url:)`. Mockup is offline-first (the HTTP client is the sole exception), so this
/// never loads anything — a browser-chrome card with a fake address bar showing the URL.
private struct MockWebView: View {
    let url: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Circle().fill(.red.opacity(0.6)).frame(width: 7, height: 7)
                    Circle().fill(.yellow.opacity(0.6)).frame(width: 7, height: 7)
                    Circle().fill(.green.opacity(0.6)).frame(width: 7, height: 7)
                }
                Spacer(minLength: 8)
                Text(url.isEmpty ? "about:blank" : url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(MockupIOSTokens.systemGray6(colorScheme))

            Divider()

            VStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("Web content isn't loaded in a mockup")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.03))
        }
        .frame(minHeight: 160)
        .clipShape(.rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 1)
        }
    }
}

/// `.toolbar { }`: a leading/principal/trailing bar above the content, and a bottom bar for any
/// `.bottomBar`-placed items — each row's items share a glass background via
/// `GlassEffectContainer`, the way a real iOS 26 toolbar merges adjacent glass items.
private struct MockToolbarChrome<Content: View>: View {
    let items: [MockToolbarItem]
    @ViewBuilder let content: () -> Content

    private var topItems: [MockToolbarItem] { items.filter { $0.placement != .bottomBar } }
    private var bottomItems: [MockToolbarItem] { items.filter { $0.placement == .bottomBar } }

    var body: some View {
        VStack(spacing: 0) {
            if !topItems.isEmpty {
                bar(topItems)
                Divider()
            }
            content()
            if !bottomItems.isEmpty {
                Divider()
                bar(bottomItems)
            }
        }
    }

    @ViewBuilder
    private func bar(_ row: [MockToolbarItem]) -> some View {
        let leading = row.filter { $0.placement == .leading }
        let principal = row.filter { $0.placement == .principal }
        let trailing = row.filter { $0.placement == .trailing || $0.placement == .bottomBar }
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                group(leading)
                Spacer(minLength: 0)
                group(principal)
                Spacer(minLength: 0)
                group(trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func group(_ row: [MockToolbarItem]) -> some View {
        ForEach(Array(row.enumerated()), id: \.offset) { _, item in
            if item.isSpacer {
                Spacer(minLength: 16)
            } else if let node = item.content {
                MockNodeView(node: node)
            }
        }
    }
}

/// `.alert(_:isPresented:)` / `.confirmationDialog(_:isPresented:)`. The mock has no live
/// presentation state to bind `isPresented` to, so this draws the alert/dialog's finished
/// appearance directly over the view it's attached to — a permanently-visible preview rather
/// than a tap-triggered one, the same tradeoff `.navigationTitle` and `.searchable` already make.
private struct MockAlertCard: View {
    let title: String
    let message: String?
    let buttonTitles: [String]
    let isDialog: Bool

    var body: some View {
        VStack(spacing: isDialog ? 0 : 12) {
            if !isDialog {
                VStack(spacing: 4) {
                    Text(title).font(.headline).multilineTextAlignment(.center)
                    if let message {
                        Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)
                Divider().padding(.top, 12)
                buttonStack
            } else {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
                Divider()
                buttonStack
            }
        }
        .frame(width: isDialog ? nil : 270)
        .frame(maxWidth: isDialog ? .infinity : nil)
        .glassEffect(.regular, in: .rect(cornerRadius: isDialog ? 14 : 13))
        .padding(isDialog ? 16 : 0)
    }

    private var buttonStack: some View {
        VStack(spacing: 0) {
            ForEach(Array(buttonTitles.enumerated()), id: \.offset) { index, title in
                if index > 0 { Divider() }
                Text(title)
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
    }
}

/// Placeholder drawn where the source used syntax outside the supported subset.
public struct UnsupportedNodeBadge: View {
    public let label: String

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "questionmark.square.dashed")
            Text(label.isEmpty ? "unsupported" : label)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.orange.opacity(0.10), in: .rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.orange.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        }
    }
}
