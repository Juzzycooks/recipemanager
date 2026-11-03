import SwiftUI
import UIKit
import WidgetKit

/// The app's look, mirrored for the widgets: colours from this extension's asset catalog (copies of the app's sets),
/// Alegreya (two faces bundled in the extension, see UIAppFonts in project.yml) for what is read.
enum WidgetColors {
    static let background = Color("Background")
    static let card = Color("Card")
    static let ink = Color("TextPrimary")
    static let secondary = Color("TextSecondary")
    static let tertiary = Color("TextTertiary")
    static let accent = Color("AccentColor")
    static let hairline = Color("Hairline")
    static let tiles: [(wash: Color, ink: Color)] = [
        (Color("TileTerracotta"), Color("TileTerracottaInk")),
        (Color("TileHerb"), Color("TileHerbInk")),
        (Color("TileButter"), Color("TileButterInk")),
        (Color("TileSlate"), Color("TileSlateInk")),
    ]
}

enum WidgetFonts {
    static func title(_ size: CGFloat, relativeTo style: Font.TextStyle = .headline) -> Font {
        Font.custom("Alegreya-Bold", size: size, relativeTo: style)
    }
    static func monogram(_ size: CGFloat) -> Font { Font.custom("Alegreya-BoldItalic", fixedSize: size) }
    /// Small capitals-style label above a title ("TONIGHT").
    static let eyebrow = Font.caption2.weight(.semibold)
}

/// The recipe's first letter on one of the four tints: the app's photo-less tile (`RecipeImage`), mirrored.
struct LetterTile: View {
    let title: String
    let id: Int

    var body: some View {
        let tint = WidgetColors.tiles[abs(id) % WidgetColors.tiles.count]
        tint.wash.overlay {
            GeometryReader { geo in
                Text(String(title.trimmingCharacters(in: .whitespaces).first ?? "?"))
                    .font(WidgetFonts.monogram(min(max(18, min(geo.size.width, geo.size.height) * 0.5), 90)))
                    .foregroundStyle(tint.ink)
                    .widgetAccentable()
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A meal's photo, or its letter tile. Photos turn monochrome-accented in the tinted Home Screen modes.
struct MealPicture: View {
    let meal: WidgetMeal
    let image: Data?

    var body: some View {
        Color.clear
            .overlay {
                if let image, let picture = UIImage(data: image) {
                    Image(uiImage: picture).resizable().widgetAccentedRenderingMode(.accentedDesaturated).scaledToFill()
                } else {
                    LetterTile(title: meal.title, id: meal.recipeID)
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// Signed out, or an unsigned build that can't read the keychain.
struct SignInPrompt: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "person.crop.circle").font(.title3).foregroundStyle(WidgetColors.accent).widgetAccentable()
                .accessibilityHidden(true)
            Text("Sign in to Spoonmate").font(WidgetFonts.title(16)).foregroundStyle(WidgetColors.ink)
            Text("Open the app to see your plan and list here.").font(.caption).foregroundStyle(WidgetColors.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
