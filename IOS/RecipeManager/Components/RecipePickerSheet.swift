import SwiftUI

/// Search-and-pick a recipe. Used by the meal plan and by collections.
struct RecipePickerSheet<Header: View>: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let title: String
    var excluding: Set<Int> = []
    @ViewBuilder var header: Header
    let onPick: (RecipeSummary) async -> Bool   // return true to dismiss

    @State private var query = ""
    @State private var results: [RecipeSummary] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                Section { header.listRowBackground(Color.clear).listRowInsets(EdgeInsets()) }
                Section {
                    ForEach(results.filter { !excluding.contains($0.id) }) { recipe in
                        Button {
                            Task { if await onPick(recipe) { dismiss() } }
                        } label: {
                            HStack(spacing: Spacing.s) {
                                RecipeImage(path: recipe.thumbUrl, title: recipe.title, id: recipe.id)
                                    .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: Radius.small))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recipe.title).font(AppTypography.cardTitle).foregroundStyle(AppColors.textPrimary)
                                    if !recipe.cardMeta.isEmpty { Text(recipe.cardMeta).font(.caption).foregroundStyle(AppColors.textSecondary) }
                                }
                            }
                            .frame(minHeight: Size.tap)
                        }
                        .listRowBackground(AppColors.card)
                    }
                    if results.isEmpty && loaded {
                        Text(query.isEmpty ? "No recipes yet." : "No matches.").foregroundStyle(AppColors.textSecondary).listRowBackground(Color.clear)
                    }
                }
            }
            .appBackground()
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search recipes")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task(id: query) {
                if !query.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
                guard !Task.isCancelled else { return }
                var p = ["per_page": "50", "sort": "title_az"]
                if !query.isEmpty { p["q"] = query }
                let page: Page<RecipeSummary>? = try? await session.run { [p] in try await $0.get("/recipes", query: p) }
                results = page?.items ?? []; loaded = true
            }
        }
    }
}

extension RecipePickerSheet where Header == EmptyView {
    init(title: String, excluding: Set<Int> = [], onPick: @escaping (RecipeSummary) async -> Bool) {
        self.init(title: title, excluding: excluding, header: { EmptyView() }, onPick: onPick)
    }
}
