import SwiftSyntax

/// One call-site-bindable parameter of a local view (`struct`/computed `var`/`func`).
public nonisolated struct MockupParameter: Sendable, Equatable, Hashable {
    /// Argument label at the call site; `nil` for a positional (`_`) parameter.
    public var label: String?
    /// Name the view's body refers to it by.
    public var name: String
}

/// A locally-declared view the lowering can inline: its builder block plus the parameters it
/// takes, so `CardView(title: "Hi")` can bind `"Hi"` to `title` inside the body.
nonisolated struct MockupViewDefinition {
    var body: CodeBlockItemListSyntax
    var parameters: [MockupParameter]
}

/// A file-level `#Preview { … }` or `@Preview struct` to render as its own device.
nonisolated struct MockupPreviewSource {
    var name: String?
    /// Set when this came from `@Preview struct X`, so the engine can skip a duplicate of
    /// the implicit first `struct: View`.
    var structName: String?
    var body: CodeBlockItemListSyntax
}

/// A whole-file picture built before lowering: literal-valued declarations (for resolving
/// identifier references and folding `if` conditions) and locally-declared views (for inlining
/// custom subviews). Syntax nodes are held only for the duration of one `MockupEngine.parse`
/// call and never cross a task boundary, so this stays deliberately non-`Sendable`.
nonisolated struct MockupSourceModel {
    var literals: [String: MockValue] = [:]
    var views: [String: MockupViewDefinition] = [:]
    /// The builder block to lower from — the first `struct: View`'s `body`, else `nil` and the
    /// caller uses the file's top-level statements.
    var entry: CodeBlockItemListSyntax?
    /// Type name of `entry`, when it came from a `struct: View`.
    var entryName: String?
    /// File-level `#Preview` / `@Preview` entries, in source order. Not absorbed across files.
    var previewEntries: [MockupPreviewSource] = []
    /// Top-level `struct: View` names in source order, for play-mode scene lookup.
    var structViewNames: [String] = []

    static func build(from tree: SourceFileSyntax) -> MockupSourceModel {
        let collector = ModelCollector(viewMode: .sourceAccurate)
        collector.walk(tree)
        collector.collectFileLevelPreviews(from: tree)
        return collector.model
    }

    /// Absorbs another file's census. First declaration of a name wins, matching the
    /// collector's `== nil` guard — later files cannot overwrite an earlier `struct: View`.
    /// Does not take `other.entry` or `other.previewEntries`; the caller sets those from the
    /// selected file. `structViewNames` is appended so play-mode scenes cover the workspace.
    mutating func absorb(_ other: MockupSourceModel) {
        for (name, view) in other.views where views[name] == nil {
            views[name] = view
        }
        for (name, value) in other.literals where literals[name] == nil {
            literals[name] = value
        }
        for name in other.structViewNames where !structViewNames.contains(name) {
            structViewNames.append(name)
        }
    }
}

