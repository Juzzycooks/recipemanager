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

    init() {}
    init(_ r: RecipeDetail) {
        title = r.title; description = r.description; ingredients = r.ingredients; instructions = r.instructions
        prepTime = r.prepTime; cookTime = r.cookTime; servings = r.servings; sourceUrl = r.sourceUrl
        notes = r.notes; categoryIds = r.categories.map(\.id)
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

struct ShoppingList: Decodable, Sendable {
    struct Store: Decodable, Sendable { let name: String; let searchUrl: String }
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
}

struct DeviceToken: Decodable, Sendable, Identifiable {
    let id: Int
    let name: String
    let createdAt: Date?
    let lastUsedAt: Date?
    let current: Bool
}
