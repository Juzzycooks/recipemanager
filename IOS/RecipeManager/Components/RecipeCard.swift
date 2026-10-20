import SwiftUI

extension RecipeSummary {
    /// "30 min · ★ 4.5": what a card shows under the title.
    var cardMeta: String {
        var parts: [String] = []
        let time = cookTime.isEmpty ? prepTime : cookTime
        if !time.isEmpty { parts.append(time) }
        if let avgRating { parts.append("★ " + String(format: "%.1f", avgRating)) }
        return parts.joined(separator: " • ")
    }
}

/// Recipe tile for carousels and grids. Sizing comes from the parent (use `.frame(width:)` in carousels).
struct RecipeCard: View {
    let recipe: RecipeSummary
    let onFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecipeImage(path: recipe.thumbUrl, title: recipe.title, id: recipe.id)
                .aspectRatio(4 / 3, contentMode: .fit)
                .accessibilityHidden(true)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(recipe.title).font(AppTypography.cardTitle).foregroundStyle(AppColors.textPrimary)
                        .lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading)
                    Text(recipe.cardMeta.isEmpty ? " " : recipe.cardMeta).font(AppTypography.meta)
                        .foregroundStyle(AppColors.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                // The heart takes 32pt of the layout but its tappable square is the full 44pt (it spills into the
                // padding), and as the front-most button it wins those taps from the card's link.
                FavoriteButton(isFavorite: recipe.isFavorite, size: 16, action: onFavorite)
                    .frame(width: Size.tap, height: Size.tap).padding(-(Size.tap - 32) / 2)
                    .padding(.trailing, -Spacing.xxs)
            }
            .padding(.horizontal, Spacing.s).padding(.vertical, Spacing.s)
        }
        .background(AppColors.card, in: RoundedRectangle(cornerRadius: Radius.card))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(AppColors.separator, lineWidth: 1))
        .shadow(color: AppColors.textPrimary.opacity(0.05), radius: 1.5, y: 1)
        .accessibilityElement(children: .contain)
    }
}

/// A horizontal row of recipe cards (Home "Quick Picks").
struct RecipeCarousel: View {
    let recipes: [RecipeSummary]
    let onFavorite: (RecipeSummary) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: Spacing.s) {
                ForEach(recipes) { recipe in
                    NavigationLink(value: AppRoute.recipe(recipe.id)) {
                        RecipeCard(recipe: recipe) { onFavorite(recipe) }.frame(width: 172)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.screen)
        }
    }
}
