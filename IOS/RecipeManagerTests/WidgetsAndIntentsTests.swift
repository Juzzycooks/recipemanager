import Foundation
import Testing
@testable import RecipeManager

private final class FixtureToken {}

private func fixture<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
    let url = try #require(Bundle(for: FixtureToken.self).url(forResource: name, withExtension: "json"))
    return try APIClient.decoder.decode(T.self, from: Data(contentsOf: url))
}

private func meal(_ id: Int, _ date: String, _ type: String, _ title: String = "Soup") -> WidgetMeal {
    WidgetMeal(id: id, recipeID: id * 10, title: title, date: date, mealType: type, time: "", imageURL: nil)
}

private func calendar(_ zone: String) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: zone)!
    return c
}

private func temporaryStore() -> SnapshotStore {
    SnapshotStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("snapshots-\(UUID().uuidString)"))
}

struct WidgetSnapshotTests {
    @Test func planAndShoppingSnapshotsRoundTripThroughTheStore() throws {
        let store = temporaryStore()
        defer { store.clear() }
        let plan = PlanSnapshot(meals: [meal(1, "2026-11-04", "dinner", "Shish Barak")])
        #expect(store.write(plan: plan))
        #expect(!store.write(plan: plan))          // unchanged: no widget reload
        #expect(store.plan == plan)

        let list: ShoppingList = try fixture("shopping")
        let shopping = ShoppingSnapshot(list)
        #expect(store.write(shopping: shopping))
        #expect(store.shopping == shopping)
        #expect(store.shopping?.items.map(\.name) == list.items.map(\.name))
    }

    @Test func storeWithoutAnAppGroupDoesNothing() {
        let store = SnapshotStore(directory: nil)
        #expect(!store.write(plan: PlanSnapshot(meals: [meal(1, "2026-11-04", "dinner")])))
        #expect(store.plan == nil)
        #expect(store.pendingTicks.isEmpty)
    }

    @MainActor @Test func widgetTicksWaitWhileTheSessionHasNoClient() async {
        let store = temporaryStore()
        defer { store.clear() }
        store.addPendingTick(PendingTick(itemID: 4, name: "flour", checked: true))
        await WidgetBridge.drainPendingTicks(client: nil, store: store)
        #expect(store.pendingTicks.map(\.itemID) == [4])   // not taken, so not lost
    }

    @Test func pendingTicksAreKeptOncePerItemAndTakenOnce() {
        let store = temporaryStore()
        defer { store.clear() }
        store.addPendingTick(PendingTick(itemID: 4, name: "flour", checked: true))
        store.addPendingTick(PendingTick(itemID: 4, name: "flour", checked: true))
        store.addPendingTick(PendingTick(itemID: -9, name: "milk", checked: true))
        #expect(store.pendingTicks.count == 2)
        store.removePendingTicks([4])
        #expect(store.pendingTicks.map(\.itemID) == [-9])
        #expect(store.takePendingTicks().map(\.name) == ["milk"])
        #expect(store.pendingTicks.isEmpty)
    }

    @Test func tickingInTheSnapshotHidesTheItem() throws {
        let store = temporaryStore()
        defer { store.clear() }
        store.write(shopping: ShoppingSnapshot(try fixture("shopping", as: ShoppingList.self)))
        let before = try #require(store.shopping).openCount
        store.markChecked(2)
        #expect(store.shopping?.openCount == before - 1)
        #expect(store.shopping?.openByAisle.flatMap(\.items).contains { $0.id == 2 } == false)
    }

    @Test func shoppingGroupsFollowTheAisleOrderAndPendingTicks() throws {
        let list = ShoppingSnapshot(try fixture("shopping", as: ShoppingList.self))
        #expect(list.openByAisle.map(\.aisle) == ["Produce", "Pantry"])
        let ticked = list.applying([PendingTick(itemID: 1, name: "4 tomatoes", checked: true)])
        #expect(ticked.openByAisle.first?.items.map(\.id) == [2])
        // An aisle the order doesn't name still shows (last).
        let odd = ShoppingSnapshot(aisleOrder: ["Produce"], items: [
            WidgetShoppingItem(id: 1, name: "Saffron", aisle: "Spices", checked: false),
            WidgetShoppingItem(id: 2, name: "Leeks", aisle: "Produce", checked: false),
        ])
        #expect(odd.openByAisle.map(\.aisle) == ["Produce", "Spices"])
    }

