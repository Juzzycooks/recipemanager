import Foundation

// Mirrors /api/v1 (see API.md). Keys are snake_case on the wire; APIClient converts them.

struct User: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let username: String
    var email: String?
    var isAdmin: Bool?
    var createdAt: Date?
}

struct Category: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct Page<T: Decodable & Sendable>: Decodable, Sendable {
    let items: [T]
    let page: Int
    let perPage: Int
    let total: Int
    let pages: Int
}

struct ItemList<T: Decodable & Sendable>: Decodable, Sendable {
    let items: [T]
}

struct LoginResponse: Decodable, Sendable {
    let token: String
    let user: User
}

struct SiteInfo: Decodable, Sendable {
    let apiVersion: Int
    let name: String
    let setupRequired: Bool
    let ocrAvailable: Bool
}

/// Card-sized recipe: what the shelf, collections and search results show.
struct RecipeSummary: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    var title: String
    var description: String
    var prepTime: String
    var cookTime: String
    var servings: String
    var imageUrl: String
    var thumbUrl: String
    var categories: [Category]
    var isFavorite: Bool
    var avgRating: Double?
    var ratingCount: Int
    var author: User?
    var createdAt: Date?
    var updatedAt: Date?
}

/// The bare minimum a meal-plan entry carries.
struct RecipeBrief: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let title: String
    let description: String
    let prepTime: String
    let cookTime: String
    let servings: String
    let imageUrl: String
    let thumbUrl: String
}

struct RecipeSection: Codable, Sendable, Hashable, Identifiable {
    let heading: String?
    let lines: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        heading = try c.decodeIfPresent(String.self, forKey: .heading)
        // Imports from recipe sites can leave a checkbox glyph at the start of a line; it would sit beside our own tick box.
        lines = try c.decode([String].self, forKey: .lines).map {
            $0.replacingOccurrences(of: "^(?:[-–—•*]\\s*)?[▢☐□◻☑✓✔]+\\s*", with: "", options: .regularExpression)
        }
    }
    init(heading: String?, lines: [String]) { self.heading = heading; self.lines = lines }
    var id: String { (heading ?? "") + "|" + lines.joined(separator: "\n") }
}

struct Nutrition: Codable, Sendable, Hashable {
    struct Amounts: Codable, Sendable, Hashable { let kcal: Double; let protein: Double; let fat: Double; let carbs: Double }
    let kcal: Double
    let protein: Double
    let fat: Double
    let carbs: Double
    let servings: Int?
    let perServing: Amounts?
}

/// `nutrition_facts` on a recipe: the figures to show (per serving and whole recipe), where they came from, and the
/// estimate's working. Every field is optional and read leniently, and unknown `source` / `confidence` / `status`
/// strings are kept as they are, so a newer or odd server never fails the recipe.
struct NutritionFacts: Codable, Sendable, Hashable {
    /// A server string we compare against known values without failing on new ones.
    struct Source: RawRepresentable, Codable, Sendable, Hashable {
        let rawValue: String
        init(rawValue: String) { self.rawValue = rawValue }
        static let manual = Source(rawValue: "manual")
        static let recipe = Source(rawValue: "recipe")
        static let estimate = Source(rawValue: "estimate")
    }
    struct Confidence: RawRepresentable, Codable, Sendable, Hashable {
        let rawValue: String
        init(rawValue: String) { self.rawValue = rawValue }
        static let high = Confidence(rawValue: "high")
        static let medium = Confidence(rawValue: "medium")
        static let low = Confidence(rawValue: "low")
    }
    struct LineStatus: RawRepresentable, Codable, Sendable, Hashable {
        let rawValue: String
        init(rawValue: String) { self.rawValue = rawValue }
        static let matched = LineStatus(rawValue: "matched")
        static let negligible = LineStatus(rawValue: "negligible")
        static let unmatched = LineStatus(rawValue: "unmatched")
    }

    struct Amounts: Codable, Sendable, Hashable {
        var kcal: Double?
        var protein: Double?
        var fat: Double?
        var carbs: Double?

