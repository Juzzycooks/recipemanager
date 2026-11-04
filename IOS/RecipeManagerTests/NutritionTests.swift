import Foundation
import Testing
@testable import RecipeManager

private final class NutritionFixtureToken {}

/// `calories_per_serving`, `nutrition_facts` and import `source_nutrition`: tolerant decoding, the recipe page's
/// wording, and what the editor sends.
struct NutritionTests {
    private let en = Locale(identifier: "en_US")

    /// A recipe as an older server sends it (no new keys), with `extra` merged in at the top level.
    private func recipeJSON(_ extra: String = "") -> Data {
        Data("""
        {"id":7,"title":"Soup","description":"","prep_time":"","cook_time":"","servings":"4",
         "image_url":"","thumb_url":"","categories":[],"is_favorite":false,"avg_rating":null,"rating_count":0,
         "ingredients":"1 onion","instructions":"Boil.","notes":"","source_url":"",
         "ingredient_sections":[{"heading":null,"lines":["1 onion"]}],"instruction_sections":[{"heading":null,"lines":["Boil."]}],
         "share_url":null,"my_rating":null,"made_count":0,"last_made":null,
         "nutrition":{"kcal":2080,"protein":120,"fat":80,"carbs":200,"matched":1,"total_lines":1,"servings":4,
                      "per_serving":{"kcal":520,"protein":30,"fat":20,"carbs":50}},
         "collections":[],"comments":[],"can_edit":true\(extra.isEmpty ? "" : ",")\(extra)}
        """.utf8)
    }

    private func decode(_ extra: String = "") throws -> RecipeDetail {
        try APIClient.decoder.decode(RecipeDetail.self, from: recipeJSON(extra))
    }

    // MARK: Decoding

    /// `calories_per_serving` of any shape never fails the recipe.
    @Test(arguments: [
        ("450", 450), ("450.4", 450), ("\"450\"", 450), ("\"450 kcal\"", 450), ("\" 380.6 \"", 381),
        ("null", nil), ("\"\"", nil), ("\"lots\"", nil), ("-5", nil), ("99999", nil), ("true", nil),
        ("[450]", nil), ("{\"kcal\":450}", nil),
    ] as [(String, Int?)])
    func toleratesAnyCaloriesValue(raw: String, expected: Int?) throws {
        let r = try decode("\"calories_per_serving\":\(raw)")
        #expect(r.caloriesPerServing == expected)
        #expect(r.title == "Soup")
    }

    @Test func caloriesSurviveTheOfflineRoundTrip() throws {
        var r = try decode("\"calories_per_serving\":\"450 kcal\"")
        let again = try APIClient.decoder.decode(RecipeDetail.self, from: APIClient.encoder.encode(r))
        #expect(again.caloriesPerServing == 450)
        r.caloriesPerServing = nil
        let cleared = try APIClient.decoder.decode(RecipeDetail.self, from: APIClient.encoder.encode(r))
        #expect(cleared.caloriesPerServing == nil)
    }

    @Test func olderServerWithoutTheNewKeys() throws {
        let r = try decode()
        #expect(r.caloriesPerServing == nil)
        #expect(r.nutritionFacts == nil)
        let s = try #require(NutritionSummary(recipe: r, locale: en))
        #expect(s.headline == "520" && s.headlineUnit == "kcal per serving")
        #expect(s.totalLine == "2,080 kcal whole recipe · serves 4")
        #expect(s.sourceLabel == "Estimate")
        #expect(!s.canExplain)
    }

    @Test func fixtureWithTheFullEstimate() throws {
        let url = try #require(Bundle(for: NutritionFixtureToken.self).url(forResource: "recipe_detail_nutrition", withExtension: "json"))
        let r = try APIClient.decoder.decode(RecipeDetail.self, from: Data(contentsOf: url))
        let f = try #require(r.nutritionFacts)
        #expect(f.source == .estimate && f.servings == 4 && f.yieldUnit == "serving")
        #expect(f.perServing?.kcal == 755 && f.total?.kcal == 3021)
        let e = try #require(f.estimate)
        #expect(e.confidence == .medium && e.countedLines == 6 && e.totalLines == 7 && e.lines.count == 7)
        #expect(e.lines.last?.status == .unmatched && e.lines.last?.food == nil)
        #expect(NutritionSummary.countedLine(e) == "Counted 6 of 7 ingredients")
        let s = try #require(NutritionSummary(recipe: r, locale: en))
        #expect(s.sourceLabel == "Estimate · medium confidence")
        #expect(s.canExplain && s.explainTitle == "How this was estimated")
    }

