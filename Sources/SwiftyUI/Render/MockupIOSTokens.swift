import SwiftUI

/// 8-bit sRGB triple matching UIKit's light-mode `UIColor` components. Views convert with
/// `color`; tests assert the integers so a SwiftUI `Color` identity check is not required.
public nonisolated struct MockupIOSRGB: Equatable, Sendable {
    public var red: Int
    public var green: Int
    public var blue: Int

    public var color: Color {
        Color(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255
        )
    }
}

/// iOS system colours and control metrics, used only when `MockupChrome` is not `.mac`.
/// These are the UIKit grouped-background / switch-green / HIG control sizes — not Hextech
/// chrome — so a phone mock reads as iOS instead of a Mac `List` inside a bezel.
public nonisolated enum MockupIOSTokens {
    // MARK: System colours (UIKit sRGB)

    /// `UIColor.systemGreen` (light).
    public static let systemGreenRGB = MockupIOSRGB(red: 52, green: 199, blue: 89)
    /// `UIColor.systemBlue` (light).
    public static let systemBlueRGB = MockupIOSRGB(red: 0, green: 122, blue: 255)
    /// `UIColor.systemBlue` (dark).
    public static let systemBlueDarkRGB = MockupIOSRGB(red: 10, green: 132, blue: 255)
    /// `UIColor.systemGray`.
    public static let systemGrayRGB = MockupIOSRGB(red: 142, green: 142, blue: 147)
    /// `UIColor.systemGroupedBackground` (light).
    public static let groupedBackgroundLight = MockupIOSRGB(red: 242, green: 242, blue: 247)
    /// `UIColor.systemGroupedBackground` (dark).
    public static let groupedBackgroundDark = MockupIOSRGB(red: 0, green: 0, blue: 0)
    /// `UIColor.secondarySystemGroupedBackground` (light).
    public static let rowBackgroundLight = MockupIOSRGB(red: 255, green: 255, blue: 255)
    /// `UIColor.secondarySystemGroupedBackground` (dark).
    public static let rowBackgroundDark = MockupIOSRGB(red: 28, green: 28, blue: 30)
    /// `UIColor.systemGray4` (light) — stepper fill.
    public static let systemGray4Light = MockupIOSRGB(red: 209, green: 209, blue: 214)
    /// `UIColor.systemGray4` (dark).
    public static let systemGray4Dark = MockupIOSRGB(red: 58, green: 58, blue: 60)
    /// `UIColor.systemGray5` (light) — slider / progress track.
    public static let systemGray5Light = MockupIOSRGB(red: 229, green: 229, blue: 234)
    /// `UIColor.systemGray5` (dark).
    public static let systemGray5Dark = MockupIOSRGB(red: 44, green: 44, blue: 46)
    /// `UIColor.systemGray6` (light) — segmented track, standalone field fill.
    public static let systemGray6Light = MockupIOSRGB(red: 242, green: 242, blue: 247)
    /// `UIColor.systemGray6` (dark).
    public static let systemGray6Dark = MockupIOSRGB(red: 28, green: 28, blue: 30)
    /// UISwitch off-track (light).
    public static let switchOffLight = MockupIOSRGB(red: 233, green: 233, blue: 234)
    /// UISwitch off-track (dark).
    public static let switchOffDark = MockupIOSRGB(red: 57, green: 57, blue: 62)

    public static var systemGreen: Color { systemGreenRGB.color }

    public static func systemBlue(_ scheme: ColorScheme) -> Color {
        (scheme == .dark ? systemBlueDarkRGB : systemBlueRGB).color
    }

    public static func groupedBackground(_ scheme: ColorScheme) -> Color {
        (scheme == .dark ? groupedBackgroundDark : groupedBackgroundLight).color
    }

    public static func rowBackground(_ scheme: ColorScheme) -> Color {
        (scheme == .dark ? rowBackgroundDark : rowBackgroundLight).color
    }

    public static func systemGray4(_ scheme: ColorScheme) -> Color {
        (scheme == .dark ? systemGray4Dark : systemGray4Light).color
    }

    public static func systemGray5(_ scheme: ColorScheme) -> Color {
        (scheme == .dark ? systemGray5Dark : systemGray5Light).color
    }

    public static func systemGray6(_ scheme: ColorScheme) -> Color {
        (scheme == .dark ? systemGray6Dark : systemGray6Light).color
    }

    public static func switchOff(_ scheme: ColorScheme) -> Color {
        (scheme == .dark ? switchOffDark : switchOffLight).color
    }

    public static func barBackground(_ scheme: ColorScheme) -> Color {
        groupedBackground(scheme)
    }

    public static func separator(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 84 / 255, green: 84 / 255, blue: 88 / 255).opacity(0.6)
            : Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.29)
    }

    // MARK: HIG / UIKit control metrics (points)

    public static let switchWidth: CGFloat = 51
    public static let switchHeight: CGFloat = 31
    public static let switchKnob: CGFloat = 27
    public static let switchKnobPadding: CGFloat = 2

    public static let rowHeight: CGFloat = 44
    public static let navBarHeight: CGFloat = 44
    public static let tabBarHeight: CGFloat = 49
    public static let tabIconSize: CGFloat = 25
    public static let tabLabelSize: CGFloat = 10

    public static let listMargin: CGFloat = 16
    public static let listRowInset: CGFloat = 16
    public static let listSectionRadius: CGFloat = 10
    public static let listHeaderSize: CGFloat = 13

    public static let searchHeight: CGFloat = 36
    public static let largeTitleSize: CGFloat = 34
    public static let statusTimeSize: CGFloat = 17
    public static let bodySize: CGFloat = 17
    public static let backChevronSize: CGFloat = 17

    public static let sliderHeight: CGFloat = 31
    public static let sliderTrackHeight: CGFloat = 4
    public static let sliderThumb: CGFloat = 28

    public static let stepperWidth: CGFloat = 94
    public static let stepperHeight: CGFloat = 32
    public static let stepperCornerRadius: CGFloat = 8

    public static let progressHeight: CGFloat = 4
    public static let activityIndicatorSize: CGFloat = 20

    public static let segmentedHeight: CGFloat = 32
    public static let segmentedCornerRadius: CGFloat = 9

    public static let fieldCornerRadius: CGFloat = 10
    public static let hairlineHeight: CGFloat = 1 / 3
}