        init(kcal: Double? = nil, protein: Double? = nil, fat: Double? = nil, carbs: Double? = nil) {
            self.kcal = kcal; self.protein = protein; self.fat = fat; self.carbs = carbs
        }
        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            kcal = c.lenient(Double.self, .kcal); protein = c.lenient(Double.self, .protein)
            fat = c.lenient(Double.self, .fat); carbs = c.lenient(Double.self, .carbs)
        }
        var isEmpty: Bool { kcal == nil && protein == nil && fat == nil && carbs == nil }
    }

    /// One ingredient line as the estimate read it.
    struct Line: Codable, Sendable, Hashable {
        var text = ""
        var food: String?
        var grams: Double?
        var kcal: Double?
        var status: LineStatus?

        init(text: String, food: String? = nil, grams: Double? = nil, kcal: Double? = nil, status: LineStatus? = nil) {
            self.text = text; self.food = food; self.grams = grams; self.kcal = kcal; self.status = status
        }
        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            text = c.lenient(String.self, .text) ?? ""
            food = c.lenient(String.self, .food); grams = c.lenient(Double.self, .grams)
            kcal = c.lenient(Double.self, .kcal); status = c.lenient(LineStatus.self, .status)
        }
    }

    /// The ingredient-based estimate, for the whole recipe.
    struct Estimate: Codable, Sendable, Hashable {
        var kcal: Double?
        var protein: Double?
        var fat: Double?
        var carbs: Double?
        var confidence: Confidence?
        var matched: Int?
        var countedLines: Int?
        var totalLines: Int?
        var lines: [Line] = []

        init(kcal: Double? = nil, confidence: Confidence? = nil, countedLines: Int? = nil, totalLines: Int? = nil, lines: [Line] = []) {
            self.kcal = kcal; self.confidence = confidence; self.countedLines = countedLines; self.totalLines = totalLines; self.lines = lines
        }
        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            kcal = c.lenient(Double.self, .kcal); protein = c.lenient(Double.self, .protein)
            fat = c.lenient(Double.self, .fat); carbs = c.lenient(Double.self, .carbs)
            confidence = c.lenient(Confidence.self, .confidence)
            matched = c.lenientInt(.matched); countedLines = c.lenientInt(.countedLines); totalLines = c.lenientInt(.totalLines)
            // One odd line drops only itself (Line never throws; a non-array reads as no lines).
            lines = (c.lenient([Line].self, .lines) ?? []).filter { !$0.text.isEmpty }
        }
        var amounts: Amounts { Amounts(kcal: kcal, protein: protein, fat: fat, carbs: carbs) }
    }

    var source: Source?
    var servings: Int?
    var yieldUnit: String?
    var perServing: Amounts?
    var total: Amounts?
    var estimate: Estimate?

    init(source: Source? = nil, servings: Int? = nil, yieldUnit: String? = nil, perServing: Amounts? = nil,
         total: Amounts? = nil, estimate: Estimate? = nil) {
        self.source = source; self.servings = servings; self.yieldUnit = yieldUnit
        self.perServing = perServing; self.total = total; self.estimate = estimate
    }

    init(from decoder: Decoder) throws {
        // Never throws: a block that isn't an object (or fields of the wrong type) just reads as missing.
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        source = c.lenient(Source.self, .source)
        servings = c.lenientInt(.servings)
        yieldUnit = c.lenient(String.self, .yieldUnit)
        perServing = c.lenient(Amounts.self, .perServing).flatMap { $0.isEmpty ? nil : $0 }
        total = c.lenient(Amounts.self, .total).flatMap { $0.isEmpty ? nil : $0 }
        estimate = c.lenient(Estimate.self, .estimate)
    }

    /// True when there is a calorie figure to show.
    var hasFigures: Bool { perServing?.kcal != nil || total?.kcal != nil || estimate?.kcal != nil }
}

extension KeyedDecodingContainer {
    /// The value, or nil when the key is missing, null or the wrong type.
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
    /// A count that may arrive as 4 or 4.0.
    func lenientInt(_ key: Key) -> Int? {
        lenient(Int.self, key) ?? lenient(Double.self, key).flatMap { $0.isFinite ? Int($0.rounded()) : nil }
    }

    /// A missing key is nil too (the synthesised decoder would otherwise throw for a wrapped property).
    func decode(_ type: LenientCalories.Type, forKey key: Key) throws -> LenientCalories {
        try decodeIfPresent(type, forKey: key) ?? LenientCalories(wrappedValue: nil)
    }
}

/// A calorie count that never fails the decode of what holds it: 450, 450.0, "450" or "450 kcal" read as 450;
/// null, negative, absurd or anything else reads as nil. Encodes as a plain number or null.
@propertyWrapper
struct LenientCalories: Codable, Sendable, Hashable {
    var wrappedValue: Int?

