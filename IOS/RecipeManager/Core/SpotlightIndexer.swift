import AppIntents
import CoreSpotlight
import Foundation

/// Keeps Spotlight in step with the offline library: after each `OfflineSync`, recipes that are new or changed (or whose
/// picture has since been downloaded) are indexed as `RecipeEntity`s, recipes gone from the library are removed, and
/// `OfflineStore.clear()` (sign-out) removes them all. Tapping a result runs `OpenRecipeIntent` (the entity's open
/// intent); `recipeID(from:)` also handles the classic Spotlight continuation, in case iOS sends that instead.
enum SpotlightIndexer {
    private static let stampsKey = "spotlightIndexed"

    struct Diff: Equatable {
        var upsert: [Int]
        var delete: [Int]
    }

    /// What to index and remove, from each recipe's current stamp and the stamp it was last indexed with.
    static func diff(current: [Int: String], indexed: [Int: String]) -> Diff {
        Diff(upsert: current.filter { indexed[$0.key] != $0.value }.map(\.key).sorted(),
             delete: indexed.keys.filter { current[$0] == nil }.sorted())
    }

    /// Changes whenever anything Spotlight shows changes.
    static func stamp(_ recipe: RecipeDetail, hasPicture: Bool) -> String {
        "\(recipe.updatedAt?.timeIntervalSince1970 ?? 0)|\(recipe.title)|\(hasPicture ? 1 : 0)"
    }

    @MainActor
    static func update(library: [RecipeDetail], base: URL?) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let entities = Dictionary(uniqueKeysWithValues: library.map { ($0.id, RecipeEntity($0, base: base)) })
        let current = Dictionary(uniqueKeysWithValues: library.map { ($0.id, stamp($0, hasPicture: entities[$0.id]?.thumbnail != nil)) })
        let indexed = savedStamps
        let plan = diff(current: current, indexed: indexed)
        guard !plan.upsert.isEmpty || !plan.delete.isEmpty else { return }
        let index = CSSearchableIndex.default()
        var stamps = indexed
        do {
            if !plan.delete.isEmpty {
                try await index.deleteAppEntities(identifiedBy: plan.delete, ofType: RecipeEntity.self)
                for id in plan.delete { stamps[id] = nil }
            }
            for batch in stride(from: 0, to: plan.upsert.count, by: 100).map({ Array(plan.upsert[$0..<min($0 + 100, plan.upsert.count)]) }) {
                try await index.indexAppEntities(batch.compactMap { entities[$0] })
                for id in batch { stamps[id] = current[id] }
            }
        } catch {
            // Keep what did go in; the rest is retried after the next sync.
        }
        savedStamps = stamps
    }

    static func clear() async {
        UserDefaults.standard.removeObject(forKey: stampsKey)
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        try? await CSSearchableIndex.default().deleteAppEntities(ofType: RecipeEntity.self)
    }

    /// The recipe a Spotlight continuation points at: the last number in its identifier.
    static func recipeID(from activity: NSUserActivity) -> Int? {
        (activity.userInfo?[CSSearchableItemActivityIdentifier] as? String).flatMap(recipeID(fromIdentifier:))
    }

    static func recipeID(fromIdentifier identifier: String) -> Int? {
        guard let digits = identifier.split(whereSeparator: { !$0.isNumber }).last, let id = Int(digits), id > 0 else { return nil }
        return id
    }

    private static var savedStamps: [Int: String] {
        get {
            let raw = UserDefaults.standard.dictionary(forKey: stampsKey) as? [String: String] ?? [:]
            return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in Int(k).map { ($0, v) } })
        }
        set {
            UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: newValue.map { (String($0.key), $0.value) }), forKey: stampsKey)
        }
    }
}
