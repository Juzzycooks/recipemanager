import Testing
@testable import RecipeManager

/// The filter state shared by Search and All recipes, and the `GET /recipes` query it builds.
@MainActor
struct RecipeFiltersTests {
    @Test func nothingSetIsEveryRecipeNewestFirst() {
        let filters = RecipeFilters()
        #expect(filters.params == ["sort": "newest"])
        #expect(!filters.isActive)
        #expect(!filters.hasFilters)
    }

    @Test func allRecipesKindStartsUnfiltered() {
        let filters = RecipeFilters(kind: .all)
        #expect(!filters.favoritesOnly)
        #expect(filters.params == ["sort": "newest"])
    }

    @Test func favoritesKindPreselectsTheFavoritesChip() {
        let filters = RecipeFilters(kind: .favorites)
        #expect(filters.favoritesOnly)
        #expect(filters.params == ["sort": "newest", "favorites": "1"])
        #expect(filters.isActive)
        #expect(!filters.isSearching)
    }

    @Test func queryAndFiltersMapToParams() {
        let filters = RecipeFilters()
        filters.query = "  pasta "
        filters.ingredient = "garlic"
        filters.categoryIds = [7]
        filters.favoritesOnly = true
        filters.sort = "title_az"
        #expect(filters.params == ["q": "pasta", "ingredient": "garlic", "cat": "7", "favorites": "1", "sort": "title_az"])
        #expect(filters.isSearching)
    }

    @Test func blankQueryIsNotSent() {
        let filters = RecipeFilters()
        filters.query = "   "
        #expect(filters.params["q"] == nil)
        #expect(!filters.isActive)
    }

    @Test func onlyOneCategoryIsSent() {
        let filters = RecipeFilters()
        filters.categoryIds = [9, 3]
        #expect(filters.params["cat"] == "3")
    }

    @Test func sortAloneIsAFilterButDoesNotNarrow() {
        let filters = RecipeFilters()
        filters.sort = "oldest"
        #expect(filters.hasFilters)
        #expect(!filters.isActive)
        #expect(filters.sortTitle == "Oldest")
    }

    @Test func clearFiltersKeepsTheQuery() {
        let filters = RecipeFilters(kind: .favorites)
        filters.query = "soup"
        filters.ingredient = "leek"
        filters.categoryIds = [2]
        filters.sort = "title_za"
        filters.clearFilters()
        #expect(filters.params == ["q": "soup", "sort": "newest"])
        #expect(!filters.hasFilters)
    }

    @Test func filterKeyChangesWithEveryFilter() {
        let filters = RecipeFilters()
        var seen: Set<String> = [filters.filterKey]
        filters.query = "a"; seen.insert(filters.filterKey)
        filters.categoryIds = [1]; seen.insert(filters.filterKey)
        filters.favoritesOnly = true; seen.insert(filters.filterKey)
        filters.ingredient = "egg"; seen.insert(filters.filterKey)
        filters.sort = "oldest"; seen.insert(filters.filterKey)
        #expect(seen.count == 6)
    }

    @Test func resultLineNamesWhatIsCounted() {
        let filters = RecipeFilters()
        #expect(filters.resultLine(total: 142) == "142 recipes")
        #expect(filters.resultLine(total: 1) == "1 recipe")
        filters.favoritesOnly = true
        #expect(filters.resultLine(total: 8) == "8 favorites")
        filters.query = "pie"
        #expect(filters.resultLine(total: 12) == "12 matches")
        #expect(filters.resultLine(total: 1) == "1 match")
    }

    @Test func selectedCategoryNameComesFromTheLoadedList() {
        let filters = RecipeFilters()
        filters.categories = [Category(id: 1, name: "Breakfast"), Category(id: 2, name: "Dinner")]
        #expect(filters.selectedCategoryName == nil)
        filters.categoryIds = [2]
        #expect(filters.selectedCategoryName == "Dinner")
    }
}
