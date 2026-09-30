import SwiftUI

/// Semantic colours. Every value lives in Assets.xcassets with a light and a dark variant,
/// so screens never use raw hex literals.
enum AppColors {
    static let background = Color("Background")
    static let surface = Color("Surface")          // fields, chips, quiet fills
    static let card = Color("Card")                // raised content
    static let separator = Color("Separator")
    static let primary = Color("PrimaryGreen")
    static let secondary = Color("SecondaryGreen")
    static let onPrimary = Color("OnPrimary")
    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")
    static let favorite = Color("Favorite")
    static let star = Color("StarGold")
    static let danger = Color("Danger")

    /// Wash + ink pairs for recipes without a photo (letter tiles).
    static let tiles: [(wash: Color, ink: Color)] = [
        (Color("TileSage"), Color("TileSageInk")),
        (Color("TileSand"), Color("TileSandInk")),
        (Color("TileClay"), Color("TileClayInk")),
        (Color("TileStone"), Color("TileStoneInk")),
    ]
}
