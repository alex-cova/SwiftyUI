import Foundation
import SwiftParser
import SwiftSyntax

/// A `struct: View` / `@ViewBuilder` member harvested for completions, without syntax nodes
/// so it can cross the completion-provider task boundary.
public nonisolated struct MockupIndexedView: Sendable, Hashable {
    public var name: String
    public var parameters: [MockupParameter]
    public var originFile: String
}

/// Workspace-wide view census for Mockup completions. Built off the main actor from every
/// file's source; the current buffer is still re-parsed in `MockupCompletionEngine` so
/// same-file types stay live between index rebuilds.
public nonisolated struct MockupCompletionIndex: Sendable, Hashable {
    public var views: [MockupIndexedView]
    /// Names in the workspace's shared image library, offered inside `Image("…")`.
    public var assetNames: [String] = []

    public static let empty = MockupCompletionIndex(views: [])

    /// Stable fingerprint so `MonoCodeEditor` only rebuilds the completion controller when
    /// the set of types (not every keystroke) changes.
    public var signature: String {
        let viewsPart = views.map { view in
            let params = view.parameters.map { "\($0.label ?? "_"):\($0.name)" }.joined(separator: ",")
            return "\(view.originFile).\(view.name)(\(params))"
        }.joined(separator: ";")
        return "\(viewsPart)|\(assetNames.joined(separator: ","))"
    }

    public static func build(files: [(name: String, source: String)], assetNames: [String] = []) -> MockupCompletionIndex {
        var seen = Set<String>()
        var views: [MockupIndexedView] = []
        for file in files {
            guard !file.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let tree = Parser.parse(source: file.source)
            let model = MockupSourceModel.build(from: tree)
            for name in model.views.keys.sorted() {
                guard seen.insert(name).inserted, let definition = model.views[name] else { continue }
                views.append(MockupIndexedView(
                    name: name,
                    parameters: definition.parameters,
                    originFile: file.name
                ))
            }
        }
        return MockupCompletionIndex(views: views, assetNames: assetNames)
    }
}
