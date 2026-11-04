import SwiftUI

struct SearchView: View {
    @Environment(Session.self) private var session
    @State private var filters = RecipeFilters()
    @State private var feed = RecipeFeed()
    @AppStorage("recentSearches") private var recentData = Data()

    private var recents: [String] { (try? JSONDecoder().decode([String].self, from: recentData)) ?? [] }

    var body: some View {
        VerticalScroll {
            VStack(alignment: .leading, spacing: Spacing.m) {
                RecipeFilterBar(filters: filters)
                if filters.isActive { results } else { suggestions }
            }
            .padding(.bottom, Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColors.background)
        .navigationTitle("Search")
        // The system field: on iOS 26 the search tab carries it in the tab bar; earlier it sits under the title.
        .searchable(text: $filters.query, prompt: "Try “chicken”, “pasta” or “soup”")
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .onSubmit(of: .search) { remember(filters.query) }
        .task { await filters.loadCategories(session) }
        .task(id: "\(filters.filterKey)#\(session.dataVersion)") {
            guard filters.isActive else { return }
            if !filters.query.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await feed.reload(session, params: filters.params)
        }
    }

    @ViewBuilder private var results: some View {
        if feed.recipes.isEmpty && feed.hasLoaded && !feed.isLoading {
            EmptyStateView(title: "No matches", systemImage: "magnifyingglass", message: "Try a different word, or clear the filters.")
                .padding(.top, Spacing.xl)
        } else {
            if feed.hasLoaded {
                Text("\(feed.total) recipe\(feed.total == 1 ? "" : "s")").font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary).screenPadding()
            }
            RecipeGrid(feed: feed, params: filters.params)
        }
    }

    @ViewBuilder private var suggestions: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            NavigationLink(value: AppRoute.recipeList(.all)) { LibraryRow(title: "All recipes", systemImage: "book.closed") }.buttonStyle(.plain)
            NavigationLink(value: AppRoute.recipeList(.favorites)) { LibraryRow(title: "Favorites", systemImage: "heart") }.buttonStyle(.plain)
        }
        .screenPadding()
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text("Recent searches").font(AppTypography.title3).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Clear") { recentData = Data() }.font(.subheadline).foregroundStyle(AppColors.textSecondary)
                }
                ForEach(recents, id: \.self) { term in
                    Button { filters.query = term } label: { suggestionRow(term, symbol: "clock.arrow.circlepath") }.buttonStyle(.plain)
                }
            }
            .screenPadding()
        }
        if !filters.categories.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Browse by category").font(AppTypography.title3).accessibilityAddTraits(.isHeader)
                ForEach(filters.categories) { cat in
                    Button { filters.categoryIds = [cat.id] } label: { suggestionRow(cat.name, symbol: "magnifyingglass") }.buttonStyle(.plain)
                }
            }
            .screenPadding()
        }
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
