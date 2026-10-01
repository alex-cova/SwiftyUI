import SwiftUI

/// Inset-grouped iOS list: grouped background, rounded section cards, 44pt rows.
/// Used when `mockupChrome.usesIOSChrome` so a `List` inside an iPhone bezel is not a Mac table.
public struct MockupIOSList: View {
    public let children: [MockNode]
    @Environment(\.mockupChrome) private var chrome
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        let blocks = MockupIOSListGrouping.blocks(from: children)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    MockupIOSSection(header: block.header, rows: block.rows)
                }
            }
            .padding(.horizontal, chrome.listMargin)
            .padding(.bottom, chrome.listMargin)
        }
        .scrollIndicators(.hidden)
        .background(MockupIOSTokens.groupedBackground(colorScheme))
    }
}

public struct MockupIOSSection: View {
    public var header: String?
    public var rows: [MockNode]
    @Environment(\.mockupChrome) private var chrome
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header, !header.isEmpty {
                Text(header)
                    .font(.system(size: MockupIOSTokens.listHeaderSize, weight: .regular))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.leading, MockupIOSTokens.listRowInset)
                    .padding(.bottom, 8)
                    .padding(.top, 24)
            } else {
                Spacer().frame(height: MockupIOSTokens.listMargin)
            }

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    MockupIOSRow(node: row)
                    if index < rows.count - 1 {
                        MockupIOSHairline()
                            .padding(.leading, MockupIOSTokens.listRowInset)
                    }
                }
            }
            .background(MockupIOSTokens.rowBackground(colorScheme), in: .rect(cornerRadius: chrome.sectionRadius))
        }
    }
}

private struct MockupIOSRow: View {
    let node: MockNode
    @Environment(\.mockupChrome) private var chrome

    var body: some View {
        HStack(spacing: 8) {
            MockNodeView(node: node)
                .frame(maxWidth: .infinity, alignment: .leading)
            if node.kind.showsIOSDisclosureChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, MockupIOSTokens.listRowInset)
        .padding(.vertical, 6)
        .frame(minHeight: chrome.rowMinHeight)
        .contentShape(.rect)
        .environment(\.mockupInListRow, true)
    }
}
