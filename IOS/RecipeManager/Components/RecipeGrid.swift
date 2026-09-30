import SwiftUI

/// Two-up (or more on wide screens) grid of recipe cards with infinite scroll.
struct RecipeGrid: View {
    @Environment(Session.self) private var session
    let feed: RecipeFeed
    let params: [String: String]
    var removeWhenUnfavorited = false

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: Spacing.s, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Spacing.s) {
            ForEach(feed.recipes) { recipe in
                NavigationLink(value: AppRoute.recipe(recipe.id)) {
                    RecipeCard(recipe: recipe) { Task { await feed.toggleFavorite(recipe, session, removeWhenUnfavorited: removeWhenUnfavorited) } }
                }
                .buttonStyle(.plain)
                .task { await feed.loadMoreIfNeeded(after: recipe, session, params: params) }
            }
        }
        .screenPadding()
    }
}
