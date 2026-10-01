import Testing
@testable import SwiftyUI

struct MockupFlowRoutingTests {
    @Test func matchPrefersDestinationNameThenStrippedViewSuffixThenTitle() {
        let screens = ["Home", "Settings", "Profile"]
        #expect(
            MockupFlowRouting.match(title: "Open", destinationName: "Settings", screens: screens)
            == "Settings"
        )
        #expect(
            MockupFlowRouting.match(title: "Open", destinationName: "SettingsView", screens: screens)
            == "Settings"
        )
        #expect(
            MockupFlowRouting.match(title: "Profile", destinationName: "MissingView", screens: screens)
            == "Profile"
        )
        #expect(
            MockupFlowRouting.match(title: "Nope", destinationName: "MissingView", screens: screens)
            == nil
        )
    }

    @Test func matchIsCaseInsensitiveAndTrimsWhitespace() {
        #expect(
            MockupFlowRouting.match(
                title: " settings ",
                destinationName: nil,
                screens: ["Settings"]
            ) == "Settings"
        )
    }

    @Test func matchFindsPreviewTitlesAndStrippedViewSuffix() {
        let scenes = ["Dashboard", "Stats", "Capsule"]
        #expect(
            MockupFlowRouting.match(title: "Open", destinationName: "Stats", screens: scenes)
            == "Stats"
        )
        #expect(
            MockupFlowRouting.match(title: "Open", destinationName: "DashboardView", screens: scenes)
            == "Dashboard"
        )
        #expect(
            MockupFlowRouting.match(title: "Nope", destinationName: "Missing", screens: scenes)
            == nil
        )
    }

    @Test func inlineableRejectsUnsupportedAndEmptyGroups() {
        #expect(!MockupFlowRouting.isInlineable(nil))
        #expect(!MockupFlowRouting.isInlineable(.leaf(.unsupported(label: "X"))))
        #expect(!MockupFlowRouting.isInlineable(MockNode(kind: .group(children: []))))
        #expect(MockupFlowRouting.isInlineable(.leaf(.text("Hi"))))
        #expect(MockupFlowRouting.isInlineable(MockNode(kind: .vstack(
            alignment: nil,
            spacing: nil,
            children: [.leaf(.text("Hi"))]
        ))))
    }
}
