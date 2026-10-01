import SwiftUI

/// iOS switch: 51×31 capsule, system green when on. Replaces macOS `Toggle` inside phone/tablet
/// chrome. Owns local state seeded from the source, same as `MockToggle`.
public struct MockupIOSSwitch: View {
    public let title: String
    public var editable: Bool = true
    @State private var isOn: Bool
    @Environment(\.colorScheme) private var colorScheme

    public init(title: String, initialOn: Bool, editable: Bool = true) {
        self.title = title
        self.editable = editable
        _isOn = State(initialValue: initialOn)
    }

    public var body: some View {
        HStack(spacing: 12) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: MockupIOSTokens.bodySize))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            switchTrack
        }
    }

    private var switchTrack: some View {
        Button(action: toggle) {
            Capsule()
                .fill(trackColor)
                .frame(width: MockupIOSTokens.switchWidth, height: MockupIOSTokens.switchHeight)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: MockupIOSTokens.switchKnob, height: MockupIOSTokens.switchKnob)
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                        .padding(MockupIOSTokens.switchKnobPadding)
                }
        }
        .buttonStyle(.plain)
        .disabled(!editable)
        .accessibilityLabel(title.isEmpty ? "Toggle" : title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }

    private var trackColor: Color {
        isOn ? MockupIOSTokens.systemGreen : MockupIOSTokens.switchOff(colorScheme)
    }

    private func toggle() {
        guard editable else { return }
        withAnimation(.easeInOut(duration: 0.15)) { isOn.toggle() }
    }
}

/// iOS text field: plain 17pt field on a gray-6 fill, or unadorned when already inside a list row.
public struct MockupIOSTextField: View {
    public let placeholder: String
    public var isSecure: Bool = false
    public var editable: Bool = true
    @State private var text: String
    @Environment(\.mockupInListRow) private var inRow
    @Environment(\.colorScheme) private var colorScheme

    public init(placeholder: String, initialText: String, isSecure: Bool = false, editable: Bool = true) {
        self.placeholder = placeholder
        self.isSecure = isSecure
        self.editable = editable
        _text = State(initialValue: initialText)
    }

    public var body: some View {
        field
            .font(.system(size: MockupIOSTokens.bodySize))
            .textFieldStyle(.plain)
            .disabled(!editable)
            .padding(.horizontal, inRow ? 0 : 12)
            .padding(.vertical, inRow ? 0 : 10)
            .background {
                if !inRow {
                    RoundedRectangle(cornerRadius: MockupIOSTokens.fieldCornerRadius, style: .continuous)
                        .fill(MockupIOSTokens.systemGray6(colorScheme))
                }
            }
    }

    @ViewBuilder
    private var field: some View {
        if isSecure {
            SecureField(placeholder, text: $text)
        } else {
            TextField(placeholder, text: $text)
        }
    }
}