    /// A real `GET /recipes/{id}` from the server (tests/test_api_v1.py app, bolognese serves 4), so the app and the
    /// server can't drift apart on the contract.
    @Test func realServerResponse() throws {
        let url = try #require(Bundle(for: NutritionFixtureToken.self).url(forResource: "recipe_detail_nutrition_server", withExtension: "json"))
        let r = try APIClient.decoder.decode(RecipeDetail.self, from: Data(contentsOf: url))
        #expect(r.caloriesPerServing == nil)
        #expect(r.nutrition?.perServing?.kcal == 795)
        let f = try #require(r.nutritionFacts)
        #expect(f.source == .estimate && f.servings == 4 && f.yieldUnit == "serving")
        #expect(f.perServing?.kcal == 795 && f.total?.kcal == 3180)
        let e = try #require(f.estimate)
        #expect(e.confidence == .high && e.countedLines == 8 && e.totalLines == 10 && e.lines.count == 10)
        let s = try #require(NutritionSummary(recipe: r, locale: en))
        #expect(s.sourceLabel == "Estimate · high confidence")
    }

    @Test func manualSource() throws {
        let r = try decode("""
        "calories_per_serving":450,
        "nutrition_facts":{"source":"manual","servings":4,"yield_unit":"serving",
          "per_serving":{"kcal":450,"protein":null,"fat":null,"carbs":null},
          "total":{"kcal":1800,"protein":null,"fat":null,"carbs":null},
          "estimate":{"kcal":2080,"protein":120,"fat":80,"carbs":200,"confidence":"high","matched":1,"counted_lines":1,"total_lines":1,
                      "lines":[{"text":"1 onion","food":"onion","grams":150,"kcal":60,"status":"matched"}]}}
        """)
        #expect(r.caloriesPerServing == 450)
        let s = try #require(NutritionSummary(recipe: r, locale: en))
        #expect(s.headline == "450" && s.totalLine == "1,800 kcal whole recipe · serves 4")
        #expect(s.sourceLabel == "You entered")
        #expect(s.macros.isEmpty && s.macrosBasis == nil)   // null macros are hidden, not shown as 0
        #expect(s.canExplain && s.explainTitle == "See our estimate")
    }

    @Test func recipeSourceWithCookies() throws {
        let r = try decode("""
        "calories_per_serving":null,
        "nutrition_facts":{"source":"recipe","servings":12,"yield_unit":"cookies",
          "per_serving":{"kcal":150,"protein":2,"fat":null,"carbs":20},"total":null,"estimate":null}
        """)
        let s = try #require(NutritionSummary(recipe: r, locale: en))
        #expect(s.headlineUnit == "kcal per cookie")
        #expect(s.headlineSpoken == "150 calories per cookie")
        #expect(s.totalLine == "1,800 kcal whole recipe · makes 12 cookies")
        #expect(s.macros.map(\.name) == ["Protein", "Carbs"])
        #expect(s.macrosBasis == "Per cookie")
        #expect(s.sourceLabel == "From the recipe")
        #expect(!s.canExplain)
    }

