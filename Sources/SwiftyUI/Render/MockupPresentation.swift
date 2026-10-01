import SwiftUI

/// Sheet / full-screen cover overlay drawn inside the device screen, below the status bar.
/// Owned by `MockupFlowSession` so a tap on any node can present without threading bindings
/// through the tree.
public struct MockupPresentationOverlay: View {
    @Bindable public var flow: MockupFlowSession
    public var colorScheme: ColorScheme
    public var usesIOSChrome: Bool

    public init(flow: MockupFlowSession, colorScheme: ColorScheme, usesIOSChrome: Bool) {
        self.flow = flow
        self.colorScheme = colorScheme
        self.usesIOSChrome = usesIOSChrome
    }

    @ViewBuilder
    private func sheetCard(_ node: MockNode) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 4)
            MockNodeView(node: node)
                .padding(.horizontal, usesIOSChrome ? 16 : RenderSpacing.md)
                .padding(.bottom, usesIOSChrome ? 16 : RenderSpacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .background(MockupIOSTokens.rowBackground(colorScheme), in: UnevenRoundedRectangle(
            topLeadingRadius: 16,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 16
        ))
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        ZStack {
            if case let .sheet(node, cover, _) = flow.presented {
                GeometryReader { geo in
                    ZStack(alignment: cover ? .center : .bottom) {
                        Color.black.opacity(cover ? 0.45 : 0.32)
                            .onTapGesture { flow.dismiss() }
                            .transition(.opacity)

                        Group {
                            if cover {
                                coverCard(node)
                            } else {
                                sheetCard(node)
                                    .frame(height: geo.size.height * 0.72)
                            }
                        }
                        .transition(
                            (cover ? MockupRouteAnimation.cover : .sheet)
                                .transition(reduceMotion: reduceMotion)
                        )
                    }
                }
                .transition(
                    (cover ? MockupRouteAnimation.cover : .sheet)
                        .transition(reduceMotion: reduceMotion)
                )
            }
        }
        .renderAnimation(RenderMotion.emphasized, value: presentedIdentity)
    }

    private var presentedIdentity: String {
        switch flow.presented {
        case let .sheet(_, cover, name): "\(cover ? "c" : "s"):\(name ?? "")"
        case nil: "none"
        }
    }

    private func coverCard(_ node: MockNode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("Close", systemImage: "xmark.circle.fill") {
                    flow.dismiss()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.title2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: MockupIOSTokens.navBarHeight)

            MockNodeView(node: node)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MockupIOSTokens.groupedBackground(colorScheme))
    }
}
