import Foundation

/// Resolves a `NavigationLink` / sheet destination onto a named mockup screen, or decides that
/// the destination is rich enough to push inline. Pure so routing is unit-tested without views.
nonisolated enum MockupFlowRouting {
    static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// First screen title that matches `destinationName` (and `FooView` → `Foo`) or `title`.
    static func match(title: String, destinationName: String?, screens: [String]) -> String? {
        if let destinationName {
            if let hit = hit(destinationName, in: screens) { return hit }
            if destinationName.hasSuffix("View") {
                let stripped = String(destinationName.dropLast(4))
                if !stripped.isEmpty, let hit = hit(stripped, in: screens) { return hit }
            }
        }
        return hit(title, in: screens)
    }

    /// Destination is worth pushing inside the current preview (not an empty / unknown placeholder).
    static func isInlineable(_ node: MockNode?) -> Bool {
        guard let node else { return false }
        switch node.kind {
        case .unsupported:
            return false
        case let .group(children) where children.isEmpty:
            return false
        default:
            return true
        }
    }

    private static func hit(_ raw: String, in screens: [String]) -> String? {
        let key = normalize(raw)
        guard !key.isEmpty else { return nil }
        return screens.first { normalize($0) == key }
    }
}
