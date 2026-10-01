import Foundation
import SwiftSyntax

/// Walks a SwiftSyntax tree top-down and lowers the supported subset of SwiftUI view-builder
/// syntax to `MockNode`s. Anything off the whitelist becomes `.unsupported` plus a diagnostic;
/// lowering never throws and always returns whatever it could make sense of.
///
/// Identifier references (`Text(title)`, `.padding(gap)`) resolve through the `MockupSourceModel`
/// census — file-level literals plus a per-expansion scope stack for inlined view parameters.
nonisolated struct MockupLowering {
    let converter: SourceLocationConverter
    let model: MockupSourceModel
    /// Known names in the workspace's shared image library, so `Image("logo")` can be told
    /// apart from a typo — see `lowerConstructor`'s `"Image"` case. Empty means "don't know",
    /// which suppresses the missing-asset diagnostic rather than flagging every name.
    let assetNames: Set<String>
    /// Syntax identity of the selected file's tree. Notes attached to nodes from sibling
    /// files are dropped so jump-to-line stays 1-based in the buffer the user is editing.
    private let entrySyntaxID: SyntaxIdentifier
    private(set) var diagnostics: [MockupDiagnostic] = []
    private(set) var hasUnresolvedConditional = false

    private var seen: Set<String> = []
    private var depth = 0
    private var expanding: Set<String> = []
    private var expansionCount = 0
    private var expandDepth = 0
    /// Call-site argument bindings for each currently-inlined local view, innermost last.
    private var scopes: [[String: MockValue]] = []

    private static let maxDepth = 40
    private static let maxDiagnostics = 60
    private static let maxForEach = 200
    private static let maxExpansions = 400
    private static let maxExpandDepth = 12

    init(
        converter: SourceLocationConverter,
        model: MockupSourceModel,
        entryTree: SourceFileSyntax,
        assetNames: Set<String> = []
    ) {
        self.converter = converter
        self.model = model
        self.assetNames = assetNames
        self.entrySyntaxID = Syntax(entryTree).id
    }

    // MARK: - Blocks

    /// Lowers a builder block to a single node: `nil` when empty, the sole child when there is
    /// one, an implicit `VStack` otherwise (SwiftUI's own behavior for a multi-statement body).
    mutating func lowerBlock(_ items: CodeBlockItemListSyntax) -> MockNode? {
        let children = lowerChildren(items)
        switch children.count {
        case 0: return nil
        case 1: return children[0]
        default: return MockNode(kind: .vstack(alignment: nil, spacing: nil, children: children))
        }
    }

    private mutating func lowerChildren(_ items: CodeBlockItemListSyntax) -> [MockNode] {
        var out: [MockNode] = []
        for item in items {
            if let node = lowerItem(item) { out.append(node) }
        }
        return out
    }

    /// File-level `#Preview` is collected as its own device; don't also lower it as a sketch.
    private func isPreviewMacro(_ expr: ExprSyntax) -> Bool {
        expr.as(MacroExpansionExprSyntax.self)?.macroName.text == "Preview"
    }

    private mutating func lowerItem(_ item: CodeBlockItemSyntax) -> MockNode? {
        switch item.item {
        case .expr(let expr):
            if isPreviewMacro(expr) { return nil }
            if let ifExpr = expr.as(IfExprSyntax.self) { return lowerIf(ifExpr) }
            return lowerExpr(expr)
        case .stmt(let stmt):
            if let exprStmt = stmt.as(ExpressionStmtSyntax.self) {
                if isPreviewMacro(exprStmt.expression) { return nil }
                if let ifExpr = exprStmt.expression.as(IfExprSyntax.self) { return lowerIf(ifExpr) }
                return lowerExpr(exprStmt.expression)
            }
            return nil
        case .decl:
            // Local `let`/`var`/`func` inside a body are silently ignored — the source model
            // already harvested their values; noting each one would drown the real diagnostics.
            return nil
        }
    }

    // MARK: - Expressions

    private mutating func lowerExpr(_ expr: ExprSyntax) -> MockNode {
        guard depth < Self.maxDepth else {
            return .leaf(.unsupported(label: "…"))
        }
        depth += 1
        defer { depth -= 1 }

        if let tuple = expr.as(TupleExprSyntax.self), tuple.elements.count == 1 {
            return lowerExpr(tuple.elements.first!.expression)
        }
        if let call = expr.as(FunctionCallExprSyntax.self) {
            return lowerCall(call)
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            if let base = member.base?.as(DeclReferenceExprSyntax.self), base.baseName.text == "Color" {
                return .leaf(.color(.token(member.declName.baseName.text)))
            }
        }
        if let ifExpr = expr.as(IfExprSyntax.self) {
            return lowerIf(ifExpr)
        }
        // A bare reference to a locally-declared view: `rows`, `header`.
        if let ref = expr.as(DeclReferenceExprSyntax.self),
           let expansion = expandLocalView(name: ref.baseName.text, call: nil, at: expr) {
            return expansion
        }
        note("Unsupported expression", at: expr)
        return .leaf(.unsupported(label: expr.condensedText))
    }

    private mutating func lowerCall(_ call: FunctionCallExprSyntax) -> MockNode {
        let callee = call.calledExpression

        // `base.modifierName(args)` — a modifier applied to whatever `base` lowers to.
        if let member = callee.as(MemberAccessExprSyntax.self), let base = member.base {
            var node = lowerExpr(base)
            let name = member.declName.baseName.text
            switch modifier(named: name, call: call) {
            case .applied(let mod):
                node.modifiers.append(mod)
            case .ignored:
                break
            case .unknown:
                note("Modifier .\(name) isn't applied", at: member, severity: .info)
            }
            return node
        }

        // `Name(args) { trailing }` — a view constructor.
        if let ref = callee.as(DeclReferenceExprSyntax.self) {
            return lowerConstructor(name: ref.baseName.text, call: call)
        }

        note("Unsupported call", at: call)
        return .leaf(.unsupported(label: call.condensedText))
    }

    // MARK: - Conditionals

    private mutating func lowerIf(_ ifExpr: IfExprSyntax) -> MockNode {
        let known = evaluateCondition(ifExpr.conditions)
        let thenNode = lowerBlock(ifExpr.body.statements)

        var elseNode: MockNode?
        if let elseBody = ifExpr.elseBody {
            switch elseBody {
            case .codeBlock(let block):
                elseNode = lowerBlock(block.statements)
            case .ifExpr(let nested):
                elseNode = lowerIf(nested)
            }
        }

        if known == nil {
            hasUnresolvedConditional = true
        }
        return MockNode(kind: .conditional(then: thenNode, elseBranch: elseNode, known: known))
    }

    private func evaluateCondition(_ conditions: ConditionElementListSyntax) -> Bool? {
        guard conditions.count == 1, let first = conditions.first else { return nil }
        guard case .expression(let expr) = first.condition else { return nil }
        return evaluateBool(expr)
    }

    private func evaluateBool(_ expr: ExprSyntax) -> Bool? {
        if let bool = boolFrom(expr) { return bool }
        if let tuple = expr.as(TupleExprSyntax.self), tuple.elements.count == 1 {
            return evaluateBool(tuple.elements.first!.expression)
        }
        if let prefix = expr.as(PrefixOperatorExprSyntax.self), prefix.operator.text == "!" {
            return evaluateBool(prefix.expression).map { !$0 }
        }
        if let sequence = expr.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            guard elements.count == 3, let op = elements[1].as(BinaryOperatorExprSyntax.self) else { return nil }
            switch op.operator.text {
            case "&&":
                guard let lhs = evaluateBool(elements[0]), let rhs = evaluateBool(elements[2]) else { return nil }
                return lhs && rhs
            case "||":
                guard let lhs = evaluateBool(elements[0]), let rhs = evaluateBool(elements[2]) else { return nil }
                return lhs || rhs
            default:
                return compare(elements[0], op.operator.text, elements[2])
            }
        }
        return nil
    }

    private func compare(_ lhs: ExprSyntax, _ op: String, _ rhs: ExprSyntax) -> Bool? {
        if let a = doubleFrom(lhs), let b = doubleFrom(rhs) {
            switch op {
            case "==": return a == b
            case "!=": return a != b
            case "<": return a < b
            case ">": return a > b
            case "<=": return a <= b
            case ">=": return a >= b
            default: return nil
            }
        }
        if let a = stringFrom(lhs), let b = stringFrom(rhs) {
            switch op {
            case "==": return a == b
            case "!=": return a != b
            default: return nil
            }
        }
        if let a = boolFrom(lhs), let b = boolFrom(rhs) {
            switch op {
            case "==": return a == b
            case "!=": return a != b
            default: return nil
            }
        }
        return nil
    }

    // MARK: - Local view inlining

    private mutating func expandLocalView(
        name: String,
        call: FunctionCallExprSyntax?,
        at node: some SyntaxProtocol
    ) -> MockNode? {
        guard let definition = model.views[name] else { return nil }

        if expanding.contains(name) {
            note("View \(name) refers to itself", at: node, severity: .info)
            return .leaf(.unsupported(label: "recursive: \(name)"))
        }
        guard expandDepth < Self.maxExpandDepth, expansionCount < Self.maxExpansions else {
            note("View \(name) is too deeply nested to inline", at: node, severity: .info)
            return .leaf(.unsupported(label: name))
        }

        expanding.insert(name)
        expandDepth += 1
        expansionCount += 1
        defer {
            expanding.remove(name)
            expandDepth -= 1
        }

        scopes.append(bindArguments(definition.parameters, call: call))
        defer { scopes.removeLast() }

        return lowerBlock(definition.body) ?? MockNode(kind: .group(children: []))
    }

    private func bindArguments(_ parameters: [MockupParameter], call: FunctionCallExprSyntax?) -> [String: MockValue] {
        guard let call else { return [:] }
        var bindings: [String: MockValue] = [:]
        var positional = call.arguments.filter { $0.label == nil }.makeIterator()
        for parameter in parameters {
            if let label = parameter.label {
                if let arg = call.arguments.first(where: { $0.label?.text == label }),
                   let value = valueFrom(arg.expression) {
                    bindings[parameter.name] = value
                }
            } else if let arg = positional.next(), let value = valueFrom(arg.expression) {
                bindings[parameter.name] = value
            }
        }
        return bindings
    }

    // MARK: - Constructors

    private mutating func lowerConstructor(name: String, call: FunctionCallExprSyntax) -> MockNode {
        switch name {
        case "VStack", "LazyVStack":
            return MockNode(kind: .vstack(
                alignment: tokenArg("alignment", call).map(MockValue.token),
                spacing: doubleArg("spacing", call),
                children: trailingChildren(call)
            ))
        case "HStack", "LazyHStack":
            return MockNode(kind: .hstack(
                alignment: tokenArg("alignment", call).map(MockValue.token),
                spacing: doubleArg("spacing", call),
                children: trailingChildren(call)
            ))
        case "ZStack":
            return MockNode(kind: .zstack(
                alignment: tokenArg("alignment", call).map(MockValue.token),
                children: trailingChildren(call)
            ))
        case "ScrollView":
            let horizontal = firstUnlabeled(call).map { containsToken($0, "horizontal") } ?? false
            return MockNode(kind: .scrollView(horizontal: horizontal, children: trailingChildren(call)))
        case "Group":
            return MockNode(kind: .group(children: trailingChildren(call)))
        case "List":
            return MockNode(kind: .list(children: trailingChildren(call)))
        case "Form":
            return MockNode(kind: .form(children: trailingChildren(call)))
        case "Section":
            return MockNode(kind: .section(header: firstStringArgument(call), children: trailingChildren(call)))
        case "Grid":
            return MockNode(kind: .grid(children: trailingChildren(call)))
        case "GridRow":
            return MockNode(kind: .gridRow(children: trailingChildren(call)))
        case "Text":
            return .leaf(.text(firstStringArgument(call) ?? ""))
        case "Image":
            if let systemName = stringArg("systemName", call) {
                return .leaf(.image(.system(systemName)))
            }
            if let assetName = firstStringArgument(call) {
                if !assetNames.isEmpty, !assetNames.contains(assetName) {
                    note("No image named \"\(assetName)\" in Assets", at: call, severity: .info)
                }
                return .leaf(.image(.asset(assetName)))
            }
            note("Only Image(systemName:) and Image(\"asset\") render", at: call, severity: .info)
            return .leaf(.image(.system("photo")))
        case "Label":
            return .leaf(.label(
                title: firstStringArgument(call) ?? stringArg("title", call) ?? "",
                systemImage: stringArg("systemImage", call)
            ))
        case "Button":
            let title = firstStringArgument(call) ?? stringArg("title", call) ?? ""
            let labelChildren = closureArgument("label", call).map { lowerChildrenList($0) } ?? []
            return MockNode(kind: .button(title: title, children: labelChildren))
        case "Spacer":
            return .leaf(.spacer(minLength: doubleArg("minLength", call)))
        case "Divider":
            return .leaf(.divider)
        case "Rectangle":
            return .leaf(.shape(.rectangle))
        case "RoundedRectangle":
            return .leaf(.shape(.roundedRectangle(cornerRadius: doubleArg("cornerRadius", call) ?? 8)))
        case "Circle":
            return .leaf(.shape(.circle))
        case "Capsule":
            return .leaf(.shape(.capsule))
        case "Ellipse":
            return .leaf(.shape(.ellipse))
        case "ConcentricRectangle":
            return .leaf(.shape(.concentric))
        case "UnevenRoundedRectangle":
            return .leaf(.shape(shapeFrom(ExprSyntax(call)) ?? .unevenRoundedRectangle(
                topLeading: 0, bottomLeading: 0, bottomTrailing: 0, topTrailing: 0
            )))
        case "Color":
            if let named = firstStringArgument(call) {
                return .leaf(.color(.token(named)))
            }
            return .leaf(.color(.unknown))
        case "TextField":
            let (initial, editable) = bindingState(labels: ["text", "value"], call: call, defaultValue: .string(""))
            return .leaf(.textField(
                placeholder: firstStringArgument(call) ?? "",
                initialText: initial.asString ?? "",
                editable: editable
            ))
        case "SecureField":
            let (initial, editable) = bindingState(labels: ["text", "value"], call: call, defaultValue: .string(""))
            return .leaf(.secureField(
                placeholder: firstStringArgument(call) ?? "",
                initialText: initial.asString ?? "",
                editable: editable
            ))
        case "Toggle":
            let (initial, editable) = bindingState(labels: ["isOn"], call: call, defaultValue: .bool(false))
            return .leaf(.toggle(
                title: firstStringArgument(call) ?? "",
                initialOn: initial.asBool ?? false,
                editable: editable
            ))
        case "Picker":
            return lowerPicker(call)
        case "Slider":
            let bounds = rangeArg("in", call) ?? (0, 1)
            let seeded = bindingState(labels: ["value"], call: call, defaultValue: .number(.nan)).0.asNumber
            let value = (seeded?.isNaN == false ? seeded : nil) ?? (bounds.0 + bounds.1) / 2
            return .leaf(.slider(value: value, lowerBound: bounds.0, upperBound: bounds.1))
        case "Stepper":
            let value = bindingState(labels: ["value"], call: call, defaultValue: .number(0)).0.asNumber ?? 0
            return .leaf(.stepper(
                title: firstStringArgument(call) ?? stringArg("label", call) ?? "",
                value: value
            ))
        case "ProgressView":
            return .leaf(.progressView(
                title: firstStringArgument(call),
                value: doubleArg("value", call)
            ))
        case "Gauge":
            return .leaf(.gauge(
                title: firstStringArgument(call) ?? closureTextArg("label", call) ?? closureTextArg("currentValueLabel", call),
                value: doubleArg("value", call) ?? 0.5
            ))
        case "Menu":
            return MockNode(kind: .menu(
                title: firstStringArgument(call) ?? stringArg("title", call) ?? "",
                children: trailingChildren(call)
            ))
        case "DatePicker":
            return .leaf(.datePicker(title: firstStringArgument(call) ?? stringArg("titleKey", call) ?? "Date"))
        case "ColorPicker":
            return .leaf(.colorPicker(title: firstStringArgument(call) ?? "Color"))
        case "DisclosureGroup":
            let expanded = bindingState(labels: ["isExpanded"], call: call, defaultValue: .bool(false)).0.asBool ?? false
            return MockNode(kind: .disclosureGroup(
                title: firstStringArgument(call) ?? "",
                isExpanded: expanded,
                children: trailingChildren(call)
            ))
        case "ContentUnavailableView":
            return .leaf(.contentUnavailable(
                title: firstStringArgument(call) ?? "",
                systemImage: stringArg("systemImage", call) ?? "questionmark.circle",
                description: descriptionTextArg(call)
            ))
        case "NavigationStack", "NavigationView", "NavigationSplitView":
            return MockNode(kind: .navigationStack(children: trailingChildren(call)))
        case "NavigationLink":
            return lowerNavigationLink(call)
        case "TabView":
            return lowerTabView(call)
        case "Chart":
            return lowerChart(call)
        case "ForEach":
            return lowerForEach(call)
        case "EmptyView":
            return MockNode(kind: .group(children: []))
        case "LinearGradient", "RadialGradient", "AngularGradient":
            return .leaf(.color(gradientFrom(ExprSyntax(call)).map(MockValue.gradient) ?? .unknown))
        case "GlassEffectContainer":
            return MockNode(kind: .glassEffectContainer(
                spacing: doubleArg("spacing", call),
                children: trailingChildren(call)
            ))
        case "TextEditor":
            let (initial, editable) = bindingState(labels: ["text"], call: call, defaultValue: .string(""))
            return .leaf(.textEditor(placeholder: "", initialText: initial.asString ?? "", editable: editable))
        case "WebView":
            return .leaf(.webView(url: firstStringArgument(call) ?? stringArg("url", call) ?? ""))
        case "LabeledContent":
            return .leaf(.labeledContent(
                title: firstStringArgument(call) ?? stringArg("title", call) ?? "",
                value: stringArg("value", call) ?? closureTextArg("content", call) ?? ""
            ))
        case "Link":
            return .leaf(.link(
                title: firstStringArgument(call) ?? stringArg("title", call) ?? "",
                destination: stringArg("destination", call) ?? ""
            ))
        // `Tab` / `TabSection` outside a `TabView` closure: no framing to draw, so a bare use
        // lowers to just its own content (matching how `.tabItem`'s child renders on its own).
        case "Tab":
            return call.trailingClosure.flatMap { lowerBlock($0.statements) } ?? MockNode(kind: .group(children: []))
        case "TabSection":
            return MockNode(kind: .group(children: trailingChildren(call)))
        // `ToolbarItem` / `ToolbarItemGroup` / `ToolbarSpacer` outside a `.toolbar { }` closure:
        // no bar to draw, so a bare use lowers to just its own content (or nothing, for a spacer).
        case "ToolbarItem", "ToolbarItemGroup":
            return call.trailingClosure.flatMap { lowerBlock($0.statements) } ?? MockNode(kind: .group(children: []))
        case "ToolbarSpacer":
            return MockNode(kind: .group(children: []))
        default:
            if let expansion = expandLocalView(name: name, call: call, at: call) {
                return expansion
            }
            note("Unknown view \(name) — not a builtin or local View", at: call)
            return .leaf(.unsupported(label: name))
        }
    }

    /// Resolves a `text:` / `isOn:` argument to its seed value and whether the renderer may own
    /// live state for it. `$name` bound to a resolvable `@State` literal is editable; `.constant`
    /// and unresolved bindings are not.
    private func bindingState(
        labels: [String],
        call: FunctionCallExprSyntax,
        defaultValue: MockValue
    ) -> (MockValue, Bool) {
        guard let expr = labels.lazy.compactMap({ self.argument($0, call) }).first else {
            return (defaultValue, false)
        }
        if let inner = expr.as(FunctionCallExprSyntax.self),
           let member = inner.calledExpression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "constant",
           let firstArg = inner.arguments.first?.expression,
           let value = MockupLiterals.value(from: firstArg) {
            return (value, false)
        }
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            let bare = ref.baseName.text.hasPrefix("$") ? String(ref.baseName.text.dropFirst()) : ref.baseName.text
            if let value = literalValue(bare) {
                return (value, true)
            }
        }
        return (defaultValue, false)
    }

    private mutating func lowerForEach(_ call: FunctionCallExprSyntax) -> MockNode {
        let count = forEachCount(firstUnlabeled(call) ?? call.arguments.first?.expression, at: call)
        let child = call.trailingClosure.flatMap { lowerBlock($0.statements) }
            ?? .leaf(.unsupported(label: "ForEach body"))
        return .leaf(.forEach(count: count, child: child))
    }

    private mutating func forEachCount(_ expr: ExprSyntax?, at node: some SyntaxProtocol) -> Int {
        if let expr, let count = staticCount(expr) {
            return count
        }
        note("ForEach count couldn't be read; showing 3", at: node, severity: .info)
        return 3
    }

    /// A collection literal's element count read without emitting a diagnostic — an array literal,
    /// an integer literal, or a `a..<b` / `a...b` range over resolvable bounds. `nil` when the
    /// expression is a runtime value.
    private func staticCount(_ expr: ExprSyntax) -> Int? {
        if let array = expr.as(ArrayExprSyntax.self) {
            return min(array.elements.count, Self.maxForEach)
        }
        if let intLit = expr.as(IntegerLiteralExprSyntax.self), let value = intFromText(intLit.literal.text) {
            return max(0, min(value, Self.maxForEach))
        }
        if let range = parseRange(expr) {
            let span = Int(range.upper - range.lower) + (range.isClosed ? 1 : 0)
            return max(0, min(span, Self.maxForEach))
        }
        return nil
    }

    /// `a...b` / `a..<b` over resolvable numeric bounds. Shared by `Slider(in:)` and range-based
    /// `ForEach`.
    private func parseRange(_ expr: ExprSyntax) -> (lower: Double, upper: Double, isClosed: Bool)? {
        guard let sequence = expr.as(SequenceExprSyntax.self) else { return nil }
        let elements = Array(sequence.elements)
        guard elements.count == 3,
              let op = elements[1].as(BinaryOperatorExprSyntax.self),
              let lower = doubleFrom(elements[0]),
              let upper = doubleFrom(elements[2])
        else { return nil }
        switch op.operator.text {
        case "...": return (lower, upper, true)
        case "..<": return (lower, upper, false)
        default: return nil
        }
    }

    private func rangeArg(_ label: String, _ call: FunctionCallExprSyntax) -> (Double, Double)? {
        argument(label, call).flatMap(parseRange).map { ($0.lower, $0.upper) }
    }

    // MARK: - Compound constructors

    private mutating func lowerPicker(_ call: FunctionCallExprSyntax) -> MockNode {
        let title = firstStringArgument(call) ?? stringArg("label", call) ?? ""
        var options: [String] = []
        for child in trailingChildren(call) {
            switch child.kind {
            case let .text(value):
                options.append(value)
            case let .label(labelTitle, _):
                options.append(labelTitle)
            case let .forEach(count, forEachChild):
                if case .text = forEachChild.kind {
                    options.append(contentsOf: (1...max(1, count)).map { "Item \($0)" })
                }
            default:
                break
            }
        }
        if options.isEmpty {
            note("Picker options couldn't be read; showing placeholders", at: call, severity: .info)
            options = ["Option 1", "Option 2", "Option 3"]
        }
        let seeded = bindingState(labels: ["selection"], call: call, defaultValue: .number(0)).0.asNumber.map { Int($0) } ?? 0
        let selectedIndex = max(0, min(seeded, options.count - 1))
        return MockNode(kind: .picker(title: title, options: options, selectedIndex: selectedIndex, style: .automatic))
    }

    private mutating func lowerTabView(_ call: FunctionCallExprSyntax) -> MockNode {
        guard let closure = call.trailingClosure else {
            return MockNode(kind: .tabView(tabs: [], selectedIndex: 0))
        }
        let tabs = lowerTabContent(closure.statements, sectionTitle: nil)
        let seeded = bindingState(labels: ["selection"], call: call, defaultValue: .number(0)).0.asNumber.map { Int($0) } ?? 0
        let selectedIndex = tabs.isEmpty ? 0 : max(0, min(seeded, tabs.count - 1))
        return MockNode(kind: .tabView(tabs: tabs, selectedIndex: selectedIndex))
    }

    /// A `TabView`'s (or nested `TabSection`'s) children — either the legacy `.tabItem(...)`
    /// style or iOS 26's `Tab(_:systemImage:)` / `Tab(role:)` / `TabSection(_:) { }` — flattened
    /// to one `[MockTab]` list. `sectionTitle` tags every tab produced while inside a section.
    private mutating func lowerTabContent(_ items: CodeBlockItemListSyntax, sectionTitle: String?) -> [MockTab] {
        var tabs: [MockTab] = []
        for item in items {
            if case .expr(let expr) = item.item, let call = expr.as(FunctionCallExprSyntax.self),
               let ref = call.calledExpression.as(DeclReferenceExprSyntax.self) {
                if ref.baseName.text == "Tab" {
                    tabs.append(lowerTab(call, sectionTitle: sectionTitle, index: tabs.count))
                    continue
                }
                if ref.baseName.text == "TabSection" {
                    let title = firstStringArgument(call)
                    if let inner = call.trailingClosure {
                        tabs.append(contentsOf: lowerTabContent(inner.statements, sectionTitle: title ?? "Section"))
                    }
                    continue
                }
            }
            guard let node = lowerItem(item) else { continue }
            let info = tabItemInfo(item)
            tabs.append(MockTab(
                title: info.title ?? "Tab \(tabs.count + 1)",
                systemImage: info.systemImage,
                content: node,
                sectionTitle: sectionTitle
            ))
        }
        return tabs
    }

    private mutating func lowerTab(_ call: FunctionCallExprSyntax, sectionTitle: String?, index: Int) -> MockTab {
        let isSearch = tokenArg("role", call) == "search"
        let title = firstStringArgument(call) ?? stringArg("title", call) ?? (isSearch ? "Search" : "Tab \(index + 1)")
        let systemImage = stringArg("systemImage", call) ?? stringArg("image", call) ?? (isSearch ? "magnifyingglass" : nil)
        let content = call.trailingClosure.flatMap { lowerBlock($0.statements) } ?? MockNode(kind: .group(children: []))
        return MockTab(
            title: title,
            systemImage: systemImage,
            content: content,
            isSearchRole: isSearch,
            sectionTitle: sectionTitle
        )
    }

    /// Pulls `title` / `systemImage` out of a `.tabItem { Label(…) }` (or bare `Text` / `Image`)
    /// applied to a `TabView` child, without lowering the modifier itself.
    private func tabItemInfo(_ item: CodeBlockItemSyntax) -> (title: String?, systemImage: String?) {
        guard case .expr(let expr) = item.item else { return (nil, nil) }
        var current: ExprSyntax? = expr
        while let call = current?.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
            if member.declName.baseName.text == "tabItem", let closure = call.trailingClosure {
                return labelInfo(from: closure.statements)
            }
            current = member.base
        }
        return (nil, nil)
    }

    private func labelInfo(from statements: CodeBlockItemListSyntax) -> (title: String?, systemImage: String?) {
        var title: String?
        var image: String?
        for statement in statements {
            guard case .expr(let expr) = statement.item,
                  let call = expr.as(FunctionCallExprSyntax.self),
                  let ref = call.calledExpression.as(DeclReferenceExprSyntax.self)
            else { continue }
            switch ref.baseName.text {
            case "Label":
                title = title ?? firstStringArgument(call) ?? stringArg("title", call)
                image = image ?? stringArg("systemImage", call)
            case "Text":
                title = title ?? firstStringArgument(call)
            case "Image":
                image = image ?? stringArg("systemName", call)
            default:
                break
            }
        }
        return (title, image)
    }

    private mutating func lowerChart(_ call: FunctionCallExprSyntax) -> MockNode {
        var kind: MockChartKind = .bar
        var count = 6
        if let closure = call.trailingClosure {
            let body = closure.statements.description
            if body.contains("LineMark") {
                kind = .line
            } else if body.contains("AreaMark") || body.contains("PointMark") {
                kind = .area
            }
            for statement in closure.statements {
                guard case .expr(let expr) = statement.item,
                      let forEach = expr.as(FunctionCallExprSyntax.self),
                      let ref = forEach.calledExpression.as(DeclReferenceExprSyntax.self),
                      ref.baseName.text == "ForEach",
                      let arg = firstUnlabeled(forEach) ?? forEach.arguments.first?.expression,
                      let resolved = staticCount(arg)
                else { continue }
                count = resolved
            }
        }
        return .leaf(.chart(kind: kind, count: max(1, min(count, 60))))
    }

    /// The string inside a `description: Text("…")` argument (`ContentUnavailableView`).
    private func descriptionTextArg(_ call: FunctionCallExprSyntax) -> String? {
        guard let inner = argument("description", call)?.as(FunctionCallExprSyntax.self),
              let ref = inner.calledExpression.as(DeclReferenceExprSyntax.self),
              ref.baseName.text == "Text"
        else { return nil }
        return firstStringArgument(inner)
    }

    /// The string inside a `label: { Text("…") }` trailing-style argument (`Gauge`).
    private func closureTextArg(_ label: String, _ call: FunctionCallExprSyntax) -> String? {
        guard let statements = closureArgument(label, call) else { return nil }
        return labelInfo(from: statements).title
    }

    private func pickerStyleValue(_ call: FunctionCallExprSyntax) -> MockPickerStyle {
        switch firstUnlabeled(call).flatMap(tokenFrom) {
        case "segmented": return .segmented
        case "menu": return .menu
        case "inline": return .inline
        case "wheel": return .wheel
        case "palette": return .palette
        default: return .automatic
        }
    }

    private func contentModeValue(_ call: FunctionCallExprSyntax) -> MockContentMode {
        tokenArg("contentMode", call) == "fill" ? .fill : .fit
    }

    // MARK: - iOS 26 token helpers

    /// Walks a `.regular.tint(.blue).interactive()` chain outside-in: peels `.tint(_)` /
    /// `.interactive()` calls, recursing on the base until it hits the bare `.regular` /
    /// `.clear` / `.identity` that roots the chain.
    private func glassFrom(_ expr: ExprSyntax) -> MockGlass? {
        if let call = expr.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           let base = member.base {
            guard var glass = glassFrom(base) else { return nil }
            switch member.declName.baseName.text {
            case "tint":
                if let value = firstValue(call) { glass.tint = value }
            case "interactive":
                glass.interactive = firstUnlabeled(call).flatMap(boolFrom) ?? true
            default:
                break
            }
            return glass
        }
        if let member = expr.as(MemberAccessExprSyntax.self), member.base == nil {
            switch member.declName.baseName.text {
            case "regular": return MockGlass(variant: .regular)
            case "clear": return MockGlass(variant: .clear)
            case "identity": return MockGlass(variant: .identity)
            default: return nil
            }
        }
        return nil
    }

    private func buttonStyleFrom(_ token: String) -> MockButtonStyle? {
        switch token {
        case "automatic": .automatic
        case "plain": .plain
        case "bordered": .bordered
        case "borderedProminent": .borderedProminent
        case "borderless": .borderless
        case "glass": .glass
        case "glassProminent": .glassProminent
        default: nil
        }
    }

    private func tabViewStyleFrom(_ token: String) -> MockTabViewStyle? {
        switch token {
        case "automatic": .automatic
        case "page": .page
        case "sidebarAdaptable": .sidebarAdaptable
        case "grouped", "tabBarOnly": .grouped
        default: nil
        }
    }

    private func tabBarMinimizeBehaviorFrom(_ token: String) -> MockTabBarMinimizeBehavior? {
        switch token {
        case "automatic": .automatic
        case "onScrollDown": .onScrollDown
        case "onScrollUp": .onScrollUp
        case "never": .never
        default: nil
        }
    }

    /// `ToolbarItem` / `ToolbarItemGroup` / `ToolbarSpacer` inside a `.toolbar { }` closure.
    private mutating func lowerToolbarItems(_ call: FunctionCallExprSyntax) -> [MockToolbarItem] {
        guard let closure = call.trailingClosure else { return [] }
        var items: [MockToolbarItem] = []
        for item in closure.statements {
            guard case .expr(let expr) = item.item,
                  let toolbarCall = expr.as(FunctionCallExprSyntax.self),
                  let ref = toolbarCall.calledExpression.as(DeclReferenceExprSyntax.self)
            else {
                if let node = lowerItem(item) {
                    items.append(MockToolbarItem(placement: .trailing, content: node))
                }
                continue
            }
            switch ref.baseName.text {
            case "ToolbarItem":
                let placement = toolbarPlacementFrom(tokenArg("placement", toolbarCall))
                let content = closureArgument("content", toolbarCall).flatMap { lowerBlock($0) }
                    ?? toolbarCall.trailingClosure.flatMap { lowerBlock($0.statements) }
                items.append(MockToolbarItem(placement: placement, content: content))
            case "ToolbarItemGroup":
                let placement = toolbarPlacementFrom(tokenArg("placement", toolbarCall))
                let content = toolbarCall.trailingClosure.flatMap { lowerBlock($0.statements) }
                items.append(MockToolbarItem(placement: placement, content: content))
            case "ToolbarSpacer":
                let placement = toolbarPlacementFrom(tokenArg("placement", toolbarCall))
                items.append(MockToolbarItem(placement: placement, content: nil, isSpacer: true))
            default:
                if let node = lowerItem(item) {
                    items.append(MockToolbarItem(placement: .trailing, content: node))
                }
            }
        }
        return items
    }

    /// Collapses the many real `ToolbarItemPlacement` cases to the four buckets that visually
    /// differ in a static sketch.
    private func toolbarPlacementFrom(_ token: String?) -> MockToolbarPlacement {
        switch token {
        case "topBarLeading", "navigation", "cancellationAction": .leading
        case "principal": .principal
        case "bottomBar": .bottomBar
        default: .trailing // topBarTrailing, primaryAction, confirmationAction, automatic, nil
        }
    }

    private func scrollEdgeStyleFrom(_ token: String) -> MockScrollEdgeStyle? {
        switch token {
        case "automatic": .automatic
        case "soft": .soft
        case "hard": .hard
        default: nil
        }
    }

    private func presentationSizingFrom(_ token: String) -> MockPresentationSizing? {
        switch token {
        case "automatic": .automatic
        case "form": .form
        case "page": .page
        case "fitted": .fitted
        default: nil
        }
    }

    /// `.presentationDetents([.medium, .large])` — folds the requested detents onto the same
    /// `MockPresentationSizing` `.presentationSizing` uses, favoring the tallest one present.
    private func detentSizing(_ call: FunctionCallExprSyntax) -> MockPresentationSizing {
        guard let array = firstUnlabeled(call)?.as(ArrayExprSyntax.self) else { return .automatic }
        let tokens = array.elements.compactMap { tokenFrom($0.expression) }
        if tokens.contains("large") { return .page }
        if tokens.contains("medium") { return .form }
        return .automatic
    }

    private func symbolRenderingModeFrom(_ token: String) -> MockSymbolRenderingMode? {
        switch token {
        case "monochrome": .monochrome
        case "hierarchical": .hierarchical
        case "palette": .palette
        case "multicolor": .multicolor
        default: nil
        }
    }

    private func symbolColorRenderingModeFrom(_ token: String) -> MockSymbolColorRenderingMode? {
        switch token {
        case "flat": .flat
        case "gradient": .gradient
        default: nil
        }
    }

    private func symbolVariableValueModeFrom(_ token: String) -> MockSymbolVariableValueMode? {
        switch token {
        case "color": .color
        case "draw": .draw
        default: nil
        }
    }

    private func symbolEffectFrom(_ token: String) -> MockSymbolEffect? {
        switch token {
        case "appear": .appear
        case "disappear": .disappear
        case "bounce": .bounce
        case "pulse": .pulse
        case "variableColor": .variableColor
        case "wiggle": .wiggle
        case "breathe": .breathe
        case "rotate": .rotate
        case "replace": .replace
        case "drawOn": .drawOn
        case "drawOff": .drawOff
        default: nil
        }
    }

    private func imageScaleFrom(_ token: String) -> MockImageScale? {
        switch token {
        case "small": .small
        case "medium": .medium
        case "large": .large
        default: nil
        }
    }

    private func listStyleFrom(_ token: String) -> MockListStyle? {
        switch token {
        case "automatic": .automatic
        case "plain": .plain
        case "inset": .inset
        case "grouped": .grouped
        case "insetGrouped": .insetGrouped
        case "sidebar": .sidebar
        default: nil
        }
    }

    private func toggleStyleFrom(_ token: String) -> MockToggleStyle? {
        switch token {
        case "automatic": .automatic
        case "switch": .swiftSwitch
        case "button": .button
        case "checkbox": .checkbox
        default: nil
        }
    }

    private func labelStyleFrom(_ token: String) -> MockLabelStyle? {
        switch token {
        case "automatic": .automatic
        case "iconOnly": .iconOnly
        case "titleOnly": .titleOnly
        case "titleAndIcon": .titleAndIcon
        default: nil
        }
    }

    private func progressViewStyleFrom(_ token: String) -> MockProgressViewStyle? {
        switch token {
        case "automatic": .automatic
        case "linear": .linear
        case "circular": .circular
        default: nil
        }
    }

    private func controlSizeFrom(_ token: String) -> MockControlSize? {
        switch token {
        case "mini": .mini
        case "small": .small
        case "regular": .regular
        case "large": .large
        case "extraLarge": .extraLarge
        default: nil
        }
    }

    private func lowerAlert(_ call: FunctionCallExprSyntax) -> MockModifier {
        .alert(
            title: firstStringArgument(call) ?? "Alert",
            message: closureArgument("message", call).flatMap { labelInfo(from: $0).title },
            buttonTitles: alertButtonTitles(call)
        )
    }

    private func lowerConfirmationDialog(_ call: FunctionCallExprSyntax) -> MockModifier {
        .confirmationDialog(
            title: firstStringArgument(call) ?? "Are you sure?",
            buttonTitles: alertButtonTitles(call)
        )
    }

    /// Button titles out of an `.alert` / `.confirmationDialog`'s actions closure (`actions:` or
    /// trailing).
    private func alertButtonTitles(_ call: FunctionCallExprSyntax) -> [String] {
        guard let items = closureArgument("actions", call) ?? call.trailingClosure?.statements else {
            return ["OK"]
        }
        var titles: [String] = []
        for item in items {
            guard case .expr(let expr) = item.item,
                  let buttonCall = expr.as(FunctionCallExprSyntax.self),
                  let ref = buttonCall.calledExpression.as(DeclReferenceExprSyntax.self),
                  ref.baseName.text == "Button"
            else { continue }
            titles.append(firstStringArgument(buttonCall) ?? stringArg("title", buttonCall) ?? "Button")
        }
        return titles.isEmpty ? ["OK"] : titles
    }

    // MARK: - Modifiers

    private enum ModifierResult {
        case applied(MockModifier)
        /// Recognized but has no bearing on a static mock (styles, gestures, lifecycle).
        case ignored
        case unknown
    }

    private mutating func modifier(named name: String, call: FunctionCallExprSyntax) -> ModifierResult {
        switch name {
        case "padding":
            if call.arguments.isEmpty && call.trailingClosure == nil {
                return .applied(.padding(edges: nil, length: nil))
            }
            var edges: MockValue?
            var length: Double?
            for arg in call.arguments {
                if let value = doubleFrom(arg.expression) {
                    length = value
                } else if let token = tokenFrom(arg.expression) {
                    edges = .token(token)
                }
            }
            return .applied(.padding(edges: edges, length: length))
        case "frame":
            return .applied(.frame(parseFrame(call.arguments)))
        case "foregroundStyle", "foregroundColor":
            return firstValue(call).map { .applied(.foregroundStyle($0)) } ?? .ignored
        case "font":
            return firstValue(call).map { .applied(.font($0)) } ?? .ignored
        case "fontWeight":
            return firstValue(call).map { .applied(.fontWeight($0)) } ?? .ignored
        case "bold":
            return .applied(.bold)
        case "italic":
            return .applied(.italic)
        case "fill":
            return .applied(.fill(firstValue(call) ?? .token("primary")))
        case "stroke":
            return .applied(.stroke(color: firstValue(call) ?? .token("primary"), lineWidth: strokeWidth(call)))
        case "strokeBorder":
            return .applied(.strokeBorder(color: firstValue(call) ?? .token("primary"), lineWidth: strokeWidth(call)))
        case "background":
            if let closure = call.trailingClosure {
                return .applied(.background(lowerBlock(closure.statements) ?? MockNode(kind: .group(children: []))))
            }
            if let first = call.arguments.first(where: { $0.label == nil })?.expression ?? call.arguments.first?.expression {
                return .applied(.background(styleNode(from: first)))
            }
            return .ignored
        case "overlay":
            let alignment = tokenArg("alignment", call).map(MockValue.token)
            if let closure = call.trailingClosure {
                return .applied(.overlay(
                    node: lowerBlock(closure.statements) ?? MockNode(kind: .group(children: [])),
                    alignment: alignment
                ))
            }
            if let first = call.arguments.first(where: { $0.label == nil })?.expression {
                return .applied(.overlay(node: styleNode(from: first), alignment: alignment))
            }
            return .ignored
        case "cornerRadius":
            return firstDouble(call).map { .applied(.cornerRadius($0)) } ?? .ignored
        case "clipShape":
            return firstUnlabeled(call).flatMap(shapeFrom).map { .applied(.clipShape($0)) } ?? .ignored
        case "opacity":
            return firstDouble(call).map { .applied(.opacity($0)) } ?? .ignored
        case "shadow":
            return .applied(.shadow(
                color: argument("color", call).flatMap(valueFrom),
                radius: doubleArg("radius", call) ?? 4,
                x: doubleArg("x", call) ?? 0,
                y: doubleArg("y", call) ?? 0
            ))
        case "border":
            return .applied(.border(
                color: firstValue(call) ?? .token("primary"),
                width: doubleArg("width", call) ?? 1
            ))
        case "multilineTextAlignment":
            return firstValue(call).map { .applied(.multilineTextAlignment($0)) } ?? .ignored
        case "lineLimit":
            return firstInt(call).map { .applied(.lineLimit($0)) } ?? .ignored
        case "tint":
            return firstValue(call).map { .applied(.tint($0)) } ?? .ignored
        case "navigationTitle":
            return firstStringArgument(call).map { .applied(.navigationTitle($0)) } ?? .ignored
        case "pickerStyle":
            return .applied(.pickerStyle(pickerStyleValue(call)))
        case "searchable":
            return .applied(.searchable(prompt: stringArg("prompt", call)))
        case "sheet", "fullScreenCover", "popover":
            return .applied(lowerSheet(name: name, call: call))
        case "onClickShow":
            if let target = firstStringArgument(call), !target.isEmpty {
                return .applied(.onClickShow(target))
            }
            return .ignored
        case "resizable":
            return .applied(.resizable)
        case "scaledToFit":
            return .applied(.aspectRatio(ratio: nil, contentMode: .fit))
        case "scaledToFill":
            return .applied(.aspectRatio(ratio: nil, contentMode: .fill))
        case "aspectRatio":
            return .applied(.aspectRatio(ratio: firstDouble(call), contentMode: contentModeValue(call)))
        case "clipped":
            return .applied(.clipped)
        // MARK: iOS 26
        case "glassEffect":
            let glass = firstUnlabeled(call).flatMap(glassFrom) ?? MockGlass()
            let shape = argument("in", call).flatMap(shapeFrom)
            return .applied(.glassEffect(glass, shape: shape))
        case "buttonStyle":
            return .applied(.buttonStyle(firstUnlabeled(call).flatMap(tokenFrom).flatMap(buttonStyleFrom) ?? .automatic))
        case "tabViewStyle":
            return .applied(.tabViewStyle(firstUnlabeled(call).flatMap(tokenFrom).flatMap(tabViewStyleFrom) ?? .automatic))
        case "tabBarMinimizeBehavior":
            return .applied(.tabBarMinimizeBehavior(
                firstUnlabeled(call).flatMap(tokenFrom).flatMap(tabBarMinimizeBehaviorFrom) ?? .automatic
            ))
        case "tabViewBottomAccessory":
            let content = call.trailingClosure.flatMap { lowerBlock($0.statements) } ?? MockNode(kind: .group(children: []))
            return .applied(.tabViewBottomAccessory(content))
        case "toolbar":
            return .applied(.toolbar(lowerToolbarItems(call)))
        case "backgroundExtensionEffect":
            return .applied(.backgroundExtensionEffect)
        case "scrollEdgeEffectStyle":
            let style = firstUnlabeled(call).flatMap(tokenFrom).flatMap(scrollEdgeStyleFrom) ?? .automatic
            let edges = argument("for", call).flatMap(tokenFrom).map(MockValue.token)
            return .applied(.scrollEdgeEffectStyle(style: style, edges: edges))
        case "safeAreaBar", "safeAreaInset":
            let edge = argument("edge", call).flatMap(tokenFrom).map(MockValue.token)
            let content = call.trailingClosure.flatMap { lowerBlock($0.statements) }
                ?? closureArgument("content", call).flatMap { lowerBlock($0) }
            guard let content else { return .ignored }
            return .applied(.safeAreaBar(edge: edge, node: content))
        case "presentationSizing":
            return .applied(.presentationSizing(
                firstUnlabeled(call).flatMap(tokenFrom).flatMap(presentationSizingFrom) ?? .automatic
            ))
        case "presentationDetents":
            return .applied(.presentationSizing(detentSizing(call)))
        case "containerShape":
            return firstUnlabeled(call).flatMap(shapeFrom).map { .applied(.containerShape($0)) } ?? .ignored
        case "symbolRenderingMode":
            return .applied(.symbolRenderingMode(
                firstUnlabeled(call).flatMap(tokenFrom).flatMap(symbolRenderingModeFrom) ?? .monochrome
            ))
        case "symbolColorRenderingMode":
            return .applied(.symbolColorRenderingMode(
                firstUnlabeled(call).flatMap(tokenFrom).flatMap(symbolColorRenderingModeFrom) ?? .flat
            ))
        case "symbolVariableValueMode":
            return .applied(.symbolVariableValueMode(
                firstUnlabeled(call).flatMap(tokenFrom).flatMap(symbolVariableValueModeFrom) ?? .color
            ))
        case "symbolEffect":
            return .applied(.symbolEffect(firstUnlabeled(call).flatMap(tokenFrom).flatMap(symbolEffectFrom) ?? .appear))
        case "imageScale":
            return .applied(.imageScale(firstUnlabeled(call).flatMap(tokenFrom).flatMap(imageScaleFrom) ?? .medium))
        case "listStyle":
            return .applied(.listStyle(firstUnlabeled(call).flatMap(tokenFrom).flatMap(listStyleFrom) ?? .automatic))
        case "toggleStyle":
            return .applied(.toggleStyle(firstUnlabeled(call).flatMap(tokenFrom).flatMap(toggleStyleFrom) ?? .automatic))
        case "labelStyle":
            return .applied(.labelStyle(firstUnlabeled(call).flatMap(tokenFrom).flatMap(labelStyleFrom) ?? .automatic))
        case "progressViewStyle":
            return .applied(.progressViewStyle(
                firstUnlabeled(call).flatMap(tokenFrom).flatMap(progressViewStyleFrom) ?? .automatic
            ))
        case "controlSize":
            return .applied(.controlSize(firstUnlabeled(call).flatMap(tokenFrom).flatMap(controlSizeFrom) ?? .regular))
        case "badge":
            return firstValue(call).map { .applied(.badge($0)) } ?? .ignored
        case "alert":
            return .applied(lowerAlert(call))
        case "confirmationDialog":
            return .applied(lowerConfirmationDialog(call))
        default:
            if MockupVocabulary.ignoredModifierNames.contains(name) { return .ignored }
            return .unknown
        }
    }

    private func strokeWidth(_ call: FunctionCallExprSyntax) -> Double {
        doubleArg("lineWidth", call) ?? 1
    }

    private func parseFrame(_ arguments: LabeledExprListSyntax) -> MockFrame {
        var frame = MockFrame()
        for arg in arguments {
            guard let label = arg.label?.text else { continue }
            switch label {
            case "width": frame.width = doubleFrom(arg.expression)
            case "height": frame.height = doubleFrom(arg.expression)
            case "minWidth": frame.minWidth = doubleFrom(arg.expression)
            case "minHeight": frame.minHeight = doubleFrom(arg.expression)
            case "idealWidth": frame.width = frame.width ?? doubleFrom(arg.expression)
            case "idealHeight": frame.height = frame.height ?? doubleFrom(arg.expression)
            case "maxWidth": frame.maxWidth = dimensionFrom(arg.expression)
            case "maxHeight": frame.maxHeight = dimensionFrom(arg.expression)
            case "alignment": frame.alignment = tokenFrom(arg.expression).map(MockValue.token)
            default: break
            }
        }
        return frame
    }

    // MARK: - Children helpers

    private mutating func lowerNavigationLink(_ call: FunctionCallExprSyntax) -> MockNode {
        var destination: MockNode?
        var targetName: String?

        if let destExpr = argument("destination", call) {
            (destination, targetName) = resolveDestination(destExpr)
        } else if let destItems = closureArgument("destination", call) {
            (destination, targetName) = resolveDestinationItems(destItems)
        }

        var labelTitle: String?
        if let labelItems = closureArgument("label", call) ?? additionalTrailing("label", call) {
            labelTitle = labelInfo(from: labelItems).title
        }

        if let trailing = call.trailingClosure {
            if destination != nil || targetName != nil {
                labelTitle = labelTitle ?? labelInfo(from: trailing.statements).title
            } else {
                (destination, targetName) = resolveDestinationItems(trailing.statements)
            }
        }

        let title = firstStringArgument(call)
            ?? stringArg("title", call)
            ?? labelTitle
            ?? targetName
            ?? "Link"
        return MockNode(kind: .navigationLink(title: title, destination: destination, targetName: targetName))
    }

    private mutating func lowerSheet(name: String, call: FunctionCallExprSyntax) -> MockModifier {
        let presented = bindingState(labels: ["isPresented"], call: call, defaultValue: .bool(false)).0
        var content: MockNode?
        var targetName: String?
        if let trailing = call.trailingClosure {
            (content, targetName) = resolveDestinationItems(trailing.statements)
        } else if let items = closureArgument("content", call) {
            (content, targetName) = resolveDestinationItems(items)
        }
        return .sheet(
            content: content,
            targetName: targetName,
            isCover: name == "fullScreenCover",
            autoPresent: presented.asBool == true
        )
    }

    /// Destination of a link or sheet: builtins and local `View`s inline; an unknown callee is a
    /// named-screen target and must not warn (the user may have a screen titled that, not a type).
    private mutating func resolveDestination(_ expr: ExprSyntax) -> (MockNode?, String?) {
        if let tuple = expr.as(TupleExprSyntax.self), tuple.elements.count == 1 {
            return resolveDestination(tuple.elements.first!.expression)
        }
        if let call = expr.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           let base = member.base {
            let (node, target) = resolveDestination(base)
            if var node {
                switch modifier(named: member.declName.baseName.text, call: call) {
                case .applied(let mod):
                    node.modifiers.append(mod)
                case .ignored, .unknown:
                    break
                }
                return (node, target)
            }
            return (nil, target)
        }
        if let call = expr.as(FunctionCallExprSyntax.self),
           let ref = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return resolveDestinationCallee(ref.baseName.text, call: call, at: call)
        }
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            return resolveDestinationCallee(ref.baseName.text, call: nil, at: ref)
        }
        return (lowerExpr(expr), nil)
    }

    private mutating func resolveDestinationItems(_ items: CodeBlockItemListSyntax) -> (MockNode?, String?) {
        let exprs: [ExprSyntax] = items.compactMap { item in
            switch item.item {
            case .expr(let expr):
                return expr
            case .stmt(let stmt):
                return stmt.as(ExpressionStmtSyntax.self)?.expression
            default:
                return nil
            }
        }
        if exprs.count == 1 {
            return resolveDestination(exprs[0])
        }
        if exprs.isEmpty {
            return (nil, nil)
        }
        return (lowerBlock(items), nil)
    }

    private mutating func resolveDestinationCallee(
        _ name: String,
        call: FunctionCallExprSyntax?,
        at node: some SyntaxProtocol
    ) -> (MockNode?, String?) {
        if MockupVocabulary.constructor(named: name) != nil {
            guard let call else { return (nil, nil) }
            return (lowerConstructor(name: name, call: call), nil)
        }
        if let expansion = expandLocalView(name: name, call: call, at: node) {
            return (expansion, name)
        }
        return (nil, name)
    }

    private func additionalTrailing(_ label: String, _ call: FunctionCallExprSyntax) -> CodeBlockItemListSyntax? {
        call.additionalTrailingClosures.first { $0.label.text == label }?.closure.statements
    }

    private mutating func trailingChildren(_ call: FunctionCallExprSyntax) -> [MockNode] {
        guard let closure = call.trailingClosure else { return [] }
        return lowerChildrenList(closure.statements)
    }

    private mutating func lowerChildrenList(_ items: CodeBlockItemListSyntax) -> [MockNode] {
        lowerChildren(items)
    }

    private func closureArgument(_ label: String, _ call: FunctionCallExprSyntax) -> CodeBlockItemListSyntax? {
        call.arguments.first { $0.label?.text == label }?
            .expression.as(ClosureExprSyntax.self)?
            .statements
    }

    // MARK: - Style / value extraction

    private mutating func styleNode(from expr: ExprSyntax) -> MockNode {
        if let shape = shapeFrom(expr) {
            return .leaf(.shape(shape))
        }
        if let value = valueFrom(expr) {
            switch value {
            case .token, .gradient:
                return .leaf(.color(value))
            default:
                break
            }
        }
        if let member = expr.as(MemberAccessExprSyntax.self), member.base == nil {
            return .leaf(.color(.token(member.declName.baseName.text)))
        }
        return lowerExpr(expr)
    }

    private func shapeFrom(_ expr: ExprSyntax) -> MockShape? {
        if let call = expr.as(FunctionCallExprSyntax.self),
           let ref = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            switch ref.baseName.text {
            case "Rectangle": return .rectangle
            case "RoundedRectangle": return .roundedRectangle(cornerRadius: doubleArg("cornerRadius", call) ?? 8)
            case "Circle": return .circle
            case "Capsule": return .capsule
            case "Ellipse": return .ellipse
            case "ConcentricRectangle": return .concentric
            case "UnevenRoundedRectangle":
                return .unevenRoundedRectangle(
                    topLeading: doubleArg("topLeadingRadius", call) ?? 0,
                    bottomLeading: doubleArg("bottomLeadingRadius", call) ?? 0,
                    bottomTrailing: doubleArg("bottomTrailingRadius", call) ?? 0,
                    topTrailing: doubleArg("topTrailingRadius", call) ?? 0
                )
            default: return nil
            }
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            switch member.declName.baseName.text {
            case "circle": return .circle
            case "capsule": return .capsule
            case "rect", "buttonBorder", "containerRelative": return .rectangle
            case "concentric": return .concentric
            default: return nil
            }
        }
        return nil
    }

    private func valueFrom(_ expr: ExprSyntax) -> MockValue? {
        if let literal = MockupLiterals.value(from: expr) { return literal }
        if let systemFont = systemFontFrom(expr) { return systemFont }
        if let gradient = gradientFrom(expr) { return .gradient(gradient) }
        if let resolved = resolveIdentifier(expr) { return resolved }
        return nil
    }

    private func systemFontFrom(_ expr: ExprSyntax) -> MockValue? {
        guard
            let call = expr.as(FunctionCallExprSyntax.self),
            let member = call.calledExpression.as(MemberAccessExprSyntax.self),
            member.base == nil,
            member.declName.baseName.text == "system"
        else { return nil }
        return .systemFont(size: doubleArg("size", call) ?? 17, weight: tokenArg("weight", call))
    }

    private func gradientFrom(_ expr: ExprSyntax) -> MockGradient? {
        guard let call = expr.as(FunctionCallExprSyntax.self) else { return nil }

        let kindName: String
        if let ref = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            kindName = ref.baseName.text
        } else if let member = call.calledExpression.as(MemberAccessExprSyntax.self), member.base == nil {
            kindName = member.declName.baseName.text
        } else {
            return nil
        }

        let kind: MockGradient.Kind
        switch kindName {
        case "LinearGradient", "linearGradient": kind = .linear
        case "RadialGradient", "radialGradient": kind = .radial
        case "AngularGradient", "angularGradient": kind = .angular
        default: return nil
        }

        let colorsExpr = argument("colors", call)
            ?? argument("gradient", call)
            ?? firstUnlabeled(call)
        var colors: [MockValue] = []
        if let array = colorsExpr?.as(ArrayExprSyntax.self) {
            colors = array.elements.compactMap { valueFrom($0.expression) }
        } else if let gradientCall = colorsExpr?.as(FunctionCallExprSyntax.self),
                  let inner = argument("colors", gradientCall)?.as(ArrayExprSyntax.self) {
            colors = inner.elements.compactMap { valueFrom($0.expression) }
        }

        return MockGradient(
            kind: kind,
            colors: colors,
            startPoint: tokenArg("startPoint", call) ?? tokenArg("center", call),
            endPoint: tokenArg("endPoint", call)
        )
    }

    /// A bare identifier resolved through the scope stack then the file-level literal census.
    private func resolveIdentifier(_ expr: ExprSyntax) -> MockValue? {
        guard let ref = expr.as(DeclReferenceExprSyntax.self) else { return nil }
        return literalValue(ref.baseName.text)
    }

    private func literalValue(_ name: String) -> MockValue? {
        for scope in scopes.reversed() {
            if let value = scope[name] { return value }
        }
        return model.literals[name]
    }

    // MARK: - Literal primitives (with identifier resolution)

    private func stringFrom(_ expr: ExprSyntax) -> String? {
        MockupLiterals.string(from: expr) ?? resolveIdentifier(expr)?.asString
    }

    private func doubleFrom(_ expr: ExprSyntax) -> Double? {
        MockupLiterals.double(from: expr) ?? resolveIdentifier(expr)?.asNumber
    }

    private func boolFrom(_ expr: ExprSyntax) -> Bool? {
        MockupLiterals.bool(from: expr) ?? resolveIdentifier(expr)?.asBool
    }

    private func dimensionFrom(_ expr: ExprSyntax) -> MockDimension? {
        if let member = expr.as(MemberAccessExprSyntax.self), member.declName.baseName.text == "infinity" {
            return .infinity
        }
        return doubleFrom(expr).map { .points($0) }
    }

    private func tokenFrom(_ expr: ExprSyntax) -> String? {
        MockupLiterals.token(from: expr)
    }

    private func containsToken(_ expr: ExprSyntax, _ token: String) -> Bool {
        if tokenFrom(expr) == token { return true }
        if let array = expr.as(ArrayExprSyntax.self) {
            return array.elements.contains { tokenFrom($0.expression) == token }
        }
        return false
    }

    private func intFromText(_ text: String) -> Int? {
        Int(text.replacingOccurrences(of: "_", with: ""))
    }

    // MARK: - Argument lookup

    private func argument(_ label: String, _ call: FunctionCallExprSyntax) -> ExprSyntax? {
        call.arguments.first { $0.label?.text == label }?.expression
    }

    private func firstUnlabeled(_ call: FunctionCallExprSyntax) -> ExprSyntax? {
        call.arguments.first { $0.label == nil }?.expression
    }

    private func stringArg(_ label: String, _ call: FunctionCallExprSyntax) -> String? {
        argument(label, call).flatMap(stringFrom)
    }

    private func doubleArg(_ label: String, _ call: FunctionCallExprSyntax) -> Double? {
        argument(label, call).flatMap(doubleFrom)
    }

    private func tokenArg(_ label: String, _ call: FunctionCallExprSyntax) -> String? {
        argument(label, call).flatMap(tokenFrom)
    }

    private func firstStringArgument(_ call: FunctionCallExprSyntax) -> String? {
        if let unlabeled = firstUnlabeled(call), let string = stringFrom(unlabeled) { return string }
        if let verbatim = stringArg("verbatim", call) { return verbatim }
        if let titleKey = stringArg("titleKey", call) { return titleKey }
        return nil
    }

    private func firstValue(_ call: FunctionCallExprSyntax) -> MockValue? {
        guard let expr = firstUnlabeled(call) ?? call.arguments.first?.expression else { return nil }
        return valueFrom(expr)
    }

    private func firstDouble(_ call: FunctionCallExprSyntax) -> Double? {
        (firstUnlabeled(call) ?? call.arguments.first?.expression).flatMap(doubleFrom)
    }

    private func firstInt(_ call: FunctionCallExprSyntax) -> Int? {
        firstDouble(call).map { Int($0) }
    }

    // MARK: - Diagnostics

    private mutating func note(
        _ message: String,
        at node: some SyntaxProtocol,
        severity: MockupDiagnostic.Severity = .warning
    ) {
        guard diagnostics.count < Self.maxDiagnostics else { return }
        guard Syntax(node).root.id == entrySyntaxID else { return }
        let line = node.startLocation(converter: converter).line
        let key = "\(line)|\(message)"
        guard seen.insert(key).inserted else { return }
        diagnostics.append(MockupDiagnostic(line: line, message: message, severity: severity))
    }
}

private nonisolated extension SyntaxProtocol {
    /// Whitespace-collapsed, length-capped source text for placeholder labels and diagnostics.
    var condensedText: String {
        let collapsed = trimmedDescription
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return collapsed.count > 48 ? String(collapsed.prefix(47)) + "…" : collapsed
    }
}
