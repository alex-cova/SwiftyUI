import Foundation

/// Pure edits to a mockup source buffer. Used by the Components sheet (insert at caret) so the
/// placement is unit-tested without a `TextView`.
public nonisolated enum MockupSourceEdit {
    /// Inserts `snippet` at `utf16Offset`. A negative offset means "caret unknown" and appends
    /// at the end, matching the original Components-sheet behaviour. Surrounding newlines are
    /// added so two view builders don't glue together.
    public static func insert(_ snippet: String, into source: String, atUTF16Offset offset: Int) -> Insert {
        let snippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        let ns = source as NSString
        guard !snippet.isEmpty else {
            let caret = min(max(0, offset), ns.length)
            return Insert(source: source, caretUTF16Offset: offset < 0 ? ns.length : caret)
        }

        let index: Int
        if offset < 0 {
            index = ns.length
        } else {
            index = min(max(0, offset), ns.length)
        }

        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Insert(source: snippet, caretUTF16Offset: (snippet as NSString).length)
        }

        let before = ns.substring(to: index)
        let after = ns.substring(from: index)
        let prefix = padded(before, joiningAtEnd: true)
        let suffix = padded(after, joiningAtEnd: false)
        let combined = prefix + snippet + suffix
        let caret = (prefix as NSString).length + (snippet as NSString).length
        return Insert(source: combined, caretUTF16Offset: caret)
    }

    public struct Insert: Equatable, Sendable {
        public var source: String
        public var caretUTF16Offset: Int
    }

    /// Ensures a blank line between existing source and the snippet without stacking extra
    /// newlines when the user already left a gap.
    private static func padded(_ fragment: String, joiningAtEnd: Bool) -> String {
        if fragment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fragment
        }
        if joiningAtEnd {
            if fragment.hasSuffix("\n\n") { return fragment }
            if fragment.hasSuffix("\n") { return fragment + "\n" }
            return fragment + "\n\n"
        } else {
            if fragment.hasPrefix("\n\n") { return fragment }
            if fragment.hasPrefix("\n") { return "\n" + fragment }
            return "\n\n" + fragment
        }
    }
}
