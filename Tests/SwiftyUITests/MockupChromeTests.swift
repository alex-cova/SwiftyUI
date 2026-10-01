import Foundation
import Testing
@testable import SwiftyUI

struct MockupChromeTests {
    @Test func phoneAndTabletShowAStatusBar() {
        #expect(MockupChrome.phone.showsStatusBar)
        #expect(MockupChrome.tablet.showsStatusBar)
        #expect(!MockupChrome.mac.showsStatusBar)
        #expect(!MockupChrome.watch.showsStatusBar)
    }

    @Test func iOSChromeIsEverythingButMac() {
        #expect(!MockupChrome.mac.usesIOSChrome)
        #expect(MockupChrome.phone.usesIOSChrome)
        #expect(MockupChrome.tablet.usesIOSChrome)
        #expect(MockupChrome.watch.usesIOSChrome)
    }

    @Test func iOSTokenTableMatchesPublishedHIGAndUIKit() {
        #expect(MockupIOSTokens.switchWidth == 51)
        #expect(MockupIOSTokens.switchHeight == 31)
        #expect(MockupIOSTokens.switchKnob == 27)
        #expect(MockupIOSTokens.rowHeight == 44)
        #expect(MockupIOSTokens.navBarHeight == 44)
        #expect(MockupIOSTokens.tabBarHeight == 49)
        #expect(MockupIOSTokens.tabIconSize == 25)
        #expect(MockupIOSTokens.sliderHeight == 31)
        #expect(MockupIOSTokens.sliderTrackHeight == 4)
        #expect(MockupIOSTokens.sliderThumb == 28)
        #expect(MockupIOSTokens.stepperWidth == 94)
        #expect(MockupIOSTokens.stepperHeight == 32)
        #expect(MockupIOSTokens.progressHeight == 4)
        #expect(MockupIOSTokens.segmentedHeight == 32)
        #expect(MockupIOSTokens.bodySize == 17)

        #expect(MockupIOSTokens.systemGreenRGB == MockupIOSRGB(red: 52, green: 199, blue: 89))
        #expect(MockupIOSTokens.systemBlueRGB == MockupIOSRGB(red: 0, green: 122, blue: 255))
        #expect(MockupIOSTokens.groupedBackgroundLight == MockupIOSRGB(red: 242, green: 242, blue: 247))
        #expect(MockupIOSTokens.groupedBackgroundDark == MockupIOSRGB(red: 0, green: 0, blue: 0))
        #expect(MockupIOSTokens.rowBackgroundLight == MockupIOSRGB(red: 255, green: 255, blue: 255))
        #expect(MockupIOSTokens.rowBackgroundDark == MockupIOSRGB(red: 28, green: 28, blue: 30))
    }

    @Test func phoneAndTabletChromeConsumeTheTokenTable() {
        #expect(MockupChrome.phone.rowMinHeight == MockupIOSTokens.rowHeight)
        #expect(MockupChrome.tablet.rowMinHeight == MockupIOSTokens.rowHeight)
        #expect(MockupChrome.phone.listMargin == MockupIOSTokens.listMargin)
        #expect(MockupChrome.tablet.listMargin == MockupIOSTokens.listMargin)
        #expect(MockupChrome.phone.sectionRadius == MockupIOSTokens.listSectionRadius)
        #expect(MockupChrome.tablet.sectionRadius == MockupIOSTokens.listSectionRadius)
        #expect(MockupChrome.mac.usesIOSChrome == false)
    }

    @Test func systemGreenColorIsBuiltFromTheRGBTable() {
        #expect(MockupIOSTokens.systemGreenRGB.red == 52)
        #expect(MockupIOSTokens.systemGreenRGB.green == 199)
        #expect(MockupIOSTokens.systemGreenRGB.blue == 89)
        #expect(MockupIOSTokens.systemGreenRGB == MockupIOSRGB(red: 52, green: 199, blue: 89))
    }
}

struct MockupIOSListGroupingTests {
    @Test func consecutiveLooseRowsBecomeOneUntitledSection() {
        let children = [
            MockNode.leaf(.text("A")),
            MockNode.leaf(.text("B")),
        ]
        let blocks = MockupIOSListGrouping.blocks(from: children)
        #expect(blocks.count == 1)
        #expect(blocks[0].header == nil)
        #expect(blocks[0].rows.count == 2)
    }

    @Test func explicitSectionsStaySeparate() {
        let children = [
            MockNode(kind: .section(header: "Account", children: [
                MockNode.leaf(.label(title: "Apple ID", systemImage: "person.circle")),
            ])),
            MockNode(kind: .section(header: "General", children: [
                MockNode.leaf(.label(title: "Appearance", systemImage: "paintbrush")),
            ])),
        ]
        let blocks = MockupIOSListGrouping.blocks(from: children)
        #expect(blocks.count == 2)
        #expect(blocks[0].header == "Account")
        #expect(blocks[1].header == "General")
        #expect(blocks[0].rows.count == 1)
    }

    @Test func forEachExpandsIntoRows() {
        let children = [
            MockNode(kind: .forEach(count: 3, child: MockNode.leaf(.text("Item")))),
        ]
        let blocks = MockupIOSListGrouping.blocks(from: children)
        #expect(blocks.count == 1)
        #expect(blocks[0].rows.count == 3)
        #expect(blocks[0].rows.allSatisfy { $0.kind == .text("Item") })
    }

    @Test func groupFlattensIntoTheSurroundingSection() {
        let children = [
            MockNode(kind: .group(children: [
                MockNode.leaf(.text("One")),
                MockNode.leaf(.text("Two")),
            ])),
        ]
        let rows = MockupIOSListGrouping.flatten(children)
        #expect(rows.count == 2)
    }

    @Test func labelsShowADisclosureChevronAndTogglesDoNot() {
        #expect(MockNode.Kind.label(title: "Wi-Fi", systemImage: "wifi").showsIOSDisclosureChevron)
        #expect(MockNode.Kind.text("Hello").showsIOSDisclosureChevron)
        #expect(MockNode.Kind.navigationLink(title: "Settings", destination: nil, targetName: "SettingsView").showsIOSDisclosureChevron)
        #expect(!MockNode.Kind.toggle(title: "Wi-Fi", initialOn: true, editable: true).showsIOSDisclosureChevron)
        #expect(!MockNode.Kind.textField(placeholder: "Name", initialText: "", editable: true).showsIOSDisclosureChevron)
    }
}