    init(wrappedValue: Int?) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        wrappedValue = Self.read((try? decoder.singleValueContainer()).flatMap(Self.value))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let wrappedValue { try c.encode(wrappedValue) } else { try c.encodeNil() }
    }

    private static func value(_ c: SingleValueDecodingContainer) -> Double? {
        if c.decodeNil() { return nil }
        if let i = try? c.decode(Int.self) { return Double(i) }
        if let d = try? c.decode(Double.self) { return d }
        guard let s = try? c.decode(String.self) else { return nil }
        // "450", "450 kcal", " 450.5 " — the leading number only.
        let number = s.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber || $0 == "." }
        return Double(number)
    }

    private static func read(_ d: Double?) -> Int? {
        guard let d, d.isFinite, d >= 0, d <= 20_000 else { return nil }   // the server's own limit is 0–20000
        return Int(d.rounded())
    }
}

struct RecipeComment: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let text: String
    let createdAt: Date?
    let user: User?
    let canDelete: Bool
}

struct CollectionRef: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct RecipeDetail: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    var title: String
    var description: String
    var prepTime: String
    var cookTime: String
    var servings: String
    var imageUrl: String
    var thumbUrl: String
    var categories: [Category]
    var isFavorite: Bool
    var avgRating: Double?
    var ratingCount: Int
    var author: User?
    var ingredients: String
    var instructions: String
    var notes: String
    var sourceUrl: String
    var ingredientSections: [RecipeSection]
    var instructionSections: [RecipeSection]
    var shareUrl: String?
    var myRating: Int?
    var madeCount: Int
    var lastMade: Date?
    var nutrition: Nutrition?
    var collections: [CollectionRef]
    var comments: [RecipeComment]
    var canEdit: Bool
    var createdAt: Date?
    var updatedAt: Date?
    /// What the cook typed in the editor (nil when not set). Older servers don't send it, and a value of the wrong
    /// type reads as nil instead of failing the whole recipe.
    @LenientCalories var caloriesPerServing: Int? = nil
    /// The figures to show and where they came from (newer servers). Decodes leniently: a bad block reads as empty
    /// (`hasFigures == false`) rather than failing the recipe, and the page falls back to `nutrition`.
    var nutritionFacts: NutritionFacts?

    var steps: [String] { instructionSections.flatMap(\.lines) }
    var timeSummary: [String] {
        [prepTime.isEmpty ? nil : "Prep \(prepTime)", cookTime.isEmpty ? nil : "Cook \(cookTime)",
         servings.isEmpty ? nil : "Serves \(servings)"].compactMap { $0 }
    }
}

/// Fields for creating or editing a recipe (PATCH takes any subset; the editor sends them all).
struct RecipeDraft: Codable, Sendable, Hashable {
    var title = ""
    var description = ""
    var ingredients = ""
    var instructions = ""
    var prepTime = ""
    var cookTime = ""
    var servings = ""
    var sourceUrl = ""
    var notes = ""
    var categoryIds: [Int] = []
    /// Sent as `null` when empty, so clearing the field clears it on the server.
    var caloriesPerServing: Int?

    init() {}
    init(_ r: RecipeDetail) {
        title = r.title; description = r.description; ingredients = r.ingredients; instructions = r.instructions
        prepTime = r.prepTime; cookTime = r.cookTime; servings = r.servings; sourceUrl = r.sourceUrl
        notes = r.notes; categoryIds = r.categories.map(\.id); caloriesPerServing = r.caloriesPerServing
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title); try c.encode(description, forKey: .description)
        try c.encode(ingredients, forKey: .ingredients); try c.encode(instructions, forKey: .instructions)
        try c.encode(prepTime, forKey: .prepTime); try c.encode(cookTime, forKey: .cookTime)
        try c.encode(servings, forKey: .servings); try c.encode(sourceUrl, forKey: .sourceUrl)
        try c.encode(notes, forKey: .notes); try c.encode(categoryIds, forKey: .categoryIds)
        try c.encode(caloriesPerServing, forKey: .caloriesPerServing)   // explicit null, unlike synthesised encodeIfPresent
    }

    /// The editor's "Calories per serving" text as a number: empty (or nonsense) is "not set".
    static func calories(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "kcal", with: "")
            .replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), value.isFinite, value >= 0, value < 100_000 else { return nil }
        return Int(value.rounded())
    }
}

