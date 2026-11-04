import SwiftUI

/// The Category, Ingredient, Favorites and Sort chips (and "Clear"), with the sheets they open.
/// Used by the Search tab and All recipes.
struct RecipeFilterBar: View {
    private enum Sheet: String, Identifiable { case category, ingredient, sort; var id: String { rawValue } }

    let filters: RecipeFilters
    @State private var sheet: Sheet?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                FilterChip(title: filters.categoryIds.isEmpty ? "Category" : "Category · \(filters.categoryIds.count)",
                           isSelected: !filters.categoryIds.isEmpty, showsChevron: true) { sheet = .category }
                    .accessibilityLabel(filters.categoryIds.isEmpty ? "Category" : "Category: \(filters.selectedCategoryName ?? "1 selected")")
                    .accessibilityHint("Choose a category")
                FilterChip(title: filters.ingredient.isEmpty ? "Ingredient" : filters.ingredient,
                           isSelected: !filters.ingredient.isEmpty, showsChevron: true) { sheet = .ingredient }
                    .accessibilityLabel(filters.ingredient.isEmpty ? "Ingredient" : "Ingredient: \(filters.ingredient)")
                    .accessibilityHint("Only recipes with an ingredient")
                FilterChip(title: "Favorites", isSelected: filters.favoritesOnly) { filters.favoritesOnly.toggle() }
                    .accessibilityLabel("Favorites only")
                FilterChip(title: "Sort", isSelected: filters.sort != RecipeFilters.defaultSort, showsChevron: true) { sheet = .sort }
                    .accessibilityLabel("Sort: \(filters.sortTitle)")
                    .accessibilityHint("Choose the order")
                if filters.hasFilters {
                    Button("Clear") { withAnimation { filters.clearFilters() } }.font(.subheadline).foregroundStyle(AppColors.textSecondary)
                        .accessibilityLabel("Clear filters")
                }
            }
            .screenPadding()
        }
        .padding(.top, Spacing.xs)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .category: CategoryFilterSheet(filters: filters)
            case .ingredient: IngredientFilterSheet(filters: filters)
            case .sort: SortFilterSheet(filters: filters)
            }
        }
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
    let filters: RecipeFilters
    var body: some View {
        FilterSheetFrame(title: "Category") {
            List(filters.categories) { cat in
                Button {
                    // One category at a time: the server ANDs several, which rarely matches anything.
                    filters.categoryIds = filters.categoryIds == [cat.id] ? [] : [cat.id]
                } label: {
                    HStack { Text(cat.name).foregroundStyle(AppColors.textPrimary); Spacer()
                        if filters.categoryIds.contains(cat.id) { Image(systemName: "checkmark").foregroundStyle(AppColors.primary) } }
                }
                .accessibilityAddTraits(filters.categoryIds.contains(cat.id) ? .isSelected : [])
            }
        }
    }
}

struct IngredientFilterSheet: View {
    @Bindable var filters: RecipeFilters
    @FocusState private var focused: Bool
    var body: some View {
        FilterSheetFrame(title: "Ingredient") {
            Form {
                Section {
                    TextField("e.g. garlic", text: $filters.ingredient).focused($focused).textInputAutocapitalization(.never)
                } footer: { Text("Only recipes with this ingredient.") }
                if !filters.ingredient.isEmpty { Button("Clear", role: .destructive) { filters.ingredient = "" } }
            }
            .onAppear { focused = true }
        }
    }
}

struct SortFilterSheet: View {
    let filters: RecipeFilters
    var body: some View {
        FilterSheetFrame(title: "Sort") {
            List {
                ForEach(RecipeFilters.sortOptions, id: \.value) { option in
                    Button { filters.sort = option.value } label: {
                        HStack { Text(option.title).foregroundStyle(AppColors.textPrimary); Spacer()
                            if filters.sort == option.value { Image(systemName: "checkmark").foregroundStyle(AppColors.primary) } }
                    }
                    .accessibilityAddTraits(filters.sort == option.value ? .isSelected : [])
                }
            }
        }
    }
}