    @Test func widgetRowsFitTheLinesAndCountTheRest() {
        let list = ShoppingSnapshot(aisleOrder: ["Produce", "Dairy"], items: [
            WidgetShoppingItem(id: 1, name: "Leeks", aisle: "Produce", checked: false),
            WidgetShoppingItem(id: 2, name: "Lemons", aisle: "Produce", checked: false),
            WidgetShoppingItem(id: 3, name: "Milk", aisle: "Dairy", checked: false),
            WidgetShoppingItem(id: 4, name: "Feta", aisle: "Dairy", checked: false),
            WidgetShoppingItem(id: 5, name: "Butter", aisle: "Dairy", checked: true),
        ])
        let flat = list.widgetRows(lines: 3, headings: false)
        #expect(flat.rows.count == 3)
        #expect(flat.hidden == 1)
        // With headings, a heading never sits at the bottom with nothing under it: Dairy doesn't fit in 4 lines.
        let headed = list.widgetRows(lines: 4, headings: true)
        #expect(headed.rows == [.aisle("Produce"), .item(list.items[0]), .item(list.items[1])])
        #expect(headed.hidden == 2)
        #expect(list.widgetRows(lines: 5, headings: true).rows.count == 5)
    }
}

struct PlanSelectionTests {
    @Test func tonightsDinnerUsesTheDeviceTimeZone() {
        let plan = PlanSnapshot(meals: [
            meal(1, "2026-11-04", "dinner", "Wednesday soup"),
            meal(2, "2026-11-05", "lunch", "Thursday salad"),
            meal(3, "2026-11-05", "dinner", "Thursday curry"),
        ])
        let now = Date(timeIntervalSince1970: 1_793_822_400)   // 2026-11-04 20:00 UTC = 2026-11-05 07:00 in Sydney
        #expect(plan.dinner(on: now, calendar: calendar("UTC"))?.title == "Wednesday soup")
        #expect(plan.dinner(on: now, calendar: calendar("Australia/Sydney"))?.title == "Thursday curry")
        #expect(plan.meals(on: now, calendar: calendar("Australia/Sydney")).map(\.mealType) == ["lunch", "dinner"])
        #expect(plan.dinner(on: now, calendar: calendar("America/Los_Angeles"))?.title == "Wednesday soup")
    }

    @Test func noDinnerWhenOnlyOtherMealsArePlanned() {
        let plan = PlanSnapshot(meals: [meal(1, "2026-11-04", "snack"), meal(2, "2026-11-04", "breakfast")])
        let now = Date(timeIntervalSince1970: 1_793_793_600)   // 2026-11-04 12:00 UTC
        #expect(plan.dinner(on: now, calendar: calendar("UTC")) == nil)
        #expect(plan.meals(on: now, calendar: calendar("UTC")).map(\.mealType) == ["breakfast", "snack"])
    }

    @Test func mergingReplacesTheFetchedRangeAndDropsPastDays() {
        let old = PlanSnapshot(meals: [meal(1, "2026-11-03", "dinner"), meal(2, "2026-11-04", "dinner"), meal(3, "2026-11-12", "dinner")])
        let merged = old.merging([meal(4, "2026-11-05", "dinner")], from: "2026-11-02", to: "2026-11-08",
                                 today: "2026-11-04", keepUntil: "2026-11-11")
        // 1 is in the past, 2 was removed from the fetched week, 3 is beyond the window.
        #expect(merged.meals.map(\.id) == [4])
        let kept = old.merging([], from: "2026-11-09", to: "2026-11-15", today: "2026-11-04", keepUntil: "2026-11-30")
        #expect(kept.meals.map(\.id) == [2])
    }

    @Test func dayKeysAreInTheCalendarsTimeZone() {
        let now = Date(timeIntervalSince1970: 1_793_822_400)
        #expect(PlanDay.key(now, calendar: calendar("UTC")) == "2026-11-04")
        #expect(PlanDay.key(now, calendar: calendar("Australia/Sydney")) == "2026-11-05")
        #expect(PlanDay.key(daysFrom: now, 1, calendar: calendar("UTC")) == "2026-11-05")
    }

