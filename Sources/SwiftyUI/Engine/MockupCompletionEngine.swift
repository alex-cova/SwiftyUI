import Foundation
import SwiftParser
import SwiftSyntax

/// What a suggestion is, so the provider can pick a `CompletionItemKind` and the popup can hint it.
public nonisolated enum MockupCompletionKind: String, Sendable, Hashable {
    case view
    case snippet
    case modifier
    case ignoredModifier
    case argumentLabel
    case token
    case symbol
    case declaration
}

/// One suggestion produced for the Mockup editor. Pure value type — the provider maps it to an
/// `EditorIntelligence.CompletionItem`.
public nonisolated struct MockupCompletionSuggestion: Sendable, Hashable, Identifiable {
    public var id: String { "\(kind.rawValue):\(label)" }
    public let label: String
    public let insertText: String
    /// Short right-aligned hint ("View", "Modifier", "Colour"…).
    public let detail: String?
    public let documentation: String?
    public let kind: MockupCompletionKind
    /// UTF-16 span in the source this suggestion was built from. Covers the in-progress token
    /// (`@Sta`, `star.f`), not just the alphanumeric run the editor reports as `prefix`.
    public let replaceStartUTF16: Int
    public let replaceEndUTF16: Int

    public init(
        label: String,
        insertText: String,
        detail: String?,
        documentation: String?,
        kind: MockupCompletionKind,
        replaceStartUTF16: Int = 0,
        replaceEndUTF16: Int = 0
    ) {
        self.label = label
        self.insertText = insertText
        self.detail = detail
        self.documentation = documentation
        self.kind = kind
        self.replaceStartUTF16 = replaceStartUTF16
        self.replaceEndUTF16 = replaceEndUTF16
    }

    fileprivate func withReplaceSpan(start: Int, end: Int) -> MockupCompletionSuggestion {
        MockupCompletionSuggestion(
            label: label,
            insertText: insertText,
            detail: detail,
            documentation: documentation,
            kind: kind,
            replaceStartUTF16: start,
            replaceEndUTF16: end
        )
    }
}