/// Default iOS `Button`: 17pt systemBlue text, 44pt min height. Not a macOS bordered push button.
public struct MockupIOSButton<Label: View>: View {
    public var action: () -> Void
    @ViewBuilder public var label: () -> Label
    @Environment(\.mockupInListRow) private var inRow
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: MockupIOSTokens.bodySize))
                .foregroundStyle(MockupIOSTokens.systemBlue(colorScheme))
                .frame(maxWidth: inRow ? .infinity : nil, alignment: .leading)
                .frame(minHeight: inRow ? nil : MockupIOSTokens.rowHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// iOS `Picker`: menu row, segmented control, or inline checklist. Owns the seeded selection.
public struct MockupIOSPicker: View {
    public let title: String
    public let options: [String]
    public let style: MockPickerStyle
    @State private var selection: Int
    @Environment(\.mockupInListRow) private var inRow
    @Environment(\.colorScheme) private var colorScheme

    public init(title: String, options: [String], selectedIndex: Int, style: MockPickerStyle) {
        self.title = title
        self.options = options
        self.style = style
        _selection = State(initialValue: options.isEmpty ? 0 : max(0, min(selectedIndex, options.count - 1)))
    }

    public var body: some View {
        switch style {
        case .segmented:
            segmented
        case .inline, .wheel, .palette:
            inlineList
        case .automatic, .menu:
            menuRow
        }
    }

    private var selectedTitle: String {
        options.indices.contains(selection) ? options[selection] : ""
    }

    private var menuRow: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button(option) { selection = index }
            }
        } label: {
            HStack(spacing: 8) {
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: MockupIOSTokens.bodySize))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                }
                Text(selectedTitle)
                    .font(.system(size: MockupIOSTokens.bodySize))
                    .foregroundStyle(inRow ? Color.secondary : MockupIOSTokens.systemBlue(colorScheme))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: inRow ? nil : MockupIOSTokens.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(options.isEmpty)
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    selection = index
                } label: {
                    Text(option)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if index == selection {
                                RoundedRectangle(cornerRadius: MockupIOSTokens.segmentedCornerRadius - 2, style: .continuous)
                                    .fill(MockupIOSTokens.rowBackground(colorScheme))
                                    .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                                    .padding(2)
                            }
                        }
                }
                .buttonStyle(.plain)
                if index < options.count - 1, index != selection, index + 1 != selection {
                    Rectangle()
                        .fill(MockupIOSTokens.separator(colorScheme))
                        .frame(width: MockupIOSTokens.hairlineHeight, height: 16)
                }
            }
        }
        .frame(height: MockupIOSTokens.segmentedHeight)
        .background(MockupIOSTokens.systemGray6(colorScheme), in: .rect(cornerRadius: MockupIOSTokens.segmentedCornerRadius))
        .disabled(options.isEmpty)
        .accessibilityElement(children: .contain)
    }

    private var inlineList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: MockupIOSTokens.listHeaderSize))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
            }
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    selection = index
                } label: {
                    HStack {
                        Text(option)
                            .font(.system(size: MockupIOSTokens.bodySize))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if index == selection {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(MockupIOSTokens.systemBlue(colorScheme))
                        }
                    }
                    .frame(minHeight: MockupIOSTokens.rowHeight)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if index < options.count - 1 {
                    MockupIOSHairline()
                }
            }
        }
    }
}

/// iOS `UISlider`: 31pt control, 4pt track, 28pt thumb, systemBlue fill. Drag changes the seeded value.
public struct MockupIOSSlider: View {
    public let lowerBound: Double
    public let upperBound: Double
    @State private var value: Double
    @Environment(\.colorScheme) private var colorScheme

    public init(value: Double, lowerBound: Double, upperBound: Double) {
        self.lowerBound = lowerBound
        self.upperBound = max(upperBound, lowerBound + 0.0001)
        _value = State(initialValue: min(max(value, lowerBound), upperBound))
    }

    public var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let span = upperBound - lowerBound
            let fraction = CGFloat((value - lowerBound) / span)
            let thumbTravel = max(width - MockupIOSTokens.sliderThumb, 0)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(MockupIOSTokens.systemGray5(colorScheme))
                    .frame(height: MockupIOSTokens.sliderTrackHeight)
                Capsule()
                    .fill(MockupIOSTokens.systemBlue(colorScheme))
                    .frame(width: max(MockupIOSTokens.sliderThumb / 2, width * fraction), height: MockupIOSTokens.sliderTrackHeight)
                Circle()
                    .fill(Color.white)
                    .frame(width: MockupIOSTokens.sliderThumb, height: MockupIOSTokens.sliderThumb)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .offset(x: thumbTravel * fraction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let t = min(1, max(0, drag.location.x / width))
                    value = lowerBound + Double(t) * span
                }
            )
        }
        .frame(height: MockupIOSTokens.sliderHeight)
        .accessibilityValue(Text(value, format: .number.precision(.fractionLength(0...2))))
    }
}

/// iOS `UIStepper`: 94×32 rounded control with minus / plus. Title and current value sit to the left.
public struct MockupIOSStepper: View {
    public let title: String
    @State private var value: Double
    @Environment(\.colorScheme) private var colorScheme

    public init(title: String, value: Double) {
        self.title = title
        _value = State(initialValue: value)
    }