    @Test func mealFromAPlanEntryResolvesItsPicture() throws {
        let week: PlanWeek = try fixture("mealplan")
        let entry = try #require(week.entries.first)
        let plain = WidgetMeal(entry, base: URL(string: "https://recipes.example.com"))
        #expect(plain.title == "Shish Barak")
        #expect(plain.time == "Cook 40 min")
        #expect(plain.imageURL == nil)   // the fixture has no picture
        #expect(WidgetMeal.resolve("/admin/uploads/a.jpg", base: URL(string: "https://r.example.com/sub"))?.absoluteString
                == "https://r.example.com/admin/uploads/a.jpg")
        #expect(WidgetMeal.resolve("https://cdn.example.com/a.jpg", base: nil)?.absoluteString == "https://cdn.example.com/a.jpg")
    }

    @Test func siriSaysTonightsDinnerAndTheRest() {
        #expect(DinnerAnswer.sentence(for: []) == "Nothing's planned for today.")
        #expect(DinnerAnswer.sentence(for: [meal(1, "d", "dinner", "Curry")]) == "Tonight's dinner is Curry.")
        #expect(DinnerAnswer.sentence(for: [meal(2, "d", "lunch", "Salad"), meal(1, "d", "dinner", "Curry")])
                == "Tonight's dinner is Curry. Also today: for lunch, Salad.")
        #expect(DinnerAnswer.sentence(for: [meal(2, "d", "lunch", "Salad")]) == "No dinner planned yet. Also today: for lunch, Salad.")
    }

    @Test func timerLengthsReadNaturally() {
        #expect(IntentActions.duration(1) == "1 minute")
        #expect(IntentActions.duration(10) == "10 minutes")
        #expect(IntentActions.duration(60) == "1 hour")
        #expect(IntentActions.duration(90) == "90 minutes")
        #expect(IntentActions.duration(120) == "2 hours")
    }
}

struct DeepLinkTests {
    @Test func parsesTheWidgetLinks() {
        #expect(DeepLink(url: URL(string: "spoonmate://recipe/12")!) == .recipe(12))
        #expect(DeepLink(url: URL(string: "spoonmate://cook/7")!) == .cook(7))
        #expect(DeepLink(url: URL(string: "spoonmate://plan")!) == .plan)
        #expect(DeepLink(url: URL(string: "spoonmate://shop")!) == .shopping)
        #expect(DeepLink(url: URL(string: "spoonmate://shopping")!) == .shopping)
        #expect(DeepLink(url: URL(string: "SPOONMATE://Recipe/3")!) == .recipe(3))
        #expect(DeepLink(url: URL(string: "spoonmate:///recipe/5")!) == .recipe(5))
    }

    @Test func rejectsAnythingElse() {
        for text in ["https://recipe/12", "spoonmate://recipe", "spoonmate://recipe/abc", "spoonmate://recipe/0", "spoonmate://recipe/-4",
                     "spoonmate://recipe/1/2", "spoonmate://plan/3", "spoonmate://settings", "spoonmate://"] {
            #expect(DeepLink(url: URL(string: text)!) == nil, "\(text)")
        }
    }

