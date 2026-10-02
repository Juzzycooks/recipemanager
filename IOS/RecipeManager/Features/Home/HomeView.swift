import SwiftUI

@MainActor @Observable
final class HomeModel {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", favorites = "Favorites", recent = "Recently Added"
        var id: String { rawValue }
    }

    var filter = Filter.all
    var picks: [RecipeSummary] = []
    var collections: [CollectionSummary] = []
    var hasLoaded = false
    var error: String?

    func load(_ session: Session) async {
        let favorites = filter == .favorites
        do {
            var query = ["per_page": "12", "sort": "newest"]
            if favorites { query["favorites"] = "1" }
            let page: Page<RecipeSummary> = try await session.run { [query] in try await $0.get("/recipes", query: query) }
            picks = filter == .recent ? page.items.filter { Self.isRecent($0) } : page.items
            let colls: ItemList<CollectionSummary> = try await session.run { try await $0.get("/collections") }
            collections = colls.items
            error = nil
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch { self.error = error.localizedDescription }
        hasLoaded = true
    }

    private static func isRecent(_ recipe: RecipeSummary) -> Bool {
        guard let created = recipe.createdAt else { return false }
        return created > Date.now.addingTimeInterval(-14 * 24 * 3600)
    }

    func toggleFavorite(_ recipe: RecipeSummary, _ session: Session) async {
        guard let i = picks.firstIndex(where: { $0.id == recipe.id }) else { return }
        let wanted = !picks[i].isFavorite
        picks[i].isFavorite = wanted
        do {
            _ = try await session.runOrQueue(.favorite(recipeID: recipe.id, wanted: wanted)) { try await $0.send(wanted ? "PUT" : "DELETE", "/recipes/\(recipe.id)/favorite") }
            if filter == .favorites && !wanted { picks.removeAll { $0.id == recipe.id } }
        } catch {
            if let j = picks.firstIndex(where: { $0.id == recipe.id }) { picks[j].isFavorite = !wanted }
            self.error = error.localizedDescription
        }
    }
}

struct HomeView: View {
    @Environment(Session.self) private var session
    @Environment(AppState.self) private var app
    @State private var model = HomeModel()
    @State private var path: [AppRoute] = []

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning,"
        case 12..<18: "Good afternoon,"
        default: "Good evening,"
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VerticalScroll {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    header
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SearchBarButton { app.openSearch() }
                        chips
                    }
                    .screenPadding()
                    quickPicks
                    collections
                    planAndShop
                }
                .padding(.top, Spacing.xs).padding(.bottom, Spacing.xl)
            }
            .background(AppColors.background)
            .withAppTabBar()
            .onChange(of: app.homeRequest) { path = [] }
            .toolbar(.hidden, for: .navigationBar)
            .appDestinations()
            .task(id: "\(model.filter.rawValue)#\(session.dataVersion)") { await model.load(session) }
            .refreshable { await model.load(session) }
            .errorAlert($model.error)
            .onChange(of: app.pendingRecipeID, initial: true) {
                if let id = app.pendingRecipeID { path.append(.recipe(id)); app.pendingRecipeID = nil }
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text(greeting).font(.system(.title, design: .serif, weight: .regular)).foregroundStyle(AppColors.textPrimary)
                Text(session.user?.username ?? "").font(.system(.title, design: .serif, weight: .bold)).foregroundStyle(AppColors.textPrimary)
            }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            Spacer()
            Button { app.tab = .profile } label: { AvatarView(name: session.user?.username ?? "") }
                .buttonStyle(.plain).accessibilityLabel("Profile")
        }
        .screenPadding()
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(HomeModel.Filter.allCases) { f in
                    FilterChip(title: f.rawValue, isSelected: model.filter == f) { model.filter = f }
                }
            }
        }
    }

    private var quickPicks: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "Quick Picks") { path.append(.recipeList(model.filter == .favorites ? .favorites : .all)) }
            if model.picks.isEmpty && model.hasLoaded {
                Text(emptyMessage).font(.subheadline).foregroundStyle(AppColors.textSecondary).screenPadding().padding(.vertical, Spacing.m)
            } else {
                RecipeCarousel(recipes: model.picks) { recipe in Task { await model.toggleFavorite(recipe, session) } }
            }
        }
    }

    private var emptyMessage: String {
        switch model.filter {
        case .all: "No recipes yet. Tap + to add your first."
        case .favorites: "Tap the heart on a recipe to keep it here."
        case .recent: "Nothing added in the last two weeks."
        }
    }

    private var collections: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "Your Collections") { app.tab = .collections }
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

    private var planAndShop: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "Plan & Shop", actionTitle: nil)
            HStack(spacing: Spacing.s) {
                shortcut("Meal Plan", "calendar", .mealPlan)
                shortcut("Shopping List", "cart", .shoppingList)
            }
            .screenPadding()
        }
    }

    private func shortcut(_ title: String, _ symbol: String, _ route: AppRoute) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: symbol).foregroundStyle(AppColors.primary)
                Text(title).font(AppTypography.label).foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(Spacing.m).frame(maxWidth: .infinity, minHeight: Size.tap)
            .background(AppColors.card, in: RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(AppColors.separator, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

struct AvatarView: View {
    let name: String
    var size: CGFloat = Size.avatar

    var body: some View {
        Text(String(name.first ?? "?").uppercased())
            .font(.system(size: size * 0.42, weight: .semibold, design: .serif)).foregroundStyle(AppColors.onPrimary)
            .frame(width: size, height: size).background(AppColors.secondary, in: Circle())
            .accessibilityHidden(true)
    }
}