// MARK: Shopping

struct ShoppingItem: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    var name: String
    var checked: Bool
    let recipeId: Int?
    let recipeTitle: String?
    let aisle: String
    let storeUrl: String?
}

struct ShoppingList: Codable, Sendable {
    struct Store: Codable, Sendable { let name: String; let searchUrl: String }
    let store: Store
    let aisleOrder: [String]
    var items: [ShoppingItem]
}

struct AddedCounts: Decodable, Sendable { let added: Int; let merged: Int }

// MARK: Meal plan

enum MealType: String, CaseIterable, Codable, Sendable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct PlanEntry: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let date: String          // yyyy-MM-dd
    let mealType: MealType
    let recipe: RecipeBrief
}

struct PlanWeek: Decodable, Sendable {
    let from: String
    let to: String
    var entries: [PlanEntry]
    let shareUrl: String?
}

// MARK: Collections

struct CollectionSummary: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    var name: String
    var description: String
    var slug: String?
    var coverUrl: String
    var category: Category?
    var shareUrl: String?
    var recipeCount: Int
}

struct CollectionDetail: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    var name: String
    var description: String
    var slug: String?
    var coverUrl: String
    var category: Category?
    var shareUrl: String?
    var recipeCount: Int
    var recipes: [RecipeSummary]
    var manualRecipeIds: [Int]
}

// MARK: Import

struct ImportDraft: Codable, Sendable, Hashable {
    var title = ""
    var description = ""
    var ingredients = ""
    var instructions = ""
    var notes = ""
    var servings = ""
    var prepTime = ""
    var cookTime = ""
}

struct ImportPreview: Decodable, Sendable {
    let kind: String
    let draft: ImportDraft
    let sourceUrl: String
    let imageName: String
    let imageUrl: String
    let rawText: String
    let warning: String
    /// Nutrition the source page printed (newer servers); handed back to /import/save untouched.
    var sourceNutrition: SourceNutrition?
}

/// Nutrition a recipe page states about itself (import previews). Lenient: any field that doesn't read is nil.
struct SourceNutrition: Codable, Sendable, Hashable {
    var kcal: Double?
    var protein: Double?
    var fat: Double?
    var carbs: Double?
    var servingSize: String?

    private enum CodingKeys: String, CodingKey { case kcal, protein, fat, carbs, servingSize }

    init(kcal: Double? = nil, protein: Double? = nil, fat: Double? = nil, carbs: Double? = nil, servingSize: String? = nil) {
        self.kcal = kcal; self.protein = protein; self.fat = fat; self.carbs = carbs; self.servingSize = servingSize
    }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        kcal = c.lenient(Double.self, .kcal); protein = c.lenient(Double.self, .protein)
        fat = c.lenient(Double.self, .fat); carbs = c.lenient(Double.self, .carbs)
        servingSize = c.lenient(String.self, .servingSize) ?? c.lenient(Double.self, .servingSize).map { String(format: "%g", $0) }
    }

    /// Every key, nulls included, as the contract shows it.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kcal, forKey: .kcal); try c.encode(protein, forKey: .protein)
        try c.encode(fat, forKey: .fat); try c.encode(carbs, forKey: .carbs)
        try c.encode(servingSize, forKey: .servingSize)
    }
}

struct DeviceToken: Decodable, Sendable, Identifiable {
    let id: Int
    let name: String
    let createdAt: Date?
    let lastUsedAt: Date?
    let current: Bool
}

// MARK: Admin

struct AdminSettings: Codable, Sendable, Hashable {
    var siteName = ""
    var logoUrl = ""
    var publicShowAuthor = false
    var storeName = ""
    var storeSearchUrl = ""
}

struct NewUserResult: Decodable, Sendable {
    let user: User
    let emailed: Bool
    let tempPassword: String?
}

extension RecipeSummary {
    /// The card-sized view of a full recipe (used to build lists from the offline library).
    init(_ d: RecipeDetail) {
        self.init(id: d.id, title: d.title, description: d.description, prepTime: d.prepTime, cookTime: d.cookTime,
                  servings: d.servings, imageUrl: d.imageUrl, thumbUrl: d.thumbUrl, categories: d.categories,
                  isFavorite: d.isFavorite, avgRating: d.avgRating, ratingCount: d.ratingCount, author: d.author,
                  createdAt: d.createdAt, updatedAt: d.updatedAt)
    }
}