    @Test func linksRoundTrip() {
        for link in [DeepLink.recipe(42), .cook(9), .plan, .shopping] { #expect(DeepLink(url: link.url) == link) }
    }
}

struct SpotlightTests {
    @Test func keywordsHoldTagsAndIngredientNamesWithoutAmountsOrUnits() {
        let words = RecipeEntity.keywords(ingredients: ["400 g tin chickpeas, drained and rinsed", "2 tbsp tahini", "1 cup Greek-style yoghurt"],
                                          tags: ["Dinner", "Vegetarian"])
        #expect(Array(words.prefix(2)) == ["dinner", "vegetarian"])
        #expect(words.contains("chickpeas"))
        #expect(words.contains("tahini"))
        #expect(words.contains("greek-style"))
        #expect(words.contains("yoghurt"))
        for noise in ["400", "tin", "tbsp", "cup", "drained", "and", "rinsed"] { #expect(!words.contains(noise), "\(noise)") }
    }

    @Test func entityFromARecipeCarriesTitleTimesTagsAndIngredients() throws {
        let recipe: RecipeDetail = try fixture("recipe_detail")
        let entity = RecipeEntity(recipe, base: URL(string: "https://recipes.example.com"))
        #expect(entity.id == recipe.id)
        #expect(entity.title == "Shish Barak")
        #expect(entity.subtitle.hasPrefix("Cook "))
        #expect(entity.keywords.contains("dinner"))
        #expect(entity.keywords.contains("flour"))
        #expect(entity.keywords.contains("beef"))
        #expect(entity.searchText.contains("250 g minced beef"))
        let attributes = entity.attributeSet
        #expect(attributes.title == "Shish Barak")
        #expect(attributes.keywords?.contains("flour") == true)
    }

    @Test func subtitlePrefersCookTime() {
        #expect(RecipeEntity.subtitle(prep: "10 min", cook: "30 min", serves: "4") == "Cook 30 min · Serves 4")
        #expect(RecipeEntity.subtitle(prep: "10 min", cook: "", serves: "") == "Prep 10 min")
        #expect(RecipeEntity.subtitle(prep: "", cook: "", serves: "") == "")
    }

    @Test func indexDiffAddsChangedAndRemovesGone() {
        let diff = SpotlightIndexer.diff(current: [1: "a", 2: "b2", 3: "c"], indexed: [1: "a", 2: "b", 4: "d"])
        #expect(diff == SpotlightIndexer.Diff(upsert: [2, 3], delete: [4]))
        #expect(SpotlightIndexer.diff(current: [:], indexed: [:]) == SpotlightIndexer.Diff(upsert: [], delete: []))
    }

    @Test func stampChangesWhenThePictureArrives() throws {
        let recipe: RecipeDetail = try fixture("recipe_detail")
        #expect(SpotlightIndexer.stamp(recipe, hasPicture: false) != SpotlightIndexer.stamp(recipe, hasPicture: true))
    }

    @Test func spotlightIdentifiersGiveTheRecipe() {
        #expect(SpotlightIndexer.recipeID(fromIdentifier: "12") == 12)
        #expect(SpotlightIndexer.recipeID(fromIdentifier: "RecipeEntity/12") == 12)
        #expect(SpotlightIndexer.recipeID(fromIdentifier: "recipe") == nil)
    }

    @Test func recipeSearchRanksTitlesBeforeIngredients() throws {
        var a: RecipeDetail = try fixture("recipe_detail")
        var b = a, c = a
        a.title = "Chickpea curry"
        b = RecipeDetail(copying: b, id: 2, title: "Hummus", ingredients: "chickpeas, tahini")
        c = RecipeDetail(copying: c, id: 3, title: "Pastéis de nata", ingredients: "pastry, custard")
        let found = RecipeQuery.match("chickpea", in: [b, a, c])
        #expect(found.map(\.title) == ["Chickpea curry", "Hummus"])
        #expect(RecipeQuery.match("nata", in: [a, b, c]).map(\.title) == ["Pastéis de nata"])
        #expect(RecipeQuery.match("PASTEIS", in: [a, b, c]).map(\.id) == [3])   // accents and case ignored
        #expect(RecipeQuery.match("  ", in: [a, b, c]).isEmpty)
    }
}

private extension RecipeDetail {
    init(copying r: RecipeDetail, id: Int, title: String, ingredients: String) {
        self.init(id: id, title: title, description: r.description, prepTime: r.prepTime, cookTime: r.cookTime, servings: r.servings,
                  imageUrl: r.imageUrl, thumbUrl: r.thumbUrl, categories: r.categories, isFavorite: r.isFavorite, avgRating: r.avgRating,
                  ratingCount: r.ratingCount, author: r.author, ingredients: ingredients, instructions: r.instructions, notes: r.notes,
                  sourceUrl: r.sourceUrl, ingredientSections: r.ingredientSections, instructionSections: r.instructionSections,
                  shareUrl: r.shareUrl, myRating: r.myRating, madeCount: r.madeCount, lastMade: r.lastMade, nutrition: r.nutrition,
                  collections: r.collections, comments: r.comments, canEdit: r.canEdit, createdAt: r.createdAt, updatedAt: r.updatedAt)
    }
}
