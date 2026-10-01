import Testing
@testable import SwiftyUI

struct MockupStackPatchTests {
    private func scene(_ name: String, text: String) -> MockupScene {
        MockupScene(name: name, root: .leaf(.text(text)))
    }

    private func frame(_ name: String?, text: String) -> MockupStackFrame {
        MockupStackFrame(name: name, root: .leaf(.text(text)))
    }

    @Test func remapReplacesNamedFramesWithTheNewTree() {
        let stack = [
            frame("Home", text: "old home"),
            frame("Settings", text: "old settings"),
        ]
        let scenes = [
            scene("Home", text: "new home"),
            scene("Settings", text: "new settings"),
        ]
        let remapped = MockupStackPatch.remap(stack: stack, scenes: scenes)
        #expect(remapped.map(\.name) == ["Home", "Settings"])
        #expect(remapped[0].root.kind == .text("new home"))
        #expect(remapped[1].root.kind == .text("new settings"))
    }

    @Test func remapIsCaseInsensitiveAndKeepsTheCanonicalSceneName() {
        let stack = [frame("home", text: "old")]
        let remapped = MockupStackPatch.remap(
            stack: stack,
            scenes: [scene("Home", text: "new")]
        )
        #expect(remapped.only?.name == "Home")
        #expect(remapped.only?.root.kind == .text("new"))
    }

    @Test func remapDropsAMissingPushedSceneAndEverythingAboveIt() {
        let stack = [
            frame("Home", text: "home"),
            frame("Gone", text: "gone"),
            frame("Settings", text: "settings"),
        ]
        let remapped = MockupStackPatch.remap(
            stack: stack,
            scenes: [scene("Home", text: "home"), scene("Settings", text: "settings")]
        )
        #expect(remapped.map(\.name) == ["Home"])
    }

    @Test func remapKeepsAnUnmatchedBaseFrameSoTypingDoesNotPopPlay() {
        let stack = [frame("preview:0", text: "sketch")]
        let remapped = MockupStackPatch.remap(
            stack: stack,
            scenes: [scene("Home", text: "home")]
        )
        #expect(remapped.only?.name == "preview:0")
        #expect(remapped.only?.root.kind == .text("sketch"))
    }

    @Test func displayingKeepsTheLastTreeWhenIncomingIsEmpty() {
        var current = MockupParse.empty
        current.previews = [MockupPreview(id: 0, name: "Home", root: .leaf(.text("Hi")))]
        current.nodeCount = 1
        var incoming = MockupParse.empty
        incoming.parseFailed = true
        incoming.diagnostics = [
            MockupDiagnostic(line: 3, message: "expected '}'", severity: .warning)
        ]
        let shown = MockupStackPatch.displaying(incoming: incoming, current: current)
        #expect(shown.previews.only?.root.kind == .text("Hi"))
        #expect(shown.parseFailed)
        #expect(shown.diagnostics.count == 1)
    }

    @Test func displayingClearsWhenTheBufferIsIntentionallyEmpty() {
        var current = MockupParse.empty
        current.previews = [MockupPreview(id: 0, name: "Home", root: .leaf(.text("Hi")))]
        let shown = MockupStackPatch.displaying(incoming: .empty, current: current)
        #expect(shown.previews.isEmpty)
        #expect(!shown.parseFailed)
    }

    @Test func displayingTakesIncomingWhenItHasPreviews() {
        var current = MockupParse.empty
        current.previews = [MockupPreview(id: 0, name: "Home", root: .leaf(.text("old")))]
        var incoming = MockupParse.empty
        incoming.previews = [MockupPreview(id: 0, name: "Home", root: .leaf(.text("new")))]
        let shown = MockupStackPatch.displaying(incoming: incoming, current: current)
        #expect(shown.previews.only?.root.kind == .text("new"))
    }

    @Test func activePreviewIDMatchesTheStackBaseName() {
        let previews = [
            MockupPreview(id: 0, name: "Home", root: .leaf(.text("H"))),
            MockupPreview(id: 1, name: "Alt", root: .leaf(.text("A"))),
        ]
        #expect(MockupStackPatch.activePreviewID(previews: previews, stackBaseName: "Alt") == 1)
        #expect(MockupStackPatch.activePreviewID(previews: previews, stackBaseName: nil) == 0)
        #expect(MockupStackPatch.activePreviewID(previews: previews, stackBaseName: "preview:1") == 1)
    }

    @Test func remapKeepsUnnamedInlineFramesUntilALaterMiss() {
        let stack = [
            frame("Home", text: "home"),
            frame(nil, text: "inline"),
            frame("Settings", text: "settings"),
        ]
        let remapped = MockupStackPatch.remap(
            stack: stack,
            scenes: [scene("Home", text: "home2"), scene("Settings", text: "settings2")]
        )
        #expect(remapped.count == 3)
        #expect(remapped[1].name == nil)
        #expect(remapped[1].root.kind == .text("inline"))
        #expect(remapped[2].root.kind == .text("settings2"))
    }

    @Test func remapPresentedFollowsANamedScene() {
        let result = MockupStackPatch.remapPresented(
            name: "Sheet",
            cover: false,
            current: .leaf(.text("old")),
            scenes: [scene("Sheet", text: "new")]
        )
        #expect(result?.node.kind == .text("new"))
        #expect(result?.cover == false)
        #expect(result?.name == "Sheet")
    }

    @Test func remapPresentedDropsAMissingNamedScene() {
        let result = MockupStackPatch.remapPresented(
            name: "Gone",
            cover: true,
            current: .leaf(.text("old")),
            scenes: [scene("Home", text: "home")]
        )
        #expect(result == nil)
    }

    @Test func remapPresentedKeepsUnnamedContent() {
        let current = MockNode.leaf(.text("inline sheet"))
        let result = MockupStackPatch.remapPresented(
            name: nil,
            cover: true,
            current: current,
            scenes: [scene("Home", text: "home")]
        )
        #expect(result?.node == current)
        #expect(result?.cover == true)
        #expect(result?.name == nil)
    }
}

struct MockupRouteAnimationTests {
    @Test func pushPopsAndSheetsSlideFromAnEdge() {
        #expect(MockupRouteAnimation.push.insertionEdge == .trailing)
        #expect(MockupRouteAnimation.pop.insertionEdge == .leading)
        #expect(MockupRouteAnimation.sheet.insertionEdge == .bottom)
    }

    @Test func coverScalesAndTabFades() {
        #expect(MockupRouteAnimation.cover.insertionEdge == nil)
        #expect(MockupRouteAnimation.cover.usesScale)
        #expect(MockupRouteAnimation.tab.isFadeOnly)
        #expect(!MockupRouteAnimation.push.isFadeOnly)
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
