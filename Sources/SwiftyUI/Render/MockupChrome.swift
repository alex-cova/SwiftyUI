import Foundation
import SwiftUI

/// Which platform chrome the renderer should imitate. Driven by the device picker: freeform
/// stays honest Mac SwiftUI; phone / tablet / watch swap in iOS-looking lists, switches, and
/// a status bar so the bezel is not a Mac window wearing a phone case.
public nonisolated enum MockupChrome: String, Sendable, Equatable {
    case mac
    case phone
    case tablet
    case watch

    /// Lists, forms, toggles, fields, buttons, pickers, sliders, steppers, progress, nav, and
    /// tabs use the iOS skins from `MockupIOSTokens`.
    public var usesIOSChrome: Bool { self != .mac }

    public var showsStatusBar: Bool {
        switch self {
        case .phone, .tablet: true
        case .mac, .watch: false
        }
    }

    public var listMargin: CGFloat {
        switch self {
        case .watch: 8
        default: MockupIOSTokens.listMargin
        }
    }

    public var rowMinHeight: CGFloat {
        switch self {
        case .watch: 32
        default: MockupIOSTokens.rowHeight
        }
    }

    public var sectionRadius: CGFloat {
        switch self {
        case .watch: 8
        default: MockupIOSTokens.listSectionRadius
        }
    }
}

public extension EnvironmentValues {
    @Entry var mockupChrome: MockupChrome = .mac
    @Entry var mockupInListRow: Bool = false
    @Entry var mockupSafeArea: MockupSafeArea = .zero
}
