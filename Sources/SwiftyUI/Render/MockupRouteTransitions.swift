import SwiftUI

public extension MockupRouteEdge {
    var swiftUIEdge: Edge {
        switch self {
        case .leading: .leading
        case .trailing: .trailing
        case .bottom: .bottom
        }
    }
}

public extension MockupRouteAnimation {
    func transition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        switch self {
        case .push:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .pop:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        case .sheet:
            return .move(edge: .bottom).combined(with: .opacity)
        case .cover:
            return .opacity.combined(with: .scale(scale: 0.96))
        case .tab:
            return .opacity
        }
    }

    func animation(reduceMotion: Bool) -> Animation {
        if reduceMotion { return RenderMotion.reduced }
        switch self {
        case .tab: return RenderMotion.standard
        default: return RenderMotion.emphasized
        }
    }
}

/// Device-stack identity + push/pop transition around a `MockNodeView`. Canvas and Play share
/// this so a tap on either surface plays the same motion.
@MainActor
public struct MockupNavigator: View {
    public let root: MockNode
    public var sceneName: String?
    public var flow: MockupFlowSession?

    public init(root: MockNode, sceneName: String? = nil, flow: MockupFlowSession? = nil) {
        self.root = root
        self.sceneName = sceneName
        self.flow = flow
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var identity: String {
        let name = flow?.currentName ?? sceneName ?? "root"
        let depth = flow?.stack.count ?? 0
        return "\(depth):\(name)"
    }

    private var stageFrame: MockupStackFrame {
        MockupStackFrame(name: sceneName ?? flow?.currentName, root: root)
    }

    public var body: some View {
        ZStack {
            MockNodeView(node: root)
                .id(identity)
                .transition(route.transition(reduceMotion: reduceMotion))
        }
        .clipped()
        .compositingGroup()
        .renderAnimation(route.animation(reduceMotion: reduceMotion), value: identity)
        .environment(\.mockupStageFrame, stageFrame)
    }

    private var route: MockupRouteAnimation {
        flow?.lastRoute ?? .push
    }
}
