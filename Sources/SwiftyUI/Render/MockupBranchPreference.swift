import SwiftUI

/// Which side of an unfoldable `if` the preview shows. When a condition folds to a constant the
/// renderer ignores this and shows the real branch; this only decides the ambiguous case.
public nonisolated enum MockupBranchPreference: String, CaseIterable, Identifiable, Sendable {
    case thenBranch
    case elseBranch

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .thenBranch: "if"
        case .elseBranch: "else"
        }
    }
}

public extension EnvironmentValues {
    @Entry var mockupBranchPreference: MockupBranchPreference = .thenBranch
}
