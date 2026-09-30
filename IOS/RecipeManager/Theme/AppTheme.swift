import Observation
import SwiftUI
import UIKit

/// Selectable colour themes. The chosen theme becomes the app's `tint`, and `AppColors.primary` /
/// `AppColors.secondary` follow the tint, so changing it recolours every screen immediately.
enum AppTheme: String, CaseIterable, Identifiable {
    case forest, terracotta, ocean, plum, slate

    static let storageKey = "colorTheme"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .forest: "Forest"
        case .terracotta: "Terracotta"
        case .ocean: "Ocean"
        case .plum: "Plum"
        case .slate: "Slate"
        }
    }

    /// (light appearance, dark appearance) hex values. Dark values are lighter so they read on the dark surface.
    private var hex: (light: UInt32, dark: UInt32) {
        switch self {
        case .forest: (0x274E3B, 0x7FB396)
        case .terracotta: (0xB83A12, 0xF0784A)   // the web app's red-pen accent
        case .ocean: (0x1F4E79, 0x7FB0DC)
        case .plum: (0x5B2A6B, 0xC89ADB)
        case .slate: (0x33404D, 0xAEBBC8)
        }
    }

    var uiColor: UIColor {
        let hex = hex
        return UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? hex.dark : hex.light
            return UIColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                           blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        }
    }

    var tint: Color { Color(uiColor: uiColor) }

    /// UIKit controls that SwiftUI can't tint (segmented controls) read this; call after the theme changes.
    @MainActor static func applyUIKitAppearance(_ theme: AppTheme) {
        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = theme.uiColor
    }
}

/// The chosen theme, observable so every view that reads `AppColors.primary` re-renders when it changes.
/// (`Color.accentColor` does not follow `.tint`, so the brand colour is read from here instead.)
@MainActor @Observable
final class ThemeStore {
    static let shared = ThemeStore()

    var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: AppTheme.storageKey)
            AppTheme.applyUIKitAppearance(theme)
        }
    }

    private init() {
        theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: AppTheme.storageKey) ?? "") ?? .forest
        AppTheme.applyUIKitAppearance(theme)
    }
}
