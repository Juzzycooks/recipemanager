import Foundation
import Testing
@testable import RecipeManager

/// Decodes payloads shaped exactly like /api/v1 responses (see API.md).
struct ModelsTests {
    @Test func decodesRecipeDetailAndPythonDates() throws {
        let json = """
        {"id":7,"title":"Soup","description":"","prep_time":"10 min","cook_time":"","servings":"4",
         "image_url":"/admin/uploads/a.jpg","thumb_url":"","categories":[{"id":1,"name":"Dinner"}],
         "is_favorite":true,"avg_rating":4.5,"rating_count":2,"author":{"id":1,"username":"cook"},
         "created_at":"2026-10-01T09:30:00.123456+00:00","updated_at":null,
         "ingredients":"# Base\\n1 onion","instructions":"Boil.","notes":"","source_url":"",
         "ingredient_sections":[{"heading":"Base","lines":["1 onion"]}],
         "instruction_sections":[{"heading":null,"lines":["Boil."]}],
         "share_url":null,"my_rating":null,"made_count":0,"last_made":null,
         "nutrition":{"kcal":300,"protein":5.5,"fat":2.0,"carbs":40.0,"matched":1,"total_lines":1,"servings":4,
                      "per_serving":{"kcal":75,"protein":1.4,"fat":0.5,"carbs":10.0}},
         "collections":[],"comments":[{"id":3,"text":"Yum","created_at":"2026-10-01T09:30:00+00:00","user":{"id":1,"username":"cook"},"can_delete":true}],
         "can_edit":true}
        """
        let recipe = try APIClient.decoder.decode(RecipeDetail.self, from: Data(json.utf8))
        #expect(recipe.title == "Soup")
        #expect(recipe.steps == ["Boil."])
        #expect(recipe.timeSummary == ["Prep 10 min", "Serves 4"])
        #expect(recipe.nutrition?.perServing?.kcal == 75)
        #expect(recipe.comments.first?.createdAt != nil)
    }

    @Test func decodesShoppingAndPlan() throws {
        let shopping = """
        {"store":{"name":"Woolworths","search_url":"https://x/?q={q}"},"aisle_order":["Produce","Other"],
         "items":[{"id":1,"name":"2 onions","checked":false,"recipe_id":null,"aisle":"Produce","store_url":null,"created_at":"2026-10-01T09:30:00+00:00"}]}
        """
        let list = try APIClient.decoder.decode(ShoppingList.self, from: Data(shopping.utf8))
        #expect(list.items.first?.aisle == "Produce")

        let plan = """
        {"from":"2026-09-28","to":"2026-10-04","share_url":null,"entries":[{"id":1,"date":"2026-09-30","meal_type":"dinner","sort_order":0,
         "recipe":{"id":7,"title":"Soup","description":"","prep_time":"","cook_time":"","servings":"","image_url":"","thumb_url":""}}]}
        """
        let week = try APIClient.decoder.decode(PlanWeek.self, from: Data(plan.utf8))
        #expect(week.entries.first?.mealType == .dinner)
    }

    @Test func normalisesServerAddresses() {
        #expect(Session.normalise(server: "recipes.example.com/")?.absoluteString == "https://recipes.example.com")
        #expect(Session.normalise(server: "http://192.168.1.5:5000")?.absoluteString == "http://192.168.1.5:5000")
        #expect(Session.normalise(server: "  ") == nil)
    }

    @Test func dayStringsRoundTrip() {
        let date = Date.fromAPIDay("2026-10-01")
        #expect(date?.apiDay == "2026-10-01")
    }
}

private final class BundleToken {}

/// Real responses captured from a running server (regenerate when API.md changes).
struct ServerFixtureTests {
    private func load<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: name, withExtension: "json"))
        return try APIClient.decoder.decode(T.self, from: Data(contentsOf: url))
    }

    @Test func recipeDetail() throws {
        let r: RecipeDetail = try load("recipe_detail")
        #expect(r.title == "Shish Barak")
        #expect(r.ingredientSections.map(\.heading) == ["Dumplings", "Sauce"])
        #expect(r.steps.count == 4)
        #expect(r.isFavorite && r.myRating == 4 && r.madeCount == 1)
        #expect(r.comments.first?.createdAt != nil)
        #expect(r.categories.first?.name == "Dinner")
    }

    @Test func recipePage() throws {
        let page: Page<RecipeSummary> = try load("recipe_page")
        #expect(page.total == 2 && page.items.count == 2)
    }

    @Test func shopping() throws {
        let list: ShoppingList = try load("shopping")
        #expect(!list.items.isEmpty)
        #expect(list.aisleOrder.last == "Other")
    }

    @Test func mealplan() throws {
        let week: PlanWeek = try load("mealplan")
        #expect(week.entries.first?.mealType == .dinner)
        #expect(week.entries.first?.recipe.title == "Shish Barak")
    }

    @Test func shoppingItemsCarryRecipeTitle() throws {
        let list: ShoppingList = try load("shopping")
        #expect(list.items.contains { $0.recipeTitle == "Shish Barak" })
    }

    @Test func collections() throws {
        let detail: CollectionDetail = try load("collection_detail")
        #expect(detail.name == "Weeknight Dinners")
        #expect(detail.recipes.count == 1 && detail.manualRecipeIds == [detail.recipes[0].id])
        let list: ItemList<CollectionSummary> = try load("collections")
        #expect(list.items.first?.recipeCount == 1)
    }

    @Test func importPreview() throws {
        let preview: ImportPreview = try load("import_preview")
        #expect(preview.kind == "caption")
        #expect(preview.draft.title == "Garlic Bread")
        #expect(preview.draft.ingredients.contains("garlic"))
    }

    @Test func deviceTokens() throws {
        let tokens: ItemList<DeviceToken> = try load("tokens")
        #expect(tokens.items.contains { $0.current })
    }

    @Test func detectsTimerMinutes() {
        #expect(CookTimer.detectMinutes(in: "Cook for 1–2 minutes until fragrant.") == 2)
        #expect(CookTimer.detectMinutes(in: "Simmer 20 min.") == 20)
        #expect(CookTimer.detectMinutes(in: "Bake for 1 hour") == 60)
        #expect(CookTimer.detectMinutes(in: "Stir well.") == nil)
    }

    @MainActor @Test func themeChoiceIsSavedAndRestored() {
        let store = ThemeStore.shared
        let original = store.theme
        defer { store.theme = original }
        store.theme = .ocean
        #expect(UserDefaults.standard.string(forKey: AppTheme.storageKey) == "ocean")
        #expect(AppTheme.allCases.count == 5)
        #expect(Set(AppTheme.allCases.map(\.rawValue)).count == 5)
    }

    @Test func login() throws {
        let response: LoginResponse = try load("login")
        #expect(response.user.username == "chef")
    }
}

