import Foundation
import SwiftParser
import SwiftSyntax

/// One device on the canvas. The selected file's first `struct: View` (or top-level sketch)
/// is always a preview; each file-level `#Preview` / `@Preview` adds another unless it would
/// duplicate that entry.
public nonisolated struct MockupPreview: Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String?
    public var root: MockNode
}

/// A named view the device stack / `.onClickShow` can jump to. First name wins across the
/// whole workspace (preview titles, `struct: View`s, then file titles).
public nonisolated struct MockupScene: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var root: MockNode

    public init(name: String, root: MockNode) {
        self.name = name
        self.root = root
    }
}

/// Result of lowering a mockup source buffer.
public nonisolated struct MockupParse: Sendable, Equatable {
    public var previews: [MockupPreview]
    /// Jump targets: selected-file preview titles, every `struct: View` in the workspace,
    /// then file titles. First name wins.
    public var scenes: [MockupScene]
    public var diagnostics: [MockupDiagnostic]
    /// The Swift parser recovered from a syntax error somewhere in the buffer.
    public var parseFailed: Bool
    public var nodeCount: Int
    /// The tree contains at least one `if` whose condition could not be folded, so the viewer's
    /// branch preference decides which side shows — surfaced as a then/else control.
    public var hasUnresolvedConditional: Bool

    /// First preview's tree. `nil` when the buffer is empty or produced no renderable views.
    public var root: MockNode? { previews.first?.root }

    public static let empty = MockupParse(
        previews: [],
        scenes: [],
        diagnostics: [],
        parseFailed: false,
        nodeCount: 0,
        hasUnresolvedConditional: false
    )
}

/// One named source buffer in a mockup workspace. Files share a type namespace; the preview
/// is the selected file's entry, with sibling `struct: View`s inlined from the rest.
public nonisolated struct MockupSourceFile: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var source: String

    public init(id: UUID, name: String, source: String) {
        self.id = id
        self.name = name
        self.source = source
    }
}

