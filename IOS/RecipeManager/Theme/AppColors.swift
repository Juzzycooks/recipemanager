import SwiftUI

/// Semantic colours. Every value lives in Assets.xcassets with a light and a dark variant,
/// so screens never use raw hex literals.
enum AppColors {
    static let background = Color("Background")    // flour; chalkboard in dark mode
    static let surface = Color("Surface")          // fields, chips, quiet fills
    static let card = Color("Card")                // card stock
    static let separator = Color("Hairline")       // card edges
    static let hairlineLight = Color("HairlineLight")
    /// Pale blue ruled lines between ingredient and step rows.
    static let rule = Color("RuleBlue")
    /// Brand colours come from the chosen `AppTheme`. They read an @Observable store, so views that use them
    /// update the moment the theme changes.
    /// `primary` is for text, lines and marks. `primaryFill` is the only accent that may fill a surface carrying
    /// white (`onPrimary`) text: in light mode they match, in dark mode the fill is deeper (the Accent-Solid rule).
    @MainActor static var primary: Color { ThemeStore.shared.theme.tint }
    @MainActor static var primaryFill: Color { ThemeStore.shared.theme.fill }
    /// Kept for older call sites: the same as `primary` (one accent, no lighter second tint).
    @MainActor static var secondary: Color { primary }
    /// Quiet emphasis behind accent marks (selection, badges, the Add sheet icons).
    static let accentWash = Color("AccentWash")
    static let onPrimary = Color("OnPrimary")
    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")
    static let textTertiary = Color("TextTertiary")
    /// Favourites and stars are marks the cook makes, so they take the accent (the Red-Pen Rule), not their own hues.
    @MainActor static var favorite: Color { primary }
    @MainActor static var star: Color { primary }
    static let success = Color("Success")
    /// Destructive actions and errors only.
    static let danger = Color("Danger")

    /// Wash + ink pairs for recipes without a photo (letter tiles), the web's four monogram tints.
    static let tiles: [(wash: Color, ink: Color)] = [
        (Color("TileTerracotta"), Color("TileTerracottaInk")),
        (Color("TileHerb"), Color("TileHerbInk")),
        (Color("TileButter"), Color("TileButterInk")),
        (Color("TileSlate"), Color("TileSlateInk")),
    ]
}