@Suite struct HTMLEntitiesTests {
    @Test func decodesCommonEntities() {
        #expect(HTMLEntities.decode("&quot;Besciamella&quot; that&#39;s it&nbsp;") == "\"Besciamella\" that's it ")
        #expect(HTMLEntities.decode("Salad &amp; Pasta &#x2013; &frac12; cup") == "Salad & Pasta – ½ cup")
        #expect(HTMLEntities.decode("Fish & chips; 5 > 3 &unknown; ok") == "Fish & chips; 5 > 3 &unknown; ok")
    }

    @Test func cleansResponsesAndLeavesPlainOnesAlone() throws {
        let plain = Data(#"{"title":"Soup","n":2.5}"#.utf8)
        #expect(HTMLEntities.clean(plain) == plain)
        let dirty = Data(#"{"title":"Mac &amp; Cheese","tags":["it&#39;s"],"n":3}"#.utf8)
        let obj = try #require(try JSONSerialization.jsonObject(with: HTMLEntities.clean(dirty)) as? [String: Any])
        #expect(obj["title"] as? String == "Mac & Cheese")
        #expect((obj["tags"] as? [String]) == ["it's"])
        #expect(obj["n"] as? Int == 3)
    }
}

struct UnitConversionTests {
    private func metric(_ s: String) -> String { UnitConversion.convert(s, to: .metric) }
    private func us(_ s: String) -> String { UnitConversion.convert(s, to: .imperial) }

    @Test func weightsToMetric() {
        #expect(metric("1 lb chicken thighs") == "450 g chicken thighs")
        #expect(metric("2 lb potatoes") == "910 g potatoes")
        #expect(metric("4 oz cheddar, grated") == "110 g cheddar, grated")
        #expect(metric("5 lb beef") == "2.25 kg beef")
    }

    @Test func volumesToMetric() {
        #expect(metric("1 cup rice") == "240 ml rice")
        #expect(metric("1 1/2 tbsp honey") == "1 1/2 tbsp honey")   // spoons stay spoons
        #expect(metric("1/2 tsp salt") == "1/2 tsp salt")
        #expect(us("15 ml soy sauce") == "1 tbsp soy sauce")
        #expect(metric("8 fl oz milk") == "240 ml milk")
        #expect(metric("8 oz milk") == "240 ml milk")
    }

    @Test func toImperial() {
        #expect(us("500 g flour") == "1 lb flour")
        #expect(us("250 ml cream") == "1 cup cream")
        #expect(us("1 kg onions") == "2 ¼ lb onions")
    }

    @Test func rangesAndFractionGlyphs() {
        #expect(metric("2-3 lb brisket") == "0.9–1.35 kg brisket")
        #expect(metric("½ cup oil") == "120 ml oil")
    }

    @Test func prefersTheFigureTheRecipeAlreadyGives() {
        #expect(metric("1 lb (450 g) flour") == "450 g flour")
        #expect(us("450 g (1 lb) flour") == "1 lb flour")
    }

    @Test func temperatures() {
        #expect(metric("Bake at 350°F for 20 minutes.") == "Bake at 175°C for 20 minutes.")
        #expect(metric("Heat the oven to 400 degrees F") == "Heat the oven to 205°C")
        #expect(metric("preheat to 350°F (180°C)") == "preheat to 180°C")
        #expect(us("Bake at 180°C") == "Bake at 355°F")
    }

    @Test func leavesEverythingElseAlone() {
        #expect(metric("3 eggs") == "3 eggs")
        #expect(metric("a pinch of salt") == "a pinch of salt")
        #expect(metric("250 g flour") == "250 g flour")
        #expect(metric("2 garlic cloves") == "2 garlic cloves")
        #expect(UnitConversion.convert("1 lb beef", to: .original) == "1 lb beef")
    }
}
