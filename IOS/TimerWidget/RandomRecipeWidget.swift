import AppIntents
import SwiftUI
import WidgetKit

/// "Random recipe": a recipe from the library, or from one collection, with its picture. A new one every three hours;
/// tapping opens it. The widget can't page through the library itself, so it picks from the pool the app writes to
/// the App Group after each sync (`RecipePoolSnapshot`, with small thumbnails). Small and medium.
struct RandomRecipeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.randomRecipe, intent: RandomRecipeIntent.self, provider: RandomRecipeProvider()) { entry in
            RandomRecipeView(entry: entry)
        }
        .configurationDisplayName("Random Recipe")
        .description("Something from your recipes to cook, changing through the day.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: Configuration

/// A collection to pick from, or "All recipes" (id 0). Read from the App Group pool, since the widget can't call the API.
struct RecipeCollectionEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Collection")
    static let defaultQuery = RecipeCollectionQuery()
    static let all = RecipeCollectionEntity(id: 0, name: "All recipes")

    let id: Int
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct RecipeCollectionQuery: EntityQuery {
    private var choices: [RecipeCollectionEntity] {
        [RecipeCollectionEntity.all] + (SnapshotStore.shared.recipePool?.collections ?? []).map { RecipeCollectionEntity(id: $0.id, name: $0.name) }
    }

    func entities(for identifiers: [Int]) async throws -> [RecipeCollectionEntity] {
        choices.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [RecipeCollectionEntity] { choices }

    func defaultResult() async -> RecipeCollectionEntity? { .all }
}

struct RandomRecipeIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Random Recipe"
    static let description = IntentDescription("Choose which recipes the widget picks from.")

    @Parameter(title: "Recipes from")
    var collection: RecipeCollectionEntity?

    init() {}
    init(collection: RecipeCollectionEntity?) { self.collection = collection }
}

// MARK: Timeline

struct RandomRecipeEntry: TimelineEntry, Sendable {
    enum Content: Sendable {
        case signedOut
        /// Nothing synced yet, or an empty collection.
        case empty(collection: String?)
        case recipe(PoolRecipe, picture: Data?)
    }
    let date: Date
    let content: Content
    /// The collection's name, shown above the title ("Weeknights"); nil for all recipes.
    var collection: String? = nil
}

struct RandomRecipeProvider: AppIntentTimelineProvider {
    /// A new recipe every three hours, five at a time (15 hours, then the widget asks again).
    static let interval: TimeInterval = 3 * 3600
    static let entryCount = 5

    func placeholder(in context: Context) -> RandomRecipeEntry {
        RandomRecipeEntry(date: .now, content: .recipe(PoolRecipe(id: 3, title: "Lemon and herb roast chicken", image: nil), picture: nil))
    }

    func snapshot(for configuration: RandomRecipeIntent, in context: Context) async -> RandomRecipeEntry {
        let entries = Self.entries(for: configuration, from: .now, count: 1)
        if context.isPreview, case .empty = entries.first?.content { return placeholder(in: context) }
        return entries.first ?? placeholder(in: context)
    }

    func timeline(for configuration: RandomRecipeIntent, in context: Context) async -> Timeline<RandomRecipeEntry> {
        Timeline(entries: Self.entries(for: configuration, from: .now, count: Self.entryCount), policy: .atEnd)
    }

    static func entries(for configuration: RandomRecipeIntent, from now: Date, count: Int) -> [RandomRecipeEntry] {
        guard WidgetLoader.isSignedIn else { return [RandomRecipeEntry(date: now, content: .signedOut)] }
        let store = SnapshotStore.shared
        let pool = store.recipePool
        let chosen = configuration.collection.flatMap { $0.id == 0 ? nil : $0 }
        let name = chosen.flatMap { c in pool?.collections.first { $0.id == c.id }?.name ?? c.name }
        var rng = SystemRandomNumberGenerator()
        let picks = RecipePoolSnapshot.picks(from: pool?.recipes(in: chosen?.id) ?? [], count: count, using: &rng)
        guard !picks.isEmpty else { return [RandomRecipeEntry(date: now, content: .empty(collection: name), collection: name)] }
        return picks.enumerated().map { i, recipe in
            let picture = recipe.image.flatMap(store.thumbnail(named:)).flatMap { try? Data(contentsOf: $0) }
            return RandomRecipeEntry(date: now.addingTimeInterval(Double(i) * interval), content: .recipe(recipe, picture: picture), collection: name)
        }
    }
}

// MARK: Views

struct RandomRecipeView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RandomRecipeEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { WidgetColors.background }
            .widgetURL(link)
    }

    private var link: URL? {
        switch entry.content {
        case .signedOut, .empty: nil   // just opens the app
        case .recipe(let recipe, _): DeepLink.recipe(recipe.id).url
        }
    }

    @ViewBuilder private var content: some View {
        switch entry.content {
        case .signedOut: SignInPrompt().padding()
        case .empty(let collection): empty(collection)
        case .recipe(let recipe, let picture):
            if family == .systemMedium { medium(recipe, picture) } else { small(recipe, picture) }
        }
    }

    private var eyebrow: some View {
        Text((entry.collection ?? "Why not cook").uppercased())
            .font(WidgetFonts.eyebrow).tracking(0.8).lineLimit(1)
            .foregroundStyle(WidgetColors.accent).widgetAccentable()
    }

    /// The picture fills the widget; the title sits on a band of the background colour below it.
    private func small(_ recipe: PoolRecipe, _ picture: Data?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RecipePicture(recipe: recipe, image: picture)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 2) {
                eyebrow
                Text(recipe.title).font(WidgetFonts.title(15)).foregroundStyle(WidgetColors.ink).lineLimit(2).minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(recipe))
    }

    private func medium(_ recipe: PoolRecipe, _ picture: Data?) -> some View {
        HStack(spacing: 0) {
            RecipePicture(recipe: recipe, image: picture)
                .aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: 4) {
                eyebrow
                Text(recipe.title).font(WidgetFonts.title(20, relativeTo: .title3)).foregroundStyle(WidgetColors.ink)
                    .lineLimit(3).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Label("Open recipe", systemImage: "book.closed").font(.caption).foregroundStyle(WidgetColors.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(recipe))
    }

    private func empty(_ collection: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "shuffle").font(.title3).foregroundStyle(WidgetColors.accent).widgetAccentable()
                .accessibilityHidden(true)
            Text(collection.map { "Nothing in \($0) yet" } ?? "No recipes yet").font(WidgetFonts.title(16)).foregroundStyle(WidgetColors.ink)
                .lineLimit(2)
            Text(collection == nil ? "Open Spoonmate to sync your recipes." : "Add recipes to it, or pick another collection.")
                .font(.caption).foregroundStyle(WidgetColors.secondary)
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func label(_ recipe: PoolRecipe) -> String {
        (entry.collection.map { "From \($0): " } ?? "Why not cook: ") + recipe.title
    }
}