    @Test func unknownStringsDoNotBreakDecoding() throws {
        let r = try decode("""
        "nutrition_facts":{"source":"lab-tested","servings":2,"yield_unit":"serving",
          "per_serving":{"kcal":300,"protein":10,"fat":5,"carbs":40},"total":{"kcal":600,"protein":20,"fat":10,"carbs":80},
          "estimate":{"kcal":600,"protein":20,"fat":10,"carbs":80,"confidence":"very high","matched":1,"counted_lines":1,"total_lines":2,
                      "lines":[{"text":"1 onion","food":"onion","grams":150,"kcal":60,"status":"guessed"},
                               {"text":"magic","status":"unmatched"}]}}
        """)
        let f = try #require(r.nutritionFacts)
        #expect(f.source?.rawValue == "lab-tested")
        #expect(f.estimate?.confidence?.rawValue == "very high")
        #expect(f.estimate?.lines.first?.status?.rawValue == "guessed")
        let s = try #require(NutritionSummary(recipe: r, locale: en))
        #expect(s.headline == "300" && s.sourceLabel == nil)
        // An unknown status with a figure still shows the figure.
        let rows = NutritionSummary.explainedLines(try #require(f.estimate), locale: en)
        #expect(rows.first?.value == "60 kcal" && rows.first?.note == nil)
        #expect(rows.last?.value == "—" && rows.last?.note == "not recognised")
    }

    @Test(arguments: [
        #""nutrition_facts":"oops""#,
        #""nutrition_facts":[1,2,3]"#,
        #""nutrition_facts":{"source":7,"servings":"four","per_serving":"lots","total":[],"estimate":{"lines":"none","kcal":"x"}}"#,
        #""nutrition_facts":{"estimate":{"kcal":100,"lines":[{"text":"ok","kcal":100,"status":"matched"},42,{"text":5}]}}"#,
    ])
    func malformedFactsNeverBreakTheRecipe(_ extra: String) throws {
        let r = try decode(extra)
        #expect(r.title == "Soup")
        #expect(NutritionSummary(recipe: r, locale: en) != nil)   // falls back to `nutrition`, or reads what it can
    }

    @Test func malformedFactsFallBackToTheOldEstimate() throws {
        let r = try decode(#""nutrition_facts":{"source":7,"per_serving":"lots"}"#)
        #expect(r.nutritionFacts?.hasFigures == false)
        let s = try #require(NutritionSummary(recipe: r, locale: en))
        #expect(s.headline == "520" && s.sourceLabel == "Estimate")
    }

    @Test func oddLinesAreDroppedOneByOne() throws {
        let r = try decode(#""nutrition_facts":{"estimate":{"kcal":100,"lines":[{"text":"ok","kcal":100,"status":"matched"},42,{"text":5}]}}"#)
        #expect(r.nutritionFacts?.estimate?.lines.map(\.text) == ["ok"])
    }

    @Test func nullFactsAndNullCalories() throws {
        let r = try decode(#""calories_per_serving":null,"nutrition_facts":null"#)
        #expect(r.caloriesPerServing == nil && r.nutritionFacts == nil)
    }

    @Test func newFieldsSurviveTheOfflineLibraryRoundTrip() throws {
        let url = try #require(Bundle(for: NutritionFixtureToken.self).url(forResource: "recipe_detail_nutrition", withExtension: "json"))
        var r = try APIClient.decoder.decode(RecipeDetail.self, from: Data(contentsOf: url))
        r.caloriesPerServing = 640
        // OfflineStore keeps the library re-encoded with the API encoder and reads it back with the API decoder.
        let again = try APIClient.decoder.decode([RecipeDetail].self, from: APIClient.encoder.encode([r]))
        #expect(again.first?.nutritionFacts == r.nutritionFacts && again.first?.nutritionFacts != nil)
        #expect(again.first?.caloriesPerServing == 640)
        let object = try #require(try JSONSerialization.jsonObject(with: APIClient.encoder.encode(r)) as? [String: Any])
        #expect(object["calories_per_serving"] as? Int == 640)
        let facts = try #require(object["nutrition_facts"] as? [String: Any])
        #expect(facts["yield_unit"] as? String == "serving")
        #expect((facts["estimate"] as? [String: Any])?["counted_lines"] as? Int == 6)
    }

    @Test func importPreviewCarriesSourceNutrition() throws {
        let json = """
        {"kind":"url","draft":{"title":"Pie","description":"","ingredients":"","instructions":"","notes":"","servings":"",
         "prep_time":"","cook_time":""},"source_url":"https://x","image_name":"","image_url":"","raw_text":"","warning":"","source_nutrition":{"kcal":350,"protein":null,"fat":12.5,"carbs":null,"serving_size":"1 slice"}}
        """
        let p = try APIClient.decoder.decode(ImportPreview.self, from: Data(json.utf8))
        #expect(p.sourceNutrition == SourceNutrition(kcal: 350, fat: 12.5, servingSize: "1 slice"))
        let old = try APIClient.decoder.decode(ImportPreview.self, from: Data(json.replacingOccurrences(of: #","source_nutrition":{"kcal":350,"protein":null,"fat":12.5,"carbs":null,"serving_size":"1 slice"}"#, with: "").utf8))
        #expect(old.sourceNutrition == nil)
        let odd = try APIClient.decoder.decode(ImportPreview.self, from: Data(json.replacingOccurrences(of: #""kcal":350"#, with: #""kcal":"lots""#).utf8))
        #expect(odd.sourceNutrition?.kcal == nil && odd.sourceNutrition?.fat == 12.5)

        // Passed back to /import/save as it came, nulls and all.
        let body = ImportSaveBody(draft: RecipeDraft(), imageName: "", useImage: false, sourceNutrition: p.sourceNutrition)
        let sent = try #require(try JSONSerialization.jsonObject(with: APIClient.encoder.encode(body)) as? [String: Any])
        let nutrition = try #require(sent["source_nutrition"] as? [String: Any])
        #expect(nutrition["kcal"] as? Double == 350 && nutrition["serving_size"] as? String == "1 slice")
        #expect(nutrition["protein"] is NSNull)
        let none = try #require(try JSONSerialization.jsonObject(with: APIClient.encoder.encode(
            ImportSaveBody(draft: RecipeDraft(), imageName: "", useImage: false))) as? [String: Any])
        #expect(none["source_nutrition"] == nil)
    }

    // MARK: Display

    @Test func scalingMultipliesTheWholeRecipeOnly() throws {
        let r = try decode()
        let double = try #require(NutritionSummary(recipe: r, scale: 2, locale: en))
        #expect(double.headline == "520")
        #expect(double.totalLine == "4,160 kcal whole recipe · serves 8")
        let half = try #require(NutritionSummary(recipe: r, scale: 0.5, locale: en))
        #expect(half.totalLine == "1,040 kcal whole recipe · serves 2")
        #expect(half.macros.first == .init(name: "Protein", grams: "30 g"))   // per serving: unscaled
    }

    @Test func wholeRecipeOnlyScalesTheHeadlineAndMacros() throws {
        let facts = NutritionFacts(source: .estimate, servings: nil, yieldUnit: "serving",
                                   total: .init(kcal: 1000, protein: 40, fat: nil, carbs: 100),
                                   estimate: .init(kcal: 1000, confidence: .low, countedLines: 3, totalLines: 5))
        let s = try #require(NutritionSummary(facts: facts, scale: 3, locale: en))
        #expect(s.headline == "3,000" && s.headlineUnit == "kcal whole recipe" && s.totalLine == nil)
        #expect(s.macros == [.init(name: "Protein", grams: "120 g"), .init(name: "Carbs", grams: "300 g")])
        #expect(s.macrosBasis == "Whole recipe")
        #expect(s.sourceLabel == "Estimate · low confidence")
    }

    @Test func perServingIsDerivedWhenOnlyTheTotalAndServingsAreKnown() throws {
        let facts = NutritionFacts(source: .estimate, servings: 4, total: .init(kcal: 2000, protein: 80))
        let s = try #require(NutritionSummary(facts: facts, locale: en))
        #expect(s.headline == "500" && s.totalLine == "2,000 kcal whole recipe · serves 4")
        #expect(s.macros == [.init(name: "Protein", grams: "20 g")] && s.macrosBasis == "Per serving")
    }

    @Test func nothingToShow() {
        #expect(NutritionSummary(facts: NutritionFacts(source: .estimate, servings: 4)) == nil)
    }

    @Test func yieldWording() {
        #expect(NutritionSummary.singular(nil) == "serving")
        #expect(NutritionSummary.singular("servings") == "serving")
        #expect(NutritionSummary.singular("cookies") == "cookie")
        #expect(NutritionSummary.singular("Loaves") == "loaf")
        #expect(NutritionSummary.singular("patties") == "patty")
        #expect(NutritionSummary.singular("sandwiches") == "sandwich")
        #expect(NutritionSummary.singular("small cakes") == "small cake")
        #expect(NutritionSummary.singular("muffin") == "muffin")
        #expect(NutritionSummary.yield(4, unit: "serving", locale: en) == "serves 4")
        #expect(NutritionSummary.yield(24, unit: "cookies", locale: en) == "makes 24 cookies")
        #expect(NutritionSummary.yield(1, unit: "loaves", locale: en) == "makes 1 loaf")
        #expect(NutritionSummary.yield(2, unit: "loaf", locale: en) == "makes 2 loaves")
        #expect(NutritionSummary.yield(1.5, unit: "serving", locale: en) == "serves 1.5")
        #expect(NutritionSummary.yield(6, unit: "patties", locale: en) == "makes 6 patties")
    }

    @Test func explainedLines() {
        let e = NutritionFacts.Estimate(kcal: 970, countedLines: 2, totalLines: 3, lines: [
            .init(text: "2 cups flour", food: "wheat flour", grams: 250, kcal: 910, status: .matched),
            .init(text: "salt", food: "salt", grams: nil, kcal: 0, status: .negligible),
            .init(text: "1 bunch mint", status: .unmatched),
        ])
        let rows = NutritionSummary.explainedLines(e, locale: en)
        #expect(rows.map(\.value) == ["910 kcal", "—", "—"])
        #expect(rows.map(\.note) == [nil, "not counted", "not recognised"])
        #expect(rows[0].detail == "wheat flour · 250 g")
        #expect(rows[0].spoken == "2 cups flour, read as wheat flour, 250 grams, 910 calories")
        #expect(rows[2].spoken == "1 bunch mint, not recognised")
        #expect(NutritionSummary.countedLine(e) == "Counted 2 of 3 ingredients")
    }

    // MARK: Editor

    @Test func draftAlwaysSendsCaloriesPerServing() throws {
        var draft = RecipeDraft(title: "Soup", description: "", ingredients: "", instructions: "", prepTime: "", cookTime: "",
                                servings: "4", sourceUrl: "", notes: "", categoryIds: [], caloriesPerServing: 450)
        var sent = try #require(try JSONSerialization.jsonObject(with: APIClient.encoder.encode(draft)) as? [String: Any])
        #expect(sent["calories_per_serving"] as? Int == 450)
        #expect(sent["title"] as? String == "Soup" && sent["category_ids"] as? [Int] == [])
        draft.caloriesPerServing = nil   // cleared: an explicit null clears it on the server
        sent = try #require(try JSONSerialization.jsonObject(with: APIClient.encoder.encode(draft)) as? [String: Any])
        #expect(sent.keys.contains("calories_per_serving") && sent["calories_per_serving"] is NSNull)
    }

    @Test func draftLoadsCaloriesFromTheRecipe() throws {
        let r = try decode(#""calories_per_serving":380"#)
        #expect(RecipeDraft(r).caloriesPerServing == 380)
    }

    @Test func caloriesFieldParsing() {
        #expect(RecipeDraft.calories(from: "") == nil)
        #expect(RecipeDraft.calories(from: "  ") == nil)
        #expect(RecipeDraft.calories(from: "450") == 450)
        #expect(RecipeDraft.calories(from: "1,200 kcal") == 1200)
        #expect(RecipeDraft.calories(from: "abc") == nil)
    }

    @Test func editorHints() {
        #expect(RecipeEditorHints.calories(source: SourceNutrition(kcal: 350), facts: nil)
                == "The recipe lists 350 kcal per serving. Leave Calories per serving empty to use that.")
        #expect(RecipeEditorHints.calories(source: SourceNutrition(fat: 3), facts: nil) == nil)
        let estimate = NutritionFacts(source: .estimate, servings: 4, perServing: .init(kcal: 519.6))
        #expect(RecipeEditorHints.calories(source: nil, facts: estimate) == "Estimated at about 520 kcal per serving from the ingredients.")
        let manual = NutritionFacts(source: .manual, servings: 4, perServing: .init(kcal: 450))
        #expect(RecipeEditorHints.calories(source: nil, facts: manual) == nil)
    }
}
