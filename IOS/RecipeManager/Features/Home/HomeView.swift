import SwiftUI

@MainActor @Observable
final class HomeModel {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", favorites = "Favorites"
        var id: String { rawValue }
    }

    var filter = Filter.all
    var picks: [RecipeSummary] = []
    /// How many recipes (or favorites) there are in all: the shelf's page carries it, so it costs no extra request.
    var total: Int?
    var collections: [CollectionSummary] = []
    var hasLoaded = false
    var error: String?

    func load(_ session: Session) async {
        let favorites = filter == .favorites
        do {
            var query = ["per_page": "12", "sort": "newest"]
            if favorites { query["favorites"] = "1" }
            let page: Page<RecipeSummary> = try await session.run { [query] in try await $0.get("/recipes", query: query) }
            picks = page.items
            total = page.total
            let colls: ItemList<CollectionSummary> = try await session.run { try await $0.get("/collections") }
            collections = colls.items
            error = nil
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch { self.error = error.localizedDescription }
        hasLoaded = true
    }

    /// The admin's site name titles the shelf; it's remembered so the title doesn't flicker (or vanish offline).
    func loadSiteName(_ session: Session) async {
        guard let info: SiteInfo = try? await session.run({ try await $0.get("/site") }) else { return }
        UserDefaults.standard.set(info.name.trimmingCharacters(in: .whitespaces), forKey: HomeView.siteNameKey)
    }

    func toggleFavorite(_ recipe: RecipeSummary, _ session: Session) async {
        guard let i = picks.firstIndex(where: { $0.id == recipe.id }) else { return }
        let wanted = !picks[i].isFavorite
        picks[i].isFavorite = wanted
        do {
            _ = try await session.runOrQueue(.favorite(recipeID: recipe.id, wanted: wanted)) { try await $0.send(wanted ? "PUT" : "DELETE", "/recipes/\(recipe.id)/favorite") }
            if filter == .favorites && !wanted {
                picks.removeAll { $0.id == recipe.id }
                if let t = total { total = max(0, t - 1) }
            }
        } catch {
            if let j = picks.firstIndex(where: { $0.id == recipe.id }) { picks[j].isFavorite = !wanted }
            self.error = error.localizedDescription
        }
    }
}

struct HomeView: View {
    static let siteNameKey = "siteName"

    @Environment(Session.self) private var session
    @Environment(AppState.self) private var app
    @State private var model = HomeModel()
    @State private var showingProfile = false
    @AppStorage(HomeView.siteNameKey) private var siteName = ""

    var body: some View {
        VerticalScroll {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    chips
                    shelf
                    allRecipesButton
                }
                collections
            }
            .padding(.bottom, Spacing.xl)
        }
        .background(AppColors.background)
        .navigationTitle(siteName.isEmpty ? "Recipes" : siteName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add recipe", systemImage: "plus") { app.showingAdd = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingProfile = true } label: { AvatarView(name: session.user?.username ?? "", size: 30) }
                    .accessibilityLabel("Profile and settings")
            }
        }
        .sheet(isPresented: $showingProfile) { ProfileView() }
        .task(id: "\(model.filter.rawValue)#\(session.dataVersion)") { await model.load(session) }
        .task(id: session.dataVersion) { await model.loadSiteName(session) }
        .refreshable { await model.load(session) }
        .errorAlert($model.error)
    }

    // MARK: Sections

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(HomeModel.Filter.allCases) { f in
                    FilterChip(title: f.rawValue, isSelected: model.filter == f) { model.filter = f }
                }
            }
            .screenPadding()
        }
    }

    /// The shelf: the newest recipes, or your favorites.
    private var shelf: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: model.filter == .favorites ? "Favorites" : "Newest")
            if model.picks.isEmpty && model.hasLoaded {
                Text(emptyMessage).font(.subheadline).foregroundStyle(AppColors.textSecondary).screenPadding().padding(.vertical, Spacing.m)
            } else {
                RecipeCarousel(recipes: model.picks) { recipe in Task { await model.toggleFavorite(recipe, session) } }
            }
        }
    }

    /// Under the shelf: every recipe (or every favorite), searchable and filterable.
    @ViewBuilder private var allRecipesButton: some View {
        if !(model.picks.isEmpty && model.hasLoaded) {
            let favorites = model.filter == .favorites
            let title = favorites ? "All favorites" : "All recipes"
            NavigationLink(value: AppRoute.recipeList(favorites ? .favorites : .all)) {
                LibraryRow(title: title, systemImage: favorites ? "heart" : "book.closed", detail: model.total.map { "\($0)" })
            }
            .buttonStyle(.plain)
            .screenPadding()
            .accessibilityLabel(model.total.map { "\(title), \($0) \(favorites ? "favorite" : "recipe")\($0 == 1 ? "" : "s")" } ?? title)
            .accessibilityIdentifier("home.allRecipes")
        }
    }

    private var emptyMessage: String {
        switch model.filter {
        case .all: "No recipes yet. Tap + to add your first."
        case .favorites: "Tap the heart on a recipe to keep it here."
        }
    }

    private var collections: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "Your collections") { app.tab = .collections }
            if model.collections.isEmpty && model.hasLoaded {
                Text("Group recipes into collections from the Collections tab.").font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary).screenPadding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Spacing.s) {
                        ForEach(model.collections) { c in
                            NavigationLink(value: AppRoute.collection(c.id)) { CollectionCard(collection: c).frame(width: 128) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.screen)
                }
            }
        }
    }
}

/// The account monogram: the user's initial in italic Alegreya, white on the accent fill.
struct AvatarView: View {
    let name: String
    var size: CGFloat = Size.avatar

    var body: some View {
        Text(String(name.first ?? "?").uppercased())
            .font(AppTypography.monogram(size: size * 0.5)).foregroundStyle(AppColors.onPrimary)
            .frame(width: size, height: size).background(AppColors.primaryFill, in: Circle())
            .accessibilityHidden(true)
    }
}
