import SwiftUI

/// All recipes, searchable and filtered with the same chips as the Search tab. With nothing set it is every recipe,
/// newest first; `.favorites` is this page with the Favorites chip already on.
struct RecipeListView: View {
    @Environment(Session.self) private var session
    @State private var filters: RecipeFilters
    @State private var feed = RecipeFeed()

    init(kind: RecipeListKind) {
        _filters = State(initialValue: RecipeFilters(kind: kind))
    }

    var body: some View {
        VerticalScroll {
            VStack(alignment: .leading, spacing: Spacing.m) {
                RecipeFilterBar(filters: filters)
                content
            }
            .padding(.bottom, Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColors.background)
        .navigationTitle(filters.favoritesOnly ? RecipeListKind.favorites.title : RecipeListKind.all.title)
        // Always showing: the automatic placement hides it in the bar until the list is pulled down.
        .searchable(text: $filters.query, placement: .navigationBarDrawer(displayMode: .always), prompt: filters.favoritesOnly ? "Search favorites" : "Search recipes")
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .task { await filters.loadCategories(session) }
        .task(id: "\(filters.filterKey)#\(session.dataVersion)") {
            if !filters.query.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await feed.reload(session, params: filters.params)
        }
        .refreshable { await feed.reload(session, params: filters.params) }
        .errorAlert(Binding(get: { feed.error }, set: { feed.error = $0 }))
    }

    @ViewBuilder private var content: some View {
        if feed.recipes.isEmpty && feed.hasLoaded && !feed.isLoading {
            emptyState.padding(.top, Spacing.xl)
        } else {
            if feed.hasLoaded {
                Text(filters.resultLine(total: feed.total)).font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary).screenPadding()
            }
            RecipeGrid(feed: feed, params: filters.params, removeWhenUnfavorited: filters.favoritesOnly)
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !filters.isActive {
            EmptyStateView(title: "No recipes yet", systemImage: "book.closed", message: "Tap + to add your first recipe.")
        } else if !filters.isSearching {   // only the Favorites chip is on
            EmptyStateView(title: "No favorites yet", systemImage: "heart", message: "Tap the heart on a recipe to keep it here.",
                           actionTitle: "Show all recipes") { withAnimation { filters.favoritesOnly = false } }
        } else {
            EmptyStateView(title: "No recipes match", systemImage: "magnifyingglass", message: "Try a different word, or clear the filters.",
                           actionTitle: "Clear filters") { withAnimation { filters.query = ""; filters.clearFilters() } }
        }
    }
}