private nonisolated final class ModelCollector: SyntaxVisitor {
    var model = MockupSourceModel()

    private static let propertyWrappers: Set<String> = [
        "State", "StateObject", "ObservedObject", "EnvironmentObject", "Environment",
        "FocusState", "Namespace", "Binding", "AppStorage", "SceneStorage", "GestureState",
        "Bindable",
    ]

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        guard conformsToView(node.inheritanceClause) else { return .visitChildren }
        let parameters = memberwiseParameters(of: node.memberBlock)
        if let body = bodyGetter(of: node.memberBlock) {
            if model.views[node.name.text] == nil {
                model.views[node.name.text] = MockupViewDefinition(body: body, parameters: parameters)
            }
            if model.entry == nil {
                model.entry = body
                model.entryName = node.name.text
            }
            if !model.structViewNames.contains(node.name.text) {
                model.structViewNames.append(node.name.text)
            }
        }
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        collectLiteral(node)
        collectComputedView(node)
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        collectViewFunction(node)
        return .visitChildren
    }

    // MARK: - Literals

    private func collectLiteral(_ node: VariableDeclSyntax) {
        for binding in node.bindings {
            guard
                let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                let value = binding.initializer?.value,
                model.literals[pattern.identifier.text] == nil,
                let literal = MockupLiterals.value(from: value)
            else { continue }
            model.literals[pattern.identifier.text] = literal
        }
    }

    // MARK: - Views

    private func collectComputedView(_ node: VariableDeclSyntax) {
        let isBuilder = node.attributes.containsAttribute(named: "ViewBuilder")
        for binding in node.bindings {
            guard
                let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                let accessor = binding.accessorBlock,
                pattern.identifier.text != "body"
            else { continue }
            let annotationIsView = binding.typeAnnotation?.type.trimmedDescription.contains("View") ?? false
            guard isBuilder || annotationIsView else { continue }
            guard let statements = getterStatements(of: accessor) else { continue }
            if model.views[pattern.identifier.text] == nil {
                model.views[pattern.identifier.text] = MockupViewDefinition(body: statements, parameters: [])
            }
        }
    }

    private func collectViewFunction(_ node: FunctionDeclSyntax) {
        guard let body = node.body else { return }
        let isBuilder = node.attributes.containsAttribute(named: "ViewBuilder")
        let returnsView = node.signature.returnClause?.type.trimmedDescription.contains("View") ?? false
        guard isBuilder || returnsView else { return }
        let parameters = node.signature.parameterClause.parameters.map { param -> MockupParameter in
            let first = param.firstName.text
            return MockupParameter(
                label: first == "_" ? nil : first,
                name: param.secondName?.text ?? first
            )
        }
        if model.views[node.name.text] == nil {
            model.views[node.name.text] = MockupViewDefinition(body: body.statements, parameters: parameters)
        }
    }

    // MARK: - Struct helpers

    private func conformsToView(_ clause: InheritanceClauseSyntax?) -> Bool {
        guard let clause else { return false }
        return clause.inheritedTypes.contains { $0.type.trimmedDescription == "View" }
    }

    private func memberwiseParameters(of memberBlock: MemberBlockSyntax) -> [MockupParameter] {
        var parameters: [MockupParameter] = []
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            guard !hasPropertyWrapper(varDecl.attributes) else { continue }
            for binding in varDecl.bindings {
                guard
                    binding.accessorBlock == nil,
                    let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                    pattern.identifier.text != "body"
                else { continue }
                parameters.append(MockupParameter(label: pattern.identifier.text, name: pattern.identifier.text))
            }
        }
        return parameters
    }

    private func bodyGetter(of memberBlock: MemberBlockSyntax) -> CodeBlockItemListSyntax? {
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            for binding in varDecl.bindings {
                guard
                    let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                    pattern.identifier.text == "body",
                    let accessor = binding.accessorBlock
                else { continue }
                return getterStatements(of: accessor)
            }
        }
        return nil
    }

    // MARK: - File-level previews

    /// Walks only the source file's top-level statements so nested `#Preview` / `@Preview`
    /// inside a type don't become extra devices.
    func collectFileLevelPreviews(from tree: SourceFileSyntax) {
        for item in tree.statements {
            switch item.item {
            case .decl(let decl):
                collectPreviewDecl(decl)
            case .expr(let expr):
                collectPreviewExpr(expr)
            case .stmt(let stmt):
                if let exprStmt = stmt.as(ExpressionStmtSyntax.self) {
                    collectPreviewExpr(exprStmt.expression)
                }
            }
        }
    }

    private func collectPreviewDecl(_ decl: DeclSyntax) {
        if let macro = decl.as(MacroExpansionDeclSyntax.self) {
            collectPreviewMacro(
                name: macro.macroName.text,
                arguments: macro.arguments,
                closure: macro.trailingClosure
            )
            return
        }
        guard let structDecl = decl.as(StructDeclSyntax.self),
              conformsToView(structDecl.inheritanceClause),
              let mark = previewMark(from: structDecl.attributes),
              let body = bodyGetter(of: structDecl.memberBlock)
        else { return }
        model.previewEntries.append(MockupPreviewSource(
            name: mark.title ?? structDecl.name.text,
            structName: structDecl.name.text,
            body: body
        ))
    }

    private func collectPreviewExpr(_ expr: ExprSyntax) {
        guard let macro = expr.as(MacroExpansionExprSyntax.self) else { return }
        collectPreviewMacro(
            name: macro.macroName.text,
            arguments: macro.arguments,
            closure: macro.trailingClosure
        )
    }

    private func collectPreviewMacro(
        name: String,
        arguments: LabeledExprListSyntax,
        closure: ClosureExprSyntax?
    ) {
        guard name == "Preview", let body = closure?.statements else { return }
        let title = firstStringArgument(arguments) ?? constructorName(from: body)
        model.previewEntries.append(MockupPreviewSource(
            name: title,
            structName: nil,
            body: body
        ))
    }

    private struct PreviewMark {
        var title: String?
    }

    private func previewMark(from attributes: AttributeListSyntax) -> PreviewMark? {
        for element in attributes {
            guard case .attribute(let attribute) = element else { continue }
            guard attribute.attributeName.trimmedDescription == "Preview" else { continue }
            if case .argumentList(let args) = attribute.arguments {
                return PreviewMark(title: firstStringArgument(args))
            }
            return PreviewMark(title: nil)
        }
        return nil
    }

    private func firstStringArgument(_ arguments: LabeledExprListSyntax) -> String? {
        for argument in arguments {
            if let string = MockupLiterals.string(from: argument.expression) {
                return string
            }
        }
        return nil
    }

    /// `StatGrid()` or `Capsule().fill(...)` → `"StatGrid"` / `"Capsule"`.
    private func constructorName(from items: CodeBlockItemListSyntax) -> String? {
        guard items.count == 1, let item = items.first else { return nil }
        let expr: ExprSyntax? = switch item.item {
        case .expr(let expr): expr
        case .stmt(let stmt): stmt.as(ExpressionStmtSyntax.self)?.expression
        default: nil
        }
        guard var current = expr else { return nil }
        while let call = current.as(FunctionCallExprSyntax.self) {
            if let member = call.calledExpression.as(MemberAccessExprSyntax.self),
               let base = member.base {
                current = base
                continue
            }
            if let ref = call.calledExpression.as(DeclReferenceExprSyntax.self) {
                return ref.baseName.text
            }
            return nil
        }
        return nil
    }

    private func hasPropertyWrapper(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            guard case .attribute(let attribute) = element else { return false }
            return Self.propertyWrappers.contains(attribute.attributeName.trimmedDescription)
        }
    }

    private func getterStatements(of accessorBlock: AccessorBlockSyntax) -> CodeBlockItemListSyntax? {
        switch accessorBlock.accessors {
        case .getter(let items):
            return items
        case .accessors(let list):
            for accessor in list where accessor.accessorSpecifier.tokenKind == .keyword(.get) {
                if let body = accessor.body { return body.statements }
            }
            return nil
        }
    }
}

private nonisolated extension AttributeListSyntax {
    func containsAttribute(named name: String) -> Bool {
        contains { element in
            guard case .attribute(let attribute) = element else { return false }
            return attribute.attributeName.trimmedDescription == name
        }
    }
}