/// A pool recipe's thumbnail, or its letter tile. Turns monochrome-accented in the tinted Home Screen modes.
struct RecipePicture: View {
    let recipe: PoolRecipe
    let image: Data?

    var body: some View {
        Color.clear
            .overlay {
                if let image, let picture = UIImage(data: image) {
                    Image(uiImage: picture).resizable().widgetAccentedRenderingMode(.accentedDesaturated).scaledToFill()
                } else {
                    LetterTile(title: recipe.title, id: recipe.id)
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

#Preview("Small", as: .systemSmall) {
    RandomRecipeWidget()
} timeline: {
    RandomRecipeEntry(date: .now, content: .recipe(PoolRecipe(id: 3, title: "Lemon and herb roast chicken", image: nil), picture: nil))
    RandomRecipeEntry(date: .now, content: .recipe(PoolRecipe(id: 6, title: "Spinach and ricotta lasagne", image: nil), picture: nil),
                      collection: "Weeknights")
    RandomRecipeEntry(date: .now, content: .empty(collection: nil))
    RandomRecipeEntry(date: .now, content: .signedOut)
}

#Preview("Medium", as: .systemMedium) {
    RandomRecipeWidget()
} timeline: {
    RandomRecipeEntry(date: .now, content: .recipe(PoolRecipe(id: 4, title: "Chickpea curry with flatbreads", image: nil), picture: nil))
    RandomRecipeEntry(date: .now, content: .empty(collection: "Baking"), collection: "Baking")
}
