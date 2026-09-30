import Foundation
import Observation

/// A paginated, filterable list of recipes (All Recipes, Favorites, Search results). Owners set `params`
/// (q, cat, favorites, sort…) and call `reload`; `loadMore` fetches the next page.
@MainActor @Observable
final class RecipeFeed {
    private(set) var recipes: [RecipeSummary] = []
    private(set) var total = 0
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var error: String?
    private var page = 0
    private var pages = 1

    func reload(_ session: Session, params: [String: String]) async {
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        var p = params
        p["page"] = "1"; p["per_page"] = "24"
        do {
            let result: Page<RecipeSummary> = try await session.run { [p] in try await $0.get("/recipes", query: p) }
            recipes = result.items; total = result.total; page = 1; pages = result.pages; error = nil
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch { self.error = error.localizedDescription }
    }

    func loadMoreIfNeeded(after recipe: RecipeSummary, _ session: Session, params: [String: String]) async {
        guard !isLoading, page < pages, recipe.id == recipes.last?.id else { return }
        isLoading = true
        defer { isLoading = false }
        var p = params
        p["page"] = String(page + 1); p["per_page"] = "24"
        if let result: Page<RecipeSummary> = try? await session.run({ [p] in try await $0.get("/recipes", query: p) }) {
            recipes += result.items; page += 1; pages = result.pages
        }
    }

    func toggleFavorite(_ recipe: RecipeSummary, _ session: Session, removeWhenUnfavorited: Bool = false) async {
        guard let i = recipes.firstIndex(where: { $0.id == recipe.id }) else { return }
        let wanted = !recipes[i].isFavorite
        recipes[i].isFavorite = wanted
        do {
            try await session.run { try await $0.send(wanted ? "PUT" : "DELETE", "/recipes/\(recipe.id)/favorite") }
            if removeWhenUnfavorited && !wanted { recipes.removeAll { $0.id == recipe.id }; total -= 1 }
        } catch {
            if let j = recipes.firstIndex(where: { $0.id == recipe.id }) { recipes[j].isFavorite = !wanted }
            self.error = error.localizedDescription
        }
    }
}
