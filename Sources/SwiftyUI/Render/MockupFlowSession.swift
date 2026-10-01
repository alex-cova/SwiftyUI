import AppKit
import SwiftUI

/// Shared click-through state for the Mockup preview: named-scene jumps, the device stack,
/// and a presented sheet. One session drives the canvas and the Play window. `@Observable`
/// so the stage overlay and nav bar refresh without bindings threaded through every
/// `MockNodeView`.
@Observable
public final class MockupFlowSession {
    public init() {}

    public var scenes: [MockupScene] = []
    public var presented: Presented?
    public var isPlaying = false
    public var stack: [MockupStackFrame] = []
    public var lastRoute: MockupRouteAnimation = .push

    public enum Presented: Equatable {
        case sheet(MockNode, cover: Bool, name: String?)
    }

    public var sceneNames: [String] { scenes.map(\.name) }
    public var canPop: Bool { stack.count > 1 }
    public var currentRoot: MockNode? { stack.last?.root }
    public var currentName: String? { stack.last?.name }

    public func scene(matching title: String, destinationName: String? = nil) -> MockupScene? {
        guard let hit = MockupFlowRouting.match(
            title: title,
            destinationName: destinationName,
            screens: sceneNames
        ) else { return nil }
        let key = MockupFlowRouting.normalize(hit)
        return scenes.first { MockupFlowRouting.normalize($0.name) == key }
    }

    /// Resolve a scene and push it onto the device. `from` seeds the stack with the current
    /// preview so Back has somewhere to go when this is the first navigation.
    public func show(_ name: String, from base: MockupStackFrame? = nil) {
        guard let scene = scene(matching: name) else { return }
        animate(.push) {
            seed(base)
            presented = nil
            stack.append(MockupStackFrame(name: scene.name, root: scene.root))
        }
    }

    /// Named-scene push. Returns false when the caller should inline the destination locally.
    @discardableResult
    public func openNamed(
        title: String,
        destinationName: String?,
        from base: MockupStackFrame? = nil
    ) -> Bool {
        if let scene = scene(matching: title, destinationName: destinationName)
            ?? scene(matching: title) {
            animate(.push) {
                seed(base)
                presented = nil
                stack.append(MockupStackFrame(name: scene.name, root: scene.root))
            }
            return true
        }
        return false
    }

    public func push(_ scene: MockupScene) {
        animate(.push) {
            presented = nil
            stack.append(MockupStackFrame(name: scene.name, root: scene.root))
        }
    }

    public func pushInline(_ node: MockNode, name: String? = nil, from base: MockupStackFrame? = nil) {
        animate(.push) {
            seed(base)
            presented = nil
            stack.append(MockupStackFrame(name: name, root: node))
        }
    }

    @discardableResult
    public func pop() -> Bool {
        guard canPop else { return false }
        animate(.pop) {
            presented = nil
            stack.removeLast()
        }
        return true
    }

    public func startPlaying(root: MockNode, name: String?) {
        isPlaying = true
        if stack.isEmpty {
            stack = [MockupStackFrame(name: name, root: root)]
        }
        presented = nil
    }

    public func stopPlaying() {
        isPlaying = false
        stack = []
        presented = nil
        lastRoute = .push
    }

    public func resetStack() {
        stack = []
        presented = nil
        lastRoute = .push
    }

    public func present(sheet node: MockNode, cover: Bool, name: String? = nil) {
        let route: MockupRouteAnimation = cover ? .cover : .sheet
        animate(route) {
            presented = .sheet(node, cover: cover, name: name)
        }
    }

    public func dismiss() {
        let route: MockupRouteAnimation
        if case let .sheet(_, cover, _) = presented {
            route = cover ? .cover : .sheet
        } else {
            route = .sheet
        }
        animate(route) {
            presented = nil
        }
    }

    /// Swap live trees after a debounced reparse without tearing Play down.
    public func patch(scenes: [MockupScene]) {
        self.scenes = scenes
        stack = MockupStackPatch.remap(stack: stack, scenes: scenes)
        if case let .sheet(node, cover, name) = presented {
            if let remapped = MockupStackPatch.remapPresented(
                name: name,
                cover: cover,
                current: node,
                scenes: scenes
            ) {
                presented = .sheet(remapped.node, cover: remapped.cover, name: remapped.name)
            } else {
                presented = nil
            }
        }
    }

    private func seed(_ base: MockupStackFrame?) {
        guard stack.isEmpty, let base else { return }
        stack = [base]
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func animate(_ route: MockupRouteAnimation, _ body: () -> Void) {
        lastRoute = route
        withAnimation(route.animation(reduceMotion: reduceMotion), body)
    }
}

public extension EnvironmentValues {
    @Entry var mockupFlow: MockupFlowSession?
    @Entry var mockupStageFrame: MockupStackFrame?
}
