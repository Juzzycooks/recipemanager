import SwiftUI

struct CollectionCard: View {
    let collection: CollectionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecipeImage(path: collection.coverUrl, title: collection.name, id: collection.id)
                .aspectRatio(4 / 3, contentMode: .fit)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(collection.name).font(AppTypography.cardTitle).foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading)
                Text("\(collection.recipeCount) recipe\(collection.recipeCount == 1 ? "" : "s")")
                    .font(AppTypography.meta).foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.s)
        }
        .background(AppColors.card, in: RoundedRectangle(cornerRadius: Radius.card))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(AppColors.separator, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}
