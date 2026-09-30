import SwiftUI

@MainActor @Observable
final class SearchModel {
    var query = ""
    var categoryIds: Set<Int> = []
    var favoritesOnly = false
    var ingredient = ""
    var sort = "newest"
    var categories: [Category] = []
    let feed = RecipeFeed()

    var hasFilters: Bool { favoritesOnly || !categoryIds.isEmpty || !ingredient.isEmpty || sort != "newest" }
    var isActive: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty || favoritesOnly || !categoryIds.isEmpty || !ingredient.isEmpty }
    var filterKey: String { "\(query)|\(categoryIds.sorted())|\(favoritesOnly)|\(ingredient)|\(sort)" }

    var params: [String: String] {
        var p = ["sort": sort]
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { p["q"] = q }
        if favoritesOnly { p["favorites"] = "1" }
        if !ingredient.isEmpty { p["ingredient"] = ingredient }
        if let first = categoryIds.sorted().first { p["cat"] = String(first) }
        return p
    }

    func clearFilters() { categoryIds = []; favoritesOnly = false; ingredient = ""; sort = "newest" }

    func loadCategories(_ session: Session) async {
        guard categories.isEmpty else { return }
        let result: ItemList<Category>? = try? await session.run { try await $0.get("/categories") }
        categories = result?.items ?? []
    }
}

struct SearchView: View {
    private enum Sheet: String, Identifiable { case category, ingredient, sort; var id: String { rawValue } }

    @Environment(Session.self) private var session
    @Environment(AppState.self) private var app
    @State private var model = SearchModel()
    @State private var sheet: Sheet?
    @FocusState private var focused: Bool
    @AppStorage("recentSearches") private var recentData = Data()

    private var recents: [String] { (try? JSONDecoder().decode([String].self, from: recentData)) ?? [] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    SearchBar(text: $model.query, prompt: "Try “chicken”, “pasta” or “soup”…", focus: $focused) { remember(model.query) }
                        .screenPadding()
                    chips
                    if model.isActive { results } else { suggestions }
                }
                .padding(.bottom, Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppColors.background)
            .navigationTitle("Search")
            .appDestinations()
            .task { await model.loadCategories(session) }
            .task(id: "\(model.filterKey)#\(session.dataVersion)") {
                guard model.isActive else { return }
                if !model.query.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
                guard !Task.isCancelled else { return }
                await model.feed.reload(session, params: model.params)
            }
            .onChange(of: app.searchFocusRequest) { focused = true }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .category: CategoryFilterSheet(model: model)
                case .ingredient: IngredientFilterSheet(model: model)
                case .sort: SortFilterSheet(model: model)
                }
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                FilterChip(title: model.categoryIds.isEmpty ? "Category" : "Category · \(model.categoryIds.count)",
                           isSelected: !model.categoryIds.isEmpty, showsChevron: true) { sheet = .category }
                FilterChip(title: model.ingredient.isEmpty ? "Ingredient" : model.ingredient,
                           isSelected: !model.ingredient.isEmpty, showsChevron: true) { sheet = .ingredient }
                FilterChip(title: "Favorites", isSelected: model.favoritesOnly) { model.favoritesOnly.toggle() }
                FilterChip(title: "Sort", isSelected: model.sort != "newest", showsChevron: true) { sheet = .sort }
                if model.hasFilters {
                    Button("Clear") { withAnimation { model.clearFilters() } }.font(.subheadline).foregroundStyle(AppColors.textSecondary)
                }
            }
            .screenPadding()
        }
    }

    @ViewBuilder private var results: some View {
        if model.feed.recipes.isEmpty && model.feed.hasLoaded && !model.feed.isLoading {
            EmptyStateView(title: "No matches", systemImage: "magnifyingglass", message: "Try a different word, or clear the filters.")
                .padding(.top, Spacing.xl)
        } else {
            if model.feed.hasLoaded {
                Text("\(model.feed.total) recipe\(model.feed.total == 1 ? "" : "s")").font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary).screenPadding()
            }
            RecipeGrid(feed: model.feed, params: model.params)
        }
    }

    @ViewBuilder private var suggestions: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            NavigationLink(value: AppRoute.recipeList(.all)) { libraryRow("All Recipes", symbol: "book.closed") }.buttonStyle(.plain)
            NavigationLink(value: AppRoute.recipeList(.favorites)) { libraryRow("Favorites", symbol: "heart") }.buttonStyle(.plain)
        }
        .screenPadding()
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text("Recent Searches").font(AppTypography.title3).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Clear") { recentData = Data() }.font(.subheadline).foregroundStyle(AppColors.textSecondary)
                }
                ForEach(recents, id: \.self) { term in
                    Button { model.query = term } label: { suggestionRow(term, symbol: "clock.arrow.circlepath") }.buttonStyle(.plain)
                }
            }
            .screenPadding()
        }
        if !model.categories.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Browse by Category").font(AppTypography.title3).accessibilityAddTraits(.isHeader)
                ForEach(model.categories) { cat in
                    Button { model.categoryIds = [cat.id] } label: { suggestionRow(cat.name, symbol: "magnifyingglass") }.buttonStyle(.plain)
                }
            }
            .screenPadding()
        }
    }

    private func libraryRow(_ title: String, symbol: String) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: symbol).foregroundStyle(AppColors.primary).frame(width: 24)
            Text(title).font(AppTypography.label).foregroundStyle(AppColors.textPrimary)
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, Spacing.m).frame(minHeight: 52)
        .background(AppColors.card, in: RoundedRectangle(cornerRadius: Radius.field))
        .overlay(RoundedRectangle(cornerRadius: Radius.field).stroke(AppColors.separator, lineWidth: 0.5))
    }

    private func suggestionRow(_ text: String, symbol: String) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: symbol).foregroundStyle(AppColors.textSecondary).frame(width: 24)
            Text(text).foregroundStyle(AppColors.textPrimary)
            Spacer()
        }
        .frame(minHeight: Size.tap).contentShape(Rectangle())
    }

    private func remember(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        var list = recents.filter { $0.caseInsensitiveCompare(t) != .orderedSame }
        list.insert(t, at: 0)
        recentData = (try? JSONEncoder().encode(Array(list.prefix(8)))) ?? Data()
    }
}

