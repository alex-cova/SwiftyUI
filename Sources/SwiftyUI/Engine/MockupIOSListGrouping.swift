import Foundation

/// Folds a `List`/`Form` child list into iOS grouped sections: consecutive non-`Section`
/// nodes become one untitled group; `ForEach` / `Group` expand into rows. Pure so tests can
/// assert the grouping without instantiating a view.
nonisolated enum MockupIOSListGrouping {
    struct Block: Equatable, Sendable {
        var header: String?
        var rows: [MockNode]
    }

    static func blocks(from children: [MockNode]) -> [Block] {
        var blocks: [Block] = []
        var loose: [MockNode] = []

        func flush() {
            let rows = flatten(loose)
            if !rows.isEmpty {
                blocks.append(Block(header: nil, rows: rows))
            }
            loose = []
        }

        for child in children {
            if case let .section(header, rows) = child.kind {
                flush()
                blocks.append(Block(header: header, rows: flatten(rows)))
            } else {
                loose.append(child)
            }
        }
        flush()
        return blocks
    }

    static func flatten(_ nodes: [MockNode]) -> [MockNode] {
        var out: [MockNode] = []
        for node in nodes {
            switch node.kind {
            case let .forEach(count, child):
                let copies = max(0, min(count, 200))
                for _ in 0..<copies { out.append(child) }
            case let .group(children):
                out.append(contentsOf: flatten(children))
            default:
                out.append(node)
            }
        }
        return out
    }
}

nonisolated extension MockNode.Kind {
    /// Settings-style disclosure chevron: labels and plain text rows, not controls.
    var showsIOSDisclosureChevron: Bool {
        switch self {
        case .label, .text, .navigationLink: true
        default: false
        }
    }
}
