import Observation
import SwiftUI
import UIKit

/// Selectable colour themes. The chosen theme becomes the app's `tint`, and `AppColors.primary` /
/// `AppColors.primaryFill` follow it, so changing it recolours every screen immediately.
/// Terracotta (the web's red pen) is the default; the others stay selectable.
enum AppTheme: String, CaseIterable, Identifiable {
    case terracotta, forest, ocean, plum, slate

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

    /// Text-and-line accent, (light appearance, dark appearance). Dark values are lighter so they read on the chalkboard.
    private var hex: (light: UInt32, dark: UInt32) {
        switch self {
        case .terracotta: (0xB83A12, 0xF0784A)   // the web app's red pen; ember on the chalkboard
        case .forest: (0x274E3B, 0x7FB396)
        case .ocean: (0x1F4E79, 0x7FB0DC)
        case .plum: (0x5B2A6B, 0xC89ADB)
        case .slate: (0x33404D, 0xAEBBC8)
        }
    }

    /// Fill behind white text. Light mode reuses the accent; dark mode needs a deeper value so white text still reads
    /// (terracotta's is the web's ember fill, 4.55:1 with white: the floor, so don't lighten it).
    private var fillHex: (light: UInt32, dark: UInt32) {
        switch self {
        case .terracotta: (0xB83A12, 0xC8501A)
        case .forest: (0x274E3B, 0x2F6B4F)
        case .ocean: (0x1F4E79, 0x2A6496)
        case .plum: (0x5B2A6B, 0x7A3D8F)
        case .slate: (0x33404D, 0x4A5A6A)
        }
    }

    private static func dynamic(_ hex: (light: UInt32, dark: UInt32)) -> UIColor {
        UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? hex.dark : hex.light
            return UIColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                           blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        }
    }

    var uiColor: UIColor { Self.dynamic(hex) }
    var fillUIColor: UIColor { Self.dynamic(fillHex) }

    var tint: Color { Color(uiColor: uiColor) }
    var fill: Color { Color(uiColor: fillUIColor) }

    /// UIKit controls that SwiftUI can't tint (segmented controls) read this; call after the theme changes.
    /// The selected segment is a fill carrying white text, so it takes the fill colour.
    @MainActor static func applyUIKitAppearance(_ theme: AppTheme) {
        let segmented = UISegmentedControl.appearance()
        segmented.backgroundColor = UIColor(named: "Surface")
        segmented.selectedSegmentTintColor = theme.fillUIColor
        segmented.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor(named: "TextPrimary") ?? .label], for: .normal)
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
        theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: AppTheme.storageKey) ?? "") ?? .terracotta
        AppTheme.applyUIKitAppearance(theme)
    }
}
