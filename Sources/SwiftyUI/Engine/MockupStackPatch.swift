import Foundation

/// One frame on the mockup device stack. `name` is the scene that produced `root` (`struct: View`,
/// `#Preview` title, or file title). Inline `NavigationLink` destinations have `name == nil` and
/// stay as-is across a reparse until the user pops them.
public nonisolated struct MockupStackFrame: Sendable, Equatable {
    public var name: String?
    public var root: MockNode
}

/// Remaps a live navigation stack onto a freshly parsed scene list so typing in the editor
/// updates the device without resetting Play.
public nonisolated enum MockupStackPatch {
    /// Named frames whose scene still exists are replaced with the new tree. A *pushed*
    /// named frame whose scene disappeared is dropped, and every frame above it is dropped
    /// with it. The **base** frame is kept even when unmatched (synthetic `preview:N` names,
    /// or a half-typed rename) so typing does not pop Play.
    /// Unnamed (inline) frames are kept until a later named miss truncates the stack.
    public static func remap(stack: [MockupStackFrame], scenes: [MockupScene]) -> [MockupStackFrame] {
        let byName = sceneIndex(scenes)
        var out: [MockupStackFrame] = []
        for frame in stack {
            guard let name = frame.name else {
                out.append(frame)
                continue
            }
            let key = MockupFlowRouting.normalize(name)
            if let scene = byName[key] {
                out.append(MockupStackFrame(name: scene.name, root: scene.root))
            } else if out.isEmpty {
                out.append(frame)
            } else {
                break
            }
        }
        return out
    }

    /// While typing, a syntax error can produce an empty tree. Keep the last renderable
    /// previews so the device does not go blank mid-keystroke; still surface diagnostics.
    public static func displaying(incoming: MockupParse, current: MockupParse) -> MockupParse {
        guard incoming.parseFailed, incoming.previews.isEmpty, !current.previews.isEmpty else {
            return incoming
        }
        var kept = current
        kept.diagnostics = incoming.diagnostics
        kept.parseFailed = true
        return kept
    }

    /// Preview column that should show the live stack. `nil` means every column keeps its own tree.
    public static func activePreviewID(previews: [MockupPreview], stackBaseName: String?) -> Int? {
        guard !previews.isEmpty else { return nil }
        guard let stackBaseName, !stackBaseName.isEmpty else { return previews.first?.id }
        let key = MockupFlowRouting.normalize(stackBaseName)
        if let hit = previews.first(where: {
            MockupFlowRouting.normalize($0.name ?? "") == key
        }) {
            return hit.id
        }
        let prefix = "preview:"
        if stackBaseName.hasPrefix(prefix),
           let raw = Int(stackBaseName.dropFirst(prefix.count)),
           previews.contains(where: { $0.id == raw }) {
            return raw
        }
        return previews.first?.id
    }

    public static func sceneName(for preview: MockupPreview) -> String {
        preview.name ?? "preview:\(preview.id)"
    }

    /// Sheet / cover content follows the named scene when one was recorded; unnamed presentations
    /// keep their current tree.
    public static func remapPresented(
        name: String?,
        cover: Bool,
        current: MockNode,
        scenes: [MockupScene]
    ) -> (node: MockNode, cover: Bool, name: String?)? {
        guard let name else {
            return (current, cover, nil)
        }
        let key = MockupFlowRouting.normalize(name)
        guard let scene = sceneIndex(scenes)[key] else { return nil }
        return (scene.root, cover, scene.name)
    }

    private static func sceneIndex(_ scenes: [MockupScene]) -> [String: MockupScene] {
        var byName: [String: MockupScene] = [:]
        for scene in scenes {
            let key = MockupFlowRouting.normalize(scene.name)
            if byName[key] == nil { byName[key] = scene }
        }
        return byName
    }
}
