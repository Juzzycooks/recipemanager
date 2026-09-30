import SwiftUI
import UIKit

/// Editorial serif for headings and recipe reading, system sans for controls. All text styles, so Dynamic Type works.
enum AppTypography {
    static let largeTitle = Font.system(.largeTitle, design: .serif, weight: .regular)
    static let title = Font.system(.title, design: .serif, weight: .semibold)
    static let title2 = Font.system(.title2, design: .serif, weight: .semibold)
    static let title3 = Font.system(.title3, design: .serif, weight: .semibold)
    static let cardTitle = Font.system(.subheadline, design: .serif, weight: .semibold)
    static let reading = Font.system(.body, design: .serif)
    static let readingLarge = Font.system(.title3, design: .serif)
    static let meta = Font.caption
    static let label = Font.subheadline.weight(.medium)

    /// Serif navigation titles without touching every screen.
    @MainActor static func configureNavigationBar() {
        func serif(_ style: UIFont.TextStyle, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.preferredFont(forTextStyle: style)
            let descriptor = base.fontDescriptor.withDesign(.serif)?.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
            return descriptor.map { UIFont(descriptor: $0, size: base.pointSize) } ?? base
        }
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.largeTitleTextAttributes = [.font: serif(.largeTitle, .semibold), .foregroundColor: UIColor(AppColors.textPrimary)]
        appearance.titleTextAttributes = [.font: serif(.headline, .semibold), .foregroundColor: UIColor(AppColors.textPrimary)]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance

        // Segmented controls: quiet track, green selection (as in the design).
        let segmented = UISegmentedControl.appearance()
        segmented.backgroundColor = UIColor(AppColors.surface)
        segmented.selectedSegmentTintColor = ThemeStore.shared.theme.uiColor
        segmented.setTitleTextAttributes([.foregroundColor: UIColor(AppColors.onPrimary)], for: .selected)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor(AppColors.textPrimary)], for: .normal)
    }
}

extension Date {
    /// `yyyy-MM-dd` in the user's calendar, as the meal-plan API expects.
    var apiDay: String { Self.dayFormatter.string(from: self) }
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func fromAPIDay(_ text: String) -> Date? { dayFormatter.date(from: text) }
}