/// Resolves the caret position in a SwiftUI-flavoured buffer to a set of completions.
///
/// Re-parses the buffer with `SwiftParser` (cheap, error-tolerant, and this runs off the main
/// actor inside `CompletionProvider.provide`). Never reuses `MockupEngine`'s render parse —
/// `MockupSourceModel` is non-`Sendable` and its syntax nodes don't cross task boundaries.
public nonisolated enum MockupCompletionEngine {

    /// - Parameters:
    ///   - source: the whole editor buffer.
    ///   - cursorUTF16Offset: caret offset in UTF-16 code units (Runestone / EIP native unit).
    ///   - prefix: the identifier run immediately before the caret, as reported by
    ///     `EditorIntelligence`. Filtering prefers the broader in-progress token (`@Sta`,
    ///     `star.f`) derived from `source` + cursor; `prefix` is the fallback when that token
    ///     is empty.
    ///   - index: sibling-file views. Same-file types are still harvested from `source`.
    public static func completions(
        source: String,
        cursorUTF16Offset: Int,
        prefix: String,
        index: MockupCompletionIndex = .empty
    ) -> [MockupCompletionSuggestion] {
        let (all, filterPrefix) = unfiltered(
            source: source,
            cursorUTF16Offset: cursorUTF16Offset,
            prefix: prefix,
            index: index
        )
        return filter(all, prefix: filterPrefix)
    }

    // MARK: - Site resolution

    private static func unfiltered(
        source: String,
        cursorUTF16Offset: Int,
        prefix: String,
        index: MockupCompletionIndex
    ) -> (items: [MockupCompletionSuggestion], filterPrefix: String) {
        guard !source.isEmpty else {
            return (fileTopLevelSuggestions(views: index.views), prefix)
        }
        let tree = Parser.parse(source: source)
        let views = resolvedViews(tree: tree, index: index)
        guard let position = absolutePosition(forUTF16Offset: cursorUTF16Offset, in: source) else {
            return ([], prefix)
        }
        let syntaxToken = tokenBeforeCursor(at: position, in: tree)
        let site = resolveSite(token: syntaxToken, views: views)
        let span = inProgressToken(in: source, cursorUTF16Offset: cursorUTF16Offset, site: site)
        // The `.` that governs a leading-dot value sits just before the in-progress identifier,
        // not before a leading `@` or earlier `star.` segments of an SF Symbol.
        let precededByDot = characterBeforeUTF16Offset(span.identifierStart, in: source) == "."

        let items: [MockupCompletionSuggestion]
        switch site {
        case .viewName:
            items = viewNameSuggestions(views: views)
        case .fileTopLevel:
            items = fileTopLevelSuggestions(views: views)
        case .declaration:
            items = declarationSuggestions()
        case .modifier:
            items = modifierSuggestions()
        case .argumentLabel(let callee, let used):
            items = argumentSuggestions(callee: callee, used: used, views: views, needsLeadingDot: !precededByDot)
        case .token(let kind):
            items = tokenSuggestions(kind: kind, needsLeadingDot: !precededByDot, quoted: kind == .symbol)
        case .symbol:
            items = tokenSuggestions(kind: .symbol, needsLeadingDot: false, quoted: false)
        case .asset:
            items = assetSuggestions(names: index.assetNames)
        case .tokenMember(let kind):
            items = tokenMemberSuggestions(kind: kind)
        case .none:
            items = []
        }
        let stamped = items.map { $0.withReplaceSpan(start: span.start, end: span.end) }
        let filterPrefix = span.text.isEmpty ? prefix : span.text
        return (stamped, filterPrefix)
    }

    private enum Site {
        case viewName
        case fileTopLevel
        case declaration
        case modifier
        case argumentLabel(callee: String, used: Set<String>)
        case token(kind: MockupVocabulary.ValueKind)
        /// A leading-dot token whose own type has chainable members — `.glassEffect(.regular.` —
        /// so completion offers `tint(_:)` / `interactive()` instead of falling through to
        /// `.modifier` the way any other `base.` member access would.
        case tokenMember(kind: MockupVocabulary.ValueKind)
        case symbol
        case asset
        case none
    }

    /// The token whose right edge the caret sits against — the half-typed identifier, or the
    /// `.` / `(` / `,` that introduces the position. `SwiftSyntax.token(at:)` returns the token
    /// *after* a boundary caret, so at `Foo(x: le|)` it hands back `)`; we want `le`.
    private static func tokenBeforeCursor(at position: AbsolutePosition, in tree: SourceFileSyntax) -> TokenSyntax? {
        guard let raw = tree.token(at: position) else {
            let last = tree.lastToken(viewMode: .sourceAccurate)
            return last?.previousToken(viewMode: .sourceAccurate) ?? last
        }
        if raw.tokenKind == .endOfFile || position <= raw.positionAfterSkippingLeadingTrivia {
            return raw.previousToken(viewMode: .sourceAccurate) ?? raw
        }
        return raw
    }

    private static func resolveSite(token: TokenSyntax?, views: [MockupIndexedView]) -> Site {
        guard let token else { return .fileTopLevel }

        var scan: Syntax? = Syntax(token)
        while let node = scan {
            if node.is(StringLiteralExprSyntax.self) {
                if isSymbolArgument(node) { return .symbol }
                if isAssetArgument(node) { return .asset }
                return .none
            }
            scan = node.parent
        }

        // A structural token just before the caret means a fresh argument position.
        switch token.tokenKind {
        case .leftParen, .comma:
            if let call = enclosingCall(Syntax(token)), let callee = knownCallee(call, views: views) {
                return .argumentLabel(callee: callee, used: usedLabels(call))
            }
            return .none
        case .period:
            // `Color.|` / `Glass.|` may not wrap as MemberAccess yet; the previous identifier is
            // enough.
            if let previous = token.previousToken(viewMode: .sourceAccurate)?.text,
               let kind = MockupVocabulary.typeNamespaces[previous] {
                return .token(kind: kind)
            }
        default:
            break
        }

        // A file-level `struct Foo: View { … }|` sits against the member-block `}`, which
        // would otherwise resolve as a declaration site inside the type.
        if token.tokenKind == .rightBrace,
           token.parent?.is(MemberBlockSyntax.self) == true,
           token.parent?.parent?.is(StructDeclSyntax.self) == true,
           token.parent?.parent?.parent?.is(CodeBlockItemSyntax.self) == true {
            return .fileTopLevel
        }

        var node: Syntax? = Syntax(token).parent
        while let current = node {
            if let member = current.as(MemberAccessExprSyntax.self) {
                if let base = member.base {
                    if let ref = base.as(DeclReferenceExprSyntax.self),
                       let kind = MockupVocabulary.typeNamespaces[ref.baseName.text] {
                        return .token(kind: kind)
                    }
                    // `.glassEffect(.regular.|)` — the base is itself a bare leading-dot token
                    // (`.regular`) whose type has chainable members; offer those instead of
                    // falling through to `.modifier`. Doesn't chase further (`.tint(...).|`).
                    if let innerMember = base.as(MemberAccessExprSyntax.self), innerMember.base == nil {
                        let kind = valueKind(forLeadingDotIn: innerMember)
                        if !MockupVocabulary.members(of: kind).isEmpty {
                            return .tokenMember(kind: kind)
                        }
                    }
                    return .modifier
                }
                return .token(kind: valueKind(forLeadingDotIn: member))
            }
            if let labeled = current.as(LabeledExprSyntax.self) {
                let call = enclosingCall(current)
                if let label = labeled.label?.text {
                    return .token(kind: valueKind(forLabel: label, call: call))
                }
                if let call, let callee = knownCallee(call, views: views) {
                    return .argumentLabel(callee: callee, used: usedLabels(call))
                }
                return .none
            }
            if current.is(LabeledExprListSyntax.self) {
                if let call = enclosingCall(current), let callee = knownCallee(call, views: views) {
                    return .argumentLabel(callee: callee, used: usedLabels(call))
                }
                return .none
            }
            if let call = current.as(FunctionCallExprSyntax.self) {
                if tokenTouchesArgumentClause(token, of: call), let callee = knownCallee(call, views: views) {
                    return .argumentLabel(callee: callee, used: usedLabels(call))
                }
            }
            if current.is(MemberBlockItemListSyntax.self) || current.is(MemberBlockSyntax.self) {
                return .declaration
            }
            if current.is(ClosureExprSyntax.self) {
                return .viewName
            }
            if current.is(CodeBlockItemListSyntax.self) {
                if current.parent?.is(SourceFileSyntax.self) == true {
                    return .fileTopLevel
                }
                return .viewName
            }
            node = current.parent
        }
        return .fileTopLevel
    }

    // MARK: - Syntax helpers

    private static func enclosingCall(_ node: Syntax) -> FunctionCallExprSyntax? {
        var current: Syntax? = node
        while let n = current {
            if let call = n.as(FunctionCallExprSyntax.self) { return call }
            current = n.parent
        }
        return nil
    }

    private static func calleeName(_ call: FunctionCallExprSyntax?) -> String? {
        guard let call else { return nil }
        if let ref = call.calledExpression.as(DeclReferenceExprSyntax.self) { return ref.baseName.text }
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self) { return member.declName.baseName.text }
        return nil
    }

    private static func knownCallee(_ call: FunctionCallExprSyntax, views: [MockupIndexedView]) -> String? {
        guard let name = calleeName(call) else { return nil }
        if MockupVocabulary.constructor(named: name) != nil { return name }
        if MockupVocabulary.modifier(named: name) != nil { return name }
        if views.contains(where: { $0.name == name }) { return name }
        return nil
    }

    private static func usedLabels(_ call: FunctionCallExprSyntax) -> Set<String> {
        Set(call.arguments.compactMap { $0.label?.text })
    }

    private static func tokenTouchesArgumentClause(_ token: TokenSyntax, of call: FunctionCallExprSyntax) -> Bool {
        guard let leftParen = call.leftParen, let rightParen = call.rightParen else { return false }
        let pos = token.positionAfterSkippingLeadingTrivia
        return pos >= leftParen.position && pos <= rightParen.endPosition
    }

    private static func isSymbolArgument(_ stringLiteral: Syntax) -> Bool {
        var scan: Syntax? = stringLiteral.parent
        while let node = scan {
            if let labeled = node.as(LabeledExprSyntax.self) {
                let label = labeled.label?.text
                return label == "systemName" || label == "systemImage"
            }
            if node.is(FunctionCallExprSyntax.self) { break }
            scan = node.parent
        }
        return false
    }

    /// The bare, unlabeled string in `Image("logo")` — the asset-name initializer. Deliberately
    /// distinct from `isSymbolArgument`: a labeled `systemName:`/`systemImage:` string is never
    /// an asset name, and an unlabeled string outside `Image(` is never one either.
    private static func isAssetArgument(_ stringLiteral: Syntax) -> Bool {
        var scan: Syntax? = stringLiteral.parent
        while let node = scan {
            if let labeled = node.as(LabeledExprSyntax.self) {
                guard labeled.label == nil else { return false }
                return calleeName(enclosingCall(node)) == "Image"
            }
            if node.is(FunctionCallExprSyntax.self) { break }
            scan = node.parent
        }
        return false
    }

    private static func valueKind(forLeadingDotIn member: MemberAccessExprSyntax) -> MockupVocabulary.ValueKind {
        var current: Syntax? = Syntax(member).parent
        while let n = current {
            if let labeled = n.as(LabeledExprSyntax.self) {
                let call = enclosingCall(n)
                if let label = labeled.label?.text {
                    return valueKind(forLabel: label, call: call)
                }
                if let name = calleeName(call) {
                    if let modifier = MockupVocabulary.modifier(named: name) { return modifier.primaryValueKind }
                    if let constructor = MockupVocabulary.constructor(named: name) { return constructor.primaryValueKind }
                }
                return .other
            }
            if n.is(FunctionCallExprSyntax.self) { break }
            current = n.parent
        }
        return .other
    }

    private static func valueKind(forLabel label: String, call: FunctionCallExprSyntax?) -> MockupVocabulary.ValueKind {
        let callee = calleeName(call)

        // `alignment:` means a different axis depending on the container.
        if label == "alignment" {
            switch callee {
            case "HStack", "LazyHStack": return .verticalAlignment
            case "VStack", "LazyVStack": return .horizontalAlignment
            default: return .alignment
            }
        }

        if let name = callee {
            if let constructor = MockupVocabulary.constructor(named: name),
               let match = constructor.labels.first(where: { $0.name == label }) {
                return match.valueKind
            }
            if let modifier = MockupVocabulary.modifier(named: name),
               let match = modifier.labels.first(where: { $0.name == label }) {
                return match.valueKind
            }
        }

        switch label {
        case "startPoint", "endPoint", "center": return .unitPoint
        case "systemImage", "systemName": return .symbol
        case "prompt", "titleKey", "verbatim": return .string
        case "isOn", "isExpanded", "isPresented": return .bool
        case "spacing", "radius", "lineWidth", "width", "height", "cornerRadius", "minLength": return .number
        case "in": return .shape
        case "for", "edge": return .edges
        case "placement": return .toolbarPlacement
        default: return .other
        }
    }

    private static func resolvedViews(tree: SourceFileSyntax, index: MockupCompletionIndex) -> [MockupIndexedView] {
        var byName: [String: MockupIndexedView] = Dictionary(uniqueKeysWithValues: index.views.map { ($0.name, $0) })
        let model = MockupSourceModel.build(from: tree)
        for (name, definition) in model.views where byName[name] == nil {
            byName[name] = MockupIndexedView(name: name, parameters: definition.parameters, originFile: "")
        }
        return Array(byName.values)
    }

    // MARK: - Offset conversion

    /// UTF-16 caret offset → SwiftSyntax `AbsolutePosition` (a UTF-8 byte offset). The two units
    /// diverge the moment the buffer holds anything outside the BMP (emoji, …).
    private static func absolutePosition(forUTF16Offset utf16Offset: Int, in source: String) -> AbsolutePosition? {
        guard utf16Offset >= 0 else { return nil }
        let clamped = min(utf16Offset, source.utf16.count)
        let index = String.Index(utf16Offset: clamped, in: source)
        let utf8Offset = source.utf8.distance(from: source.startIndex, to: index)
        return AbsolutePosition(utf8Offset: utf8Offset)
    }

    private static func characterBeforeUTF16Offset(_ utf16Offset: Int, in source: String) -> Character? {
        guard utf16Offset > 0 else { return nil }
        let clamped = min(utf16Offset, source.utf16.count)
        let index = String.Index(utf16Offset: clamped, in: source)
        guard index > source.startIndex else { return nil }
        return source[source.index(before: index)]
    }

    private struct TokenSpan {
        let start: Int
        let end: Int
        let text: String
        /// Start of the trailing identifier, excluding a leading `@` and earlier `foo.` segments.
        let identifierStart: Int
    }

    /// The in-progress token the popup should replace. Broader than EditorIntelligence's
    /// alphanumeric prefix: a leading `@` on attributes and dots inside SF Symbol names.
    private static func inProgressToken(
        in source: String,
        cursorUTF16Offset: Int,
        site: Site
    ) -> TokenSpan {
        let ns = source as NSString
        let end = min(max(0, cursorUTF16Offset), ns.length)
        var start = end

        func character(at utf16Offset: Int) -> Character? {
            guard utf16Offset >= 0, utf16Offset < ns.length else { return nil }
            return ns.substring(with: NSRange(location: utf16Offset, length: 1)).first
        }

        func isIdentifier(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_"
        }

        switch site {
        case .symbol:
            while start > 0, let character = character(at: start - 1), isIdentifier(character) || character == "." {
                start -= 1
            }
        case .declaration, .fileTopLevel:
            while start > 0, let character = character(at: start - 1), isIdentifier(character) {
                start -= 1
            }
            if start > 0, let lead = character(at: start - 1), lead == "@" || lead == "#" {
                start -= 1
            }
        default:
            while start > 0, let character = character(at: start - 1), isIdentifier(character) {
                start -= 1
            }
        }

        let text = ns.substring(with: NSRange(location: start, length: end - start))
        var identifierStart = end
        while identifierStart > start, let character = character(at: identifierStart - 1), isIdentifier(character) {
            identifierStart -= 1
        }
        return TokenSpan(start: start, end: end, text: text, identifierStart: identifierStart)
    }

    // MARK: - Suggestion builders

    private static func viewNameSuggestions(views: [MockupIndexedView]) -> [MockupCompletionSuggestion] {
        var out: [MockupCompletionSuggestion] = []
        for constructor in MockupVocabulary.constructors {
            out.append(MockupCompletionSuggestion(
                label: constructor.name,
                insertText: constructor.skeleton,
                detail: "View",
                documentation: documentation(constructor.summary, since: constructor.since),
                kind: .view
            ))
        }
        for view in views.sorted(by: { $0.name < $1.name }) where MockupVocabulary.constructor(named: view.name) == nil {
            out.append(MockupCompletionSuggestion(
                label: view.name,
                insertText: viewSkeleton(view),
                detail: view.originFile.isEmpty ? "Local view" : view.originFile,
                documentation: nil,
                kind: .view
            ))
        }
        return out
    }

    private static func fileTopLevelSuggestions(views: [MockupIndexedView]) -> [MockupCompletionSuggestion] {
        previewSuggestions() + declarationSuggestions() + viewNameSuggestions(views: views)
    }

    private static func previewSuggestions() -> [MockupCompletionSuggestion] {
        [
            MockupCompletionSuggestion(
                label: "#Preview",
                insertText: "#Preview {\n    \n}",
                detail: "Preview",
                documentation: "Show this view as its own device on the canvas.",
                kind: .declaration
            ),
            MockupCompletionSuggestion(
                label: "@Preview",
                insertText: "@Preview",
                detail: "Preview",
                documentation: "Opt this View struct into the canvas as another device.",
                kind: .declaration
            ),
        ]
    }

    private static func declarationSuggestions() -> [MockupCompletionSuggestion] {
        [
            MockupCompletionSuggestion(
                label: "struct View",
                insertText: "struct Name: View {\n    var body: some View {\n        \n    }\n}",
                detail: "View type",
                documentation: "A new SwiftUI view in this file.",
                kind: .declaration
            ),
            MockupCompletionSuggestion(
                label: "@State",
                insertText: "@State private var name = \"\"",
                detail: "Property",
                documentation: "A source of local mutable state.",
                kind: .declaration
            ),
        ]
    }

    private static func viewSkeleton(_ view: MockupIndexedView) -> String {
        guard !view.parameters.isEmpty else { return "\(view.name)()" }
        let args = view.parameters.map { parameter in
            let placeholder = parameter.name.prefix(1).uppercased() + parameter.name.dropFirst()
            if let label = parameter.label {
                return "\(label): \"\(placeholder)\""
            }
            return "\"\(placeholder)\""
        }.joined(separator: ", ")
        return "\(view.name)(\(args))"
    }

    private static func modifierSuggestions() -> [MockupCompletionSuggestion] {
        MockupVocabulary.modifiers.map { modifier in
            MockupCompletionSuggestion(
                label: modifier.name,
                insertText: modifier.skeleton,
                detail: modifier.isApplied ? "Modifier" : "No effect",
                documentation: documentation(modifier.summary, since: modifier.since),
                kind: modifier.isApplied ? .modifier : .ignoredModifier
            )
        }
    }

    /// Appends "New in <version>." to a summary so the popup surfaces how new a construct is,
    /// alongside what it is.
    private static func documentation(_ summary: String, since: String?) -> String {
        guard let since else { return summary }
        return "\(summary) New in \(since)."
    }

    private static func argumentSuggestions(
        callee: String,
        used: Set<String>,
        views: [MockupIndexedView],
        needsLeadingDot: Bool
    ) -> [MockupCompletionSuggestion] {
        var out: [MockupCompletionSuggestion] = []
        if let entry = MockupVocabulary.constructor(named: callee) {
            out += entry.labels
                .filter { !used.contains($0.name) }
                .map { labelSuggestion($0) }
            if used.isEmpty {
                out += tokenSuggestions(kind: entry.primaryValueKind, needsLeadingDot: needsLeadingDot, quoted: entry.primaryValueKind == .symbol)
            }
        } else if let modifier = MockupVocabulary.modifier(named: callee) {
            out += modifier.labels
                .filter { !used.contains($0.name) }
                .map { labelSuggestion($0) }
            if used.isEmpty {
                out += tokenSuggestions(kind: modifier.primaryValueKind, needsLeadingDot: needsLeadingDot, quoted: false)
            }
        } else if let view = views.first(where: { $0.name == callee }) {
            out += view.parameters.compactMap(\.label).filter { !used.contains($0) }.map { name in
                MockupCompletionSuggestion(
                    label: "\(name):",
                    insertText: "\(name): ",
                    detail: "Argument",
                    documentation: nil,
                    kind: .argumentLabel
                )
            }
        }
        return out
    }

    private static func labelSuggestion(_ label: MockupVocabulary.Label) -> MockupCompletionSuggestion {
        MockupCompletionSuggestion(
            label: "\(label.name):",
            insertText: "\(label.name): ",
            detail: "Argument",
            documentation: nil,
            kind: .argumentLabel
        )
    }

    private static func tokenSuggestions(
        kind: MockupVocabulary.ValueKind,
        needsLeadingDot: Bool,
        quoted: Bool
    ) -> [MockupCompletionSuggestion] {
        let names = MockupVocabulary.tokens(for: kind)
        let hint = detailLabel(for: kind)
        let tokenKind: MockupCompletionKind = kind == .symbol ? .symbol : .token
        var items: [MockupCompletionSuggestion] = names.map { name in
            let insert: String
            if quoted {
                insert = "\"\(name)\""
            } else if needsLeadingDot {
                insert = ".\(name)"
            } else {
                insert = name
            }
            return MockupCompletionSuggestion(
                label: name,
                insertText: insert,
                detail: hint,
                documentation: nil,
                kind: tokenKind
            )
        }
        if kind == .font {
            for factory in MockupVocabulary.fontFactories {
                let insert = needsLeadingDot ? ".\(factory.skeleton)" : factory.skeleton
                items.append(MockupCompletionSuggestion(
                    label: factory.name,
                    insertText: insert,
                    detail: hint,
                    documentation: "System font with a point size.",
                    kind: .token
                ))
            }
        }
        return items
    }

    /// `.glassEffect(.regular.` → `tint(_:)`, `interactive()`. Inserted without a leading dot —
    /// the base token that introduces the chain (`.regular`) is already typed.
    private static func tokenMemberSuggestions(kind: MockupVocabulary.ValueKind) -> [MockupCompletionSuggestion] {
        MockupVocabulary.members(of: kind).map { member in
            MockupCompletionSuggestion(
                label: member.name,
                insertText: member.skeleton,
                detail: detailLabel(for: kind),
                documentation: member.summary,
                kind: .token
            )
        }
    }

    /// Sourced from the live workspace library (`index.assetNames`) rather than a static `MockupVocabulary` list.
    /// Unquoted because the completion site is inside an existing string literal (`Image("…")`).
    private static func assetSuggestions(names: [String]) -> [MockupCompletionSuggestion] {
        names.map { name in
            MockupCompletionSuggestion(
                label: name,
                insertText: name,
                detail: "Image asset",
                documentation: nil,
                kind: .symbol
            )
        }
    }

    private static func detailLabel(for kind: MockupVocabulary.ValueKind) -> String {
        switch kind {
        case .horizontalAlignment, .verticalAlignment, .alignment: return "Alignment"
        case .textAlignment: return "Text alignment"
        case .color: return "Colour"
        case .font: return "Font"
        case .fontWeight: return "Weight"
        case .edges: return "Edges"
        case .unitPoint: return "Unit point"
        case .pickerStyle: return "Picker style"
        case .dimension: return "Dimension"
        case .symbol: return "SF Symbol"
        case .asset: return "Image asset"
        case .contentMode: return "Content mode"
        case .shape: return "Shape"
        case .axis: return "Axis"
        case .glassStyle: return "Glass"
        case .buttonStyle: return "Button style"
        case .tabViewStyle: return "Tab view style"
        case .tabBarMinimizeBehavior: return "Minimize behavior"
        case .toolbarPlacement: return "Placement"
        case .scrollEdgeStyle: return "Scroll edge style"
        case .presentationSizing: return "Presentation size"
        case .symbolRenderingMode: return "Symbol rendering"
        case .symbolColorRenderingMode: return "Symbol colour rendering"
        case .symbolVariableValueMode: return "Symbol variable value"
        case .symbolEffect: return "Symbol effect"
        case .imageScale: return "Image scale"
        case .listStyle: return "List style"
        case .toggleStyle: return "Toggle style"
        case .labelStyle: return "Label style"
        case .progressViewStyle: return "Progress style"
        case .controlSize: return "Control size"
        case .number, .string, .bool, .other: return "Value"
        }
    }

    // MARK: - Filtering

    /// Order is left to `EditorIntelligence`'s `DefaultRanker`; this only drops non-matches,
    /// which the ranker would otherwise keep for any non-`.text` kind (its floor is a positive
    /// kind weight, not zero).
    private static func filter(_ items: [MockupCompletionSuggestion], prefix: String) -> [MockupCompletionSuggestion] {
        let needle = prefix.lowercased()
        guard !needle.isEmpty else { return items }
        return items.filter { isSubsequence(needle, of: $0.label.lowercased()) }
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var i = needle.startIndex
        for character in haystack {
            if character == needle[i] {
                i = needle.index(after: i)
                if i == needle.endIndex { return true }
            }
        }
        return i == needle.endIndex
    }
}
