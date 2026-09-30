import SwiftUI

/// "See All" from Home: every recipe, or only favorites.
struct RecipeListView: View {
    @Environment(Session.self) private var session
    let kind: RecipeListKind
    @State private var feed = RecipeFeed()
    @State private var sort = "newest"

    private var params: [String: String] {
        var p = ["sort": sort]
        if kind == .favorites { p["favorites"] = "1" }
        return p
    }

    var body: some View {
        ScrollView {
            if feed.recipes.isEmpty && feed.hasLoaded && !feed.isLoading {
                EmptyStateView(title: kind == .favorites ? "No favorites yet" : "No recipes yet", systemImage: kind == .favorites ? "heart" : "book.closed",
                               message: kind == .favorites ? "Tap the heart on a recipe to keep it here." : "Tap + to add your first recipe.")
                    .padding(.top, Spacing.xxl)
            } else {
                RecipeGrid(feed: feed, params: params, removeWhenUnfavorited: kind == .favorites).padding(.bottom, Spacing.xl)
            }
        }
        .background(AppColors.background)
        .navigationTitle(kind.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        Text("Newest").tag("newest"); Text("Oldest").tag("oldest")
                        Text("Title A–Z").tag("title_az"); Text("Title Z–A").tag("title_za")
                    }
                } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
            }
        }
        .task(id: "\(sort)#\(session.dataVersion)") { await feed.reload(session, params: params) }
        .refreshable { await feed.reload(session, params: params) }
        .errorAlert(Binding(get: { feed.error }, set: { feed.error = $0 }))
    }
}