    public var body: some View {
        HStack(spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: MockupIOSTokens.bodySize))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(displayValue)
                .font(.system(size: MockupIOSTokens.bodySize).monospacedDigit())
                .foregroundStyle(.secondary)
            stepperControl
        }
    }

    private var displayValue: String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    private var stepperControl: some View {
        HStack(spacing: 0) {
            stepButton(systemImage: "minus") { value -= 1 }
            Rectangle()
                .fill(MockupIOSTokens.separator(colorScheme))
                .frame(width: MockupIOSTokens.hairlineHeight)
            stepButton(systemImage: "plus") { value += 1 }
        }
        .frame(width: MockupIOSTokens.stepperWidth, height: MockupIOSTokens.stepperHeight)
        .background(MockupIOSTokens.systemGray4(colorScheme), in: .rect(cornerRadius: MockupIOSTokens.stepperCornerRadius))
    }

    private func stepButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(systemImage == "plus" ? "Increment" : "Decrement")
    }
}

/// iOS `UIProgressView` (4pt capsule) or a 20pt circular activity indicator when indeterminate.
public struct MockupIOSProgress: View {
    public var title: String?
    public var value: Double?
    @Environment(\.colorScheme) private var colorScheme
    @State private var spinAngle: Double = 0

    public var body: some View {
        if let value {
            VStack(alignment: .leading, spacing: 8) {
                if let title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: MockupIOSTokens.listHeaderSize))
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(MockupIOSTokens.systemGray5(colorScheme))
                        Capsule()
                            .fill(MockupIOSTokens.systemBlue(colorScheme))
                            .frame(width: geo.size.width * CGFloat(min(1, max(0, value))))
                    }
                }
                .frame(height: MockupIOSTokens.progressHeight)
            }
        } else {
            HStack(spacing: 8) {
                spinner
                if let title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: MockupIOSTokens.bodySize))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var spinner: some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(
                MockupIOSTokens.systemGrayRGB.color,
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
            .frame(width: MockupIOSTokens.activityIndicatorSize, height: MockupIOSTokens.activityIndicatorSize)
            .rotationEffect(.degrees(spinAngle))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    spinAngle = 360
                }
            }
    }
}

/// 0.33pt separator matching `UIColor.separator`.
public struct MockupIOSHairline: View {
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        Rectangle()
            .fill(MockupIOSTokens.separator(colorScheme))
            .frame(height: MockupIOSTokens.hairlineHeight)
    }
}

/// iOS navigation back strip: 44pt, systemBlue chevron + title, grouped background, hairline.
public struct MockupIOSBackBar: View {
    public var title: String = "Back"
    public var action: () -> Void

    public init(title: String = "Back", action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: MockupIOSTokens.backChevronSize, weight: .semibold))
                    Text(title)
                        .font(.system(size: MockupIOSTokens.bodySize))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(MockupIOSTokens.systemBlue(colorScheme))
                .padding(.horizontal, 8)
                .frame(height: MockupIOSTokens.navBarHeight)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .background(MockupIOSTokens.barBackground(colorScheme))
            MockupIOSHairline()
        }
        .accessibilityLabel(title)
    }
}

/// iOS `UITabBar`: 49pt content row, 25pt glyphs, 10pt labels, systemBlue selected.
/// Extends its fill into the home-indicator inset so the bar meets the screen bottom.
public struct MockupIOSTabBar: View {
    public let tabs: [MockTab]
    @Binding public var selection: Int
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.mockupSafeArea) private var safeArea
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        VStack(spacing: 0) {
            MockupIOSHairline()
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    Button {
                        withAnimation(MockupRouteAnimation.tab.animation(reduceMotion: reduceMotion)) {
                            selection = index
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tab.systemImage ?? "circle.fill")
                                .font(.system(size: MockupIOSTokens.tabIconSize))
                            Text(tab.title)
                                .font(.system(size: MockupIOSTokens.tabLabelSize, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(
                            index == selection
                                ? MockupIOSTokens.systemBlue(colorScheme)
                                : MockupIOSTokens.systemGrayRGB.color
                        )
                        .padding(.top, 6)
                        .padding(.bottom, 1)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(index == selection ? [.isSelected] : [])
                }
            }
            .frame(height: MockupIOSTokens.tabBarHeight)
            .padding(.bottom, safeArea.bottom)
        }
        .background(MockupIOSTokens.barBackground(colorScheme))
        .padding(.bottom, -safeArea.bottom)
    }
}
