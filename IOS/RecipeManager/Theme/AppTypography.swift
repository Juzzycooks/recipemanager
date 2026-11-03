import SwiftUI
import UIKit

/// Two voices, as on the web: Alegreya (bundled, Resources/Fonts) for what is read (titles, recipe text, notes, step
/// numerals), San Francisco for what is pressed (buttons, tabs, labels, inputs). Every style is relative to a system
/// text style, so Dynamic Type scales the serif too. Alegreya sets small on the body, so its sizes sit a point or two
/// above the system style they follow.
enum AppTypography {
    /// PostScript names of the bundled Alegreya files (see UIAppFonts in Info.plist).
    enum Face {
        static let regular = "Alegreya-Regular"
        static let medium = "Alegreya-Medium"
        static let bold = "Alegreya-Bold"
        static let mediumItalic = "Alegreya-MediumItalic"
        static let boldItalic = "Alegreya-BoldItalic"
    }

    static let largeTitle = Font.custom(Face.bold, size: 34, relativeTo: .largeTitle)
    static let title = Font.custom(Face.bold, size: 29, relativeTo: .title)
    static let title2 = Font.custom(Face.bold, size: 23, relativeTo: .title2)
    static let title3 = Font.custom(Face.bold, size: 21, relativeTo: .title3)
    static let cardTitle = Font.custom(Face.bold, size: 18, relativeTo: .headline)
    /// Ingredient and method text.
    static let reading = Font.custom(Face.regular, size: 19, relativeTo: .body)
    static let readingLarge = Font.custom(Face.regular, size: 22, relativeTo: .title3)
    /// The lede under a title and other notes in the margin.
    static let note = Font.custom(Face.mediumItalic, size: 19, relativeTo: .body)
    /// Section headings inside an ingredient or step list (set in the accent).
    static let sectionHeading = Font.custom(Face.boldItalic, size: 19, relativeTo: .body)
    /// Step numbers in the method list.
    static let stepNumeral = Font.custom(Face.boldItalic, size: 26, relativeTo: .title2)
    /// The big step number in cook mode.
    static let cookNumeral = Font.custom(Face.boldItalic, size: 72, relativeTo: .largeTitle)
    /// Photo-less recipe letter. Sized from the tile (it is a picture, hidden from VoiceOver), not from Dynamic Type.
    static func monogram(size: CGFloat) -> Font { Font.custom(Face.boldItalic, fixedSize: size) }

    static let meta = Font.caption
    static let label = Font.subheadline.weight(.medium)

    /// Alegreya navigation titles without touching every screen. UIFontMetrics scales them with Dynamic Type;
    /// UIKit reads the appearance when a bar is created, so it is rebuilt when the text size changes.
    @MainActor static func configureNavigationBar() {
        applyNavigationBarAppearance()
        // A static method, not a local function, so the Sendable observer closure captures nothing.
        NotificationCenter.default.addObserver(forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppTypography.applyNavigationBarAppearance() }
        }

        // Segmented controls: quiet track, accent-fill selection with white text.
        AppTheme.applyUIKitAppearance(ThemeStore.shared.theme)
    }

    @MainActor private static func applyNavigationBarAppearance() {
        func alegreya(_ name: String, _ size: CGFloat, _ style: UIFont.TextStyle) -> UIFont {
            let base = UIFont(name: name, size: size) ?? .preferredFont(forTextStyle: style)
            return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
        }
        let ink = UIColor(named: "TextPrimary") ?? .label
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.largeTitleTextAttributes = [.font: alegreya(Face.bold, 34, .largeTitle), .foregroundColor: ink]
        appearance.titleTextAttributes = [.font: alegreya(Face.bold, 19, .headline), .foregroundColor: ink]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
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
