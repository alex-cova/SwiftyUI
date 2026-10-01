import Foundation

/// A non-fatal note about a piece of source the lowering could not represent. The tree still
/// renders — the offending node becomes a placeholder — and these surface in the editor pane
/// so the user can see what was skipped and where.
public nonisolated struct MockupDiagnostic: Sendable, Equatable, Identifiable {
    public enum Severity: Sendable, Equatable {
        case info
        case warning
    }

    public let id = UUID()
    public var line: Int
    public var message: String
    public var severity: Severity = .warning

    public static func == (lhs: MockupDiagnostic, rhs: MockupDiagnostic) -> Bool {
        lhs.line == rhs.line && lhs.message == rhs.message && lhs.severity == rhs.severity
    }
}
