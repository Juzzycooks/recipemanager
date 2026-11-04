import Foundation
import Observation

/// What a recipe list is narrowed to: the search text plus the Category, Ingredient, Favorites and Sort chips.
/// Shared by the Search tab and All recipes; `params` is the `GET /recipes` query for `RecipeFeed`.
@MainActor @Observable
final class RecipeFilters {
    static let defaultSort = "newest"
    static let sortOptions: [(value: String, title: String)] = [
        ("newest", "Newest"), ("oldest", "Oldest"), ("title_az", "Title A–Z"), ("title_za", "Title Z–A"),
    ]

    var query = ""
    var categoryIds: Set<Int> = []
    var favoritesOnly = false
    var ingredient = ""
    var sort = RecipeFilters.defaultSort
    var categories: [Category] = []

    init(favoritesOnly: Bool = false) {
        self.favoritesOnly = favoritesOnly
    }

    /// The All recipes page: `.favorites` is the same page with the Favorites chip already on.
    convenience init(kind: RecipeListKind) {
        self.init(favoritesOnly: kind == .favorites)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    /// Anything the chips' "Clear" would reset (sort included).
    var hasFilters: Bool { favoritesOnly || !categoryIds.isEmpty || !ingredient.isEmpty || sort != Self.defaultSort }
    /// Narrowed by text, category or ingredient (Favorites aside).
    var isSearching: Bool { !trimmedQuery.isEmpty || !categoryIds.isEmpty || !ingredient.isEmpty }
    /// Whether the list is narrowed at all (sort only reorders, so it doesn't count).
    var isActive: Bool { isSearching || favoritesOnly }
    /// Changes whenever the results would; a `.task(id:)` key.
    var filterKey: String { "\(query)|\(categoryIds.sorted())|\(favoritesOnly)|\(ingredient)|\(sort)" }

    var params: [String: String] {
        var p = ["sort": sort]
        if !trimmedQuery.isEmpty { p["q"] = trimmedQuery }
        if favoritesOnly { p["favorites"] = "1" }
        if !ingredient.isEmpty { p["ingredient"] = ingredient }
        if let first = categoryIds.sorted().first { p["cat"] = String(first) }
        return p
    }

    var selectedCategoryName: String? {
        guard let id = categoryIds.sorted().first else { return nil }
        return categories.first { $0.id == id }?.name
    }

    var sortTitle: String { Self.sortOptions.first { $0.value == sort }?.title ?? sort }

    /// "142 recipes" with nothing narrowing the list, "8 favorites" with only Favorites on, else "12 matches".
    func resultLine(total: Int) -> String {
        let noun = isSearching ? "match" : favoritesOnly ? "favorite" : "recipe"
        let plural = total == 1 ? noun : noun == "match" ? "matches" : noun + "s"
        return "\(total) \(plural)"
    }

    func clearFilters() { categoryIds = []; favoritesOnly = false; ingredient = ""; sort = Self.defaultSort }

    func loadCategories(_ session: Session) async {
        guard categories.isEmpty else { return }
        let result: ItemList<Category>? = try? await session.run { try await $0.get("/categories") }
        categories = result?.items ?? []
    }
}