// MARK: Filter sheets

private struct FilterSheetFrame<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            content.appBackground().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct CategoryFilterSheet: View {
    let model: SearchModel
    var body: some View {
        FilterSheetFrame(title: "Category") {
            List(model.categories) { cat in
                Button {
                    // One category at a time: the server ANDs several, which rarely matches anything.
                    model.categoryIds = model.categoryIds == [cat.id] ? [] : [cat.id]
                } label: {
                    HStack { Text(cat.name).foregroundStyle(AppColors.textPrimary); Spacer()
                        if model.categoryIds.contains(cat.id) { Image(systemName: "checkmark").foregroundStyle(AppColors.primary) } }
                }
            }
        }
    }
}

struct IngredientFilterSheet: View {
    @Bindable var model: SearchModel
    @FocusState private var focused: Bool
    var body: some View {
        FilterSheetFrame(title: "Ingredient") {
            Form {
                Section {
                    TextField("e.g. garlic", text: $model.ingredient).focused($focused).textInputAutocapitalization(.never)
                } footer: { Text("Only recipes with this ingredient.") }
                if !model.ingredient.isEmpty { Button("Clear", role: .destructive) { model.ingredient = "" } }
            }
            .onAppear { focused = true }
        }
    }
}

struct SortFilterSheet: View {
    @Bindable var model: SearchModel
    var body: some View {
        FilterSheetFrame(title: "Sort") {
            List {
                ForEach([("newest", "Newest"), ("oldest", "Oldest"), ("title_az", "Title A–Z"), ("title_za", "Title Z–A")], id: \.0) { value, title in
                    Button { model.sort = value } label: {
                        HStack { Text(title).foregroundStyle(AppColors.textPrimary); Spacer()
                            if model.sort == value { Image(systemName: "checkmark").foregroundStyle(AppColors.primary) } }
                    }
                }
            }
        }
    }
}
