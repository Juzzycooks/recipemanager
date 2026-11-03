import AppIntents
import CoreSpotlight
import Foundation

/// A recipe as Siri, Shortcuts and Spotlight see it: one entity type for all three (IndexedEntity), kept light.
struct RecipeEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Recipe", numericFormat: "\(placeholder: .int) recipes")
    static let defaultQuery = RecipeQuery()

    let id: Int
    let title: String
    /// "Cook 30 min · Serves 4".
    let subtitle: String
    /// The picture on this phone (`ImageStore`), nil when it hasn't been downloaded.
    let thumbnail: URL?
    /// Ingredient words and tags (categories), so Spotlight finds "chickpeas" or "dessert".
    var keywords: [String] = []
    /// The description and ingredient lines, searchable text for Spotlight.
    var searchText: String = ""

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)",
                              subtitle: subtitle.isEmpty ? nil : "\(subtitle)",
                              image: thumbnail.map { DisplayRepresentation.Image(url: $0) })
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let set = defaultAttributeSet
        set.title = title
        set.displayName = title
        set.contentDescription = subtitle
        set.keywords = keywords
        set.textContent = searchText
        if let thumbnail, let data = try? Data(contentsOf: thumbnail) { set.thumbnailData = data }
        return set
    }
}

extension RecipeEntity {
    init(_ recipe: RecipeDetail, base: URL?) {
        self.init(id: recipe.id, title: recipe.title,
                  subtitle: Self.subtitle(prep: recipe.prepTime, cook: recipe.cookTime, serves: recipe.servings),
                  thumbnail: Self.localPicture(thumb: recipe.thumbUrl, image: recipe.imageUrl, base: base),
                  keywords: Self.keywords(ingredients: recipe.ingredientSections.flatMap(\.lines), tags: recipe.categories.map(\.name)),
                  searchText: ([recipe.description] + recipe.ingredientSections.flatMap(\.lines)).filter { !$0.isEmpty }.joined(separator: "\n"))
    }

    init(_ recipe: RecipeSummary, base: URL?) {
        self.init(id: recipe.id, title: recipe.title,
                  subtitle: Self.subtitle(prep: recipe.prepTime, cook: recipe.cookTime, serves: recipe.servings),
                  thumbnail: Self.localPicture(thumb: recipe.thumbUrl, image: recipe.imageUrl, base: base),
                  keywords: recipe.categories.map { $0.name.lowercased() })
    }

    static func subtitle(prep: String, cook: String, serves: String) -> String {
        let time = !cook.isEmpty ? "Cook \(cook)" : !prep.isEmpty ? "Prep \(prep)" : nil
        return [time, serves.isEmpty ? nil : "Serves \(serves)"].compactMap { $0 }.joined(separator: " · ")
    }

    private static func localPicture(thumb: String, image: String, base: URL?) -> URL? {
        for path in [thumb, image] {
            if let url = WidgetMeal.resolve(path, base: base), let file = ImageStore.shared.storedFile(for: url) { return file }
        }
        return nil
    }

    /// Words worth searching for: the tags, then the ingredient names with amounts, units and filler words left out
    /// ("400 g tin chickpeas, drained" gives "chickpeas"). Lowercased, no repeats, at most 80.
    static func keywords(ingredients: [String], tags: [String]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        func add(_ word: String) {
            let w = word.lowercased()
            guard w.count >= 3, !ignored.contains(w), seen.insert(w).inserted else { return }
            out.append(w)
        }
        for tag in tags { add(tag.trimmingCharacters(in: .whitespaces)) }
        for line in ingredients {
            for word in line.split(whereSeparator: { !$0.isLetter && $0 != "-" && $0 != "'" }) {
                add(String(word).trimmingCharacters(in: CharacterSet(charactersIn: "-'")))
            }
        }
        return Array(out.prefix(80))
    }

    /// Units, sizes and kitchen verbs that would match every recipe.
    private static let ignored: Set<String> = [
        "cup", "cups", "tsp", "tbsp", "teaspoon", "teaspoons", "tablespoon", "tablespoons", "gram", "grams", "kg", "ml",
        "litre", "litres", "liter", "liters", "oz", "ounce", "ounces", "lb", "lbs", "pound", "pounds", "pinch", "dash",
        "and", "or", "the", "for", "of", "to", "with", "into", "plus", "about", "large", "small", "medium", "finely",
        "roughly", "chopped", "diced", "sliced", "minced", "grated", "fresh", "freshly", "ground", "drained", "rinsed",
        "peeled", "optional", "taste", "extra", "serve", "serving", "tin", "can", "cans", "tins", "packet", "pkt",
        "handful", "piece", "pieces", "whole", "cut", "halved", "quartered", "thinly", "thickly", "beaten", "softened",
        "melted", "room", "temperature", "some", "few", "more", "less", "each",
    ]
}

/// Finds recipes for Siri and Shortcuts: the offline library first (instant, works with no signal), the server when
/// the library doesn't have it and we're online.
struct RecipeQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [Int]) async throws -> [RecipeEntity] {
        let base = AppServices.session.baseURL
        let library = Dictionary(uniqueKeysWithValues: await OfflineStore.shared.allRecipes().map { ($0.id, $0) })
        var found: [RecipeEntity] = []
        for id in identifiers {
            if let recipe = library[id] {
                found.append(RecipeEntity(recipe, base: base))
            } else if AppServices.hasAccount,
                      let recipe: RecipeDetail = try? await AppServices.session.run({ try await $0.get("/recipes/\(id)") }) {
                found.append(RecipeEntity(recipe, base: base))
            }
        }
        return found
    }

    @MainActor
    func entities(matching string: String) async throws -> [RecipeEntity] {
        let base = AppServices.session.baseURL
        let library = await OfflineStore.shared.allRecipes()
        let local = Self.match(string, in: library).prefix(30).map { RecipeEntity($0, base: base) }
        if !local.isEmpty || library.count > 0 && Connectivity.shared.isOffline { return Array(local) }
        guard AppServices.hasAccount else { return [] }
        let page: Page<RecipeSummary>? = try? await AppServices.session.run { try await $0.get("/recipes", query: ["q": string, "per_page": "30"]) }
        return page?.items.map { RecipeEntity($0, base: base) } ?? []
    }

    @MainActor
    func suggestedEntities() async throws -> [RecipeEntity] {
        let base = AppServices.session.baseURL
        // Favourites first, then what you cook most, then the newest: the recipes worth a Siri phrase.
        let recipes = await OfflineStore.shared.allRecipes().sorted {
            ($0.isFavorite ? 1 : 0, $0.madeCount, $0.createdAt ?? .distantPast) > ($1.isFavorite ? 1 : 0, $1.madeCount, $1.createdAt ?? .distantPast)
        }
        return recipes.prefix(30).map { RecipeEntity($0, base: base) }
    }

    /// Title matches first (whole title, then title start, then anywhere), then ingredient matches.
    nonisolated static func match(_ text: String, in recipes: [RecipeDetail]) -> [RecipeDetail] {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        func rank(_ r: RecipeDetail) -> Int? {
            if r.title.compare(q, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame { return 0 }
            if r.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil { return 1 }
            if r.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil { return 2 }
            if r.ingredients.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil { return 3 }
            return nil
        }
        return recipes.compactMap { r in rank(r).map { (r, $0) } }
            .sorted { ($0.1, $0.0.title.lowercased()) < ($1.1, $1.0.title.lowercased()) }
            .map(\.0)
    }
}