/// Parses a SwiftUI-flavored source buffer and lowers a whitelisted subset of view-builder
/// syntax to `MockNode` trees. Nothing is compiled or executed — `SwiftParser` gives an
/// error-tolerant syntax tree, `MockupSourceModel` takes a whole-file census, and
/// `MockupLowering` walks it top-down.
///
/// One device is the first `struct: View`'s `body` (or the file's top-level sketch). Extra
/// devices come from file-level `#Preview { … }` macros and `@Preview` on a `struct: View`.
/// Sibling files still contribute types for inlining and named scenes for Play; only the
/// selected file's previews render on the canvas.
///
/// `nonisolated` / `Sendable` so `MockupView` can run it off the main actor on a debounce,
/// the same shape as `RegexEngine`.
public nonisolated enum MockupEngine {
    public static func parse(_ source: String, assetNames: Set<String> = []) -> MockupParse {
        let file = MockupSourceFile(id: UUID(), name: "Mockup", source: source)
        return parse(files: [file], entryID: file.id, assetNames: assetNames)
    }

    public static func parse(files: [MockupSourceFile], entryID: UUID, assetNames: Set<String> = []) -> MockupParse {
        let entryFile = files.first(where: { $0.id == entryID }) ?? files.first
        guard let entryFile,
              !entryFile.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .empty
        }

        var merged = MockupSourceModel()
        var entryTree: SourceFileSyntax?
        var entryModel = MockupSourceModel()
        var fileModels: [(MockupSourceFile, MockupSourceModel)] = []
        for file in files {
            guard !file.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let tree = Parser.parse(source: file.source)
            let model = MockupSourceModel.build(from: tree)
            if file.id == entryFile.id {
                entryTree = tree
                entryModel = model
            }
            merged.absorb(model)
            fileModels.append((file, model))
        }

        guard let entryTree else { return .empty }
        merged.entry = entryModel.entry
        merged.entryName = entryModel.entryName

        let converter = SourceLocationConverter(fileName: "\(entryFile.name).swift", tree: entryTree)
        var lowering = MockupLowering(converter: converter, model: merged, entryTree: entryTree, assetNames: assetNames)
        let previews = collectPreviews(
            entryModel: entryModel,
            entryTree: entryTree,
            lowering: &lowering
        )
        let scenes = collectScenes(
            previews: previews,
            files: fileModels,
            merged: merged,
            lowering: &lowering
        )

        return MockupParse(
            previews: previews,
            scenes: scenes,
            diagnostics: lowering.diagnostics.sorted { ($0.line, $0.message) < ($1.line, $1.message) },
            parseFailed: entryTree.hasError,
            nodeCount: previews.reduce(0) { $0 + $1.root.count },
            hasUnresolvedConditional: lowering.hasUnresolvedConditional
        )
    }

    private static func collectPreviews(
        entryModel: MockupSourceModel,
        entryTree: SourceFileSyntax,
        lowering: inout MockupLowering
    ) -> [MockupPreview] {
        var previews: [MockupPreview] = []

        func add(name: String?, items: CodeBlockItemListSyntax) {
            guard let node = lowering.lowerBlock(items) else { return }
            previews.append(MockupPreview(id: previews.count, name: name, root: node))
        }

        if let entry = entryModel.entry {
            add(name: entryModel.entryName, items: entry)
        } else if entryModel.previewEntries.isEmpty {
            add(name: nil, items: entryTree.statements)
        } else if let leftover = lowering.lowerBlock(entryTree.statements) {
            previews.append(MockupPreview(id: 0, name: nil, root: leftover))
        }

        for source in entryModel.previewEntries {
            if let structName = source.structName, structName == entryModel.entryName { continue }
            if let entryName = entryModel.entryName, isBareCall(to: entryName, in: source.body) { continue }
            add(name: source.name, items: source.body)
        }

        return previews
    }

    private static func collectScenes(
        previews: [MockupPreview],
        files: [(MockupSourceFile, MockupSourceModel)],
        merged: MockupSourceModel,
        lowering: inout MockupLowering
    ) -> [MockupScene] {
        var scenes: [MockupScene] = []
        var seen = Set<String>()

        func add(name: String, root: MockNode) {
            let key = MockupFlowRouting.normalize(name)
            guard !key.isEmpty, seen.insert(key).inserted else { return }
            scenes.append(MockupScene(name: name, root: root))
        }

        for preview in previews {
            if let name = preview.name { add(name: name, root: preview.root) }
        }
        for name in merged.structViewNames {
            guard let definition = merged.views[name] else { continue }
            guard let node = lowering.lowerBlock(definition.body) else { continue }
            add(name: name, root: node)
        }
        for (file, model) in files {
            // `parse(_:)` names the buffer "Mockup"; skip that dummy so single-buffer
            // tests don't grow a synthetic file-title scene.
            guard file.name != "Mockup" else { continue }
            guard let block = model.entry, let node = lowering.lowerBlock(block) else { continue }
            add(name: file.name, root: node)
        }
        return scenes
    }

    /// `#Preview { Dashboard() }` is the same tree as the implicit first `struct Dashboard`.
    /// A modifier chain (`Dashboard().padding()`) is a real variant and is kept.
    private static func isBareCall(to name: String, in items: CodeBlockItemListSyntax) -> Bool {
        guard items.count == 1, let item = items.first else { return false }
        let expr: ExprSyntax? = switch item.item {
        case .expr(let expr): expr
        case .stmt(let stmt): stmt.as(ExpressionStmtSyntax.self)?.expression
        default: nil
        }
        guard let call = expr?.as(FunctionCallExprSyntax.self),
              let ref = call.calledExpression.as(DeclReferenceExprSyntax.self)
        else { return false }
        return ref.baseName.text == name
    }
}
