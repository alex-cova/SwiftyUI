import Foundation

/// Which device transition a stack or presentation mutation should play. Views map this onto
/// the renderer's motion tokens + `AnyTransition`; Reduce Motion collapses everything to a fade.
public nonisolated enum MockupRouteAnimation: String, Sendable, Equatable {
    case push
    case pop
    case sheet
    case cover
    case tab

    /// Edge the incoming view appears from. `nil` means fade (and a slight scale for cover).
    public var insertionEdge: MockupRouteEdge? {
        switch self {
        case .push: .trailing
        case .pop: .leading
        case .sheet: .bottom
        case .cover, .tab: nil
        }
    }

    /// Cover scales in; tab crossfades. Push / pop / sheet slide from `insertionEdge`.
    public var usesScale: Bool { self == .cover }

    public var isFadeOnly: Bool { insertionEdge == nil && !usesScale }
}

public nonisolated enum MockupRouteEdge: String, Sendable, Equatable {
    case leading
    case trailing
    case bottom
}
