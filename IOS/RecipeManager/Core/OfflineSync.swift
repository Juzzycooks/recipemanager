import Foundation
import Observation

/// Keeps the offline copy current: the whole recipe library (only recipes that changed are re-downloaded),
/// collections, the shopping list, a few weeks of meal plan, and optionally the pictures.
@MainActor @Observable
final class OfflineSync {
    enum State: Equatable {
        case idle
        case syncing(String)
        case failed(String)
    }

    static let enabledKey = "offlineEnabled"
    static let imagesKey = "offlineImages"
    private static let lastSyncKey = "offlineLastSync"
    private static let minimumInterval: TimeInterval = 600   // the sync is incremental, so topping up often is cheap

    private(set) var state = State.idle
    private(set) var lastSync: Date? = UserDefaults.standard.object(forKey: OfflineSync.lastSyncKey) as? Date
    private(set) var recipeCount = 0

    var isSyncing: Bool { if case .syncing = state { true } else { false } }
    private var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
    private var includeImages: Bool { UserDefaults.standard.object(forKey: Self.imagesKey) as? Bool ?? true }

    /// Foreground / reconnect hook: sync if it's been a while.
    func syncIfNeeded(_ session: Session) async {
        guard enabled, session.isSignedIn, !Connectivity.shared.isOffline, !isSyncing else { return }
        let storeIsEmpty = await OfflineStore.shared.recipeCount == 0
        if !storeIsEmpty, let lastSync, Date.now.timeIntervalSince(lastSync) < Self.minimumInterval { return }
        await sync(session)
    }

    func sync(_ session: Session) async {
        guard let client = session.client, !isSyncing else { return }
        do {
            // 1. Which recipes exist, and which changed since we last looked?
            var summaries: [RecipeSummary] = []
            var page = 1, pages = 1
            repeat {
                let result: Page<RecipeSummary> = try await client.get("/recipes", query: ["page": String(page), "per_page": "100", "sort": "oldest"])
                summaries += result.items; pages = result.pages; page += 1
            } while page <= pages

            let known = Dictionary(uniqueKeysWithValues: await OfflineStore.shared.allRecipes().map { ($0.id, $0) })
            let stale = summaries.filter { s in
                guard let old = known[s.id] else { return true }
                return old.updatedAt != s.updatedAt || old.isFavorite != s.isFavorite || old.ratingCount != s.ratingCount
            }
            await OfflineStore.shared.remove(ids: known.keys.filter { id in !summaries.contains { $0.id == id } })

            // 2. Download those in full, a few at a time (each GET also updates the local library).
            var done = 0
            if !stale.isEmpty { state = .syncing("Downloading recipes (0 of \(stale.count))…") }
            try await withThrowingTaskGroup(of: Void.self) { group in
                var iterator = stale.makeIterator()
                func next() -> Int? { iterator.next()?.id }
                for _ in 0..<4 { if let id = next() { group.addTask { let _: RecipeDetail = try await client.get("/recipes/\(id)") } } }
                while try await group.next() != nil {
                    done += 1
                    state = .syncing("Downloading recipes (\(done) of \(stale.count))…")
                    if let id = next() { group.addTask { let _: RecipeDetail = try await client.get("/recipes/\(id)") } }
                }
            }

            // 3. The rest of what the screens show.
            let _: ItemList<Category> = try await client.get("/categories")
            let _: User = try await client.get("/me")
            let collections: ItemList<CollectionSummary> = try await client.get("/collections")
            for collection in collections.items { let _: CollectionDetail = try await client.get("/collections/\(collection.id)") }
            let _: ShoppingList = try await client.get("/shopping")
            let calendar = MealPlanModel.calendar
            let thisMonday = MealPlanModel.monday(of: .now)
            for offset in -1...3 {
                guard let monday = calendar.date(byAdding: .weekOfYear, value: offset, to: thisMonday),
                      let sunday = calendar.date(byAdding: .day, value: 6, to: monday) else { continue }
                let _: PlanWeek = try await client.get("/mealplan", query: ["from": monday.apiDay, "to": sunday.apiDay])
            }

            // 4. Pictures (thumbnails for cards, full size for the recipe page).
            if includeImages {
                let recipes = await OfflineStore.shared.allRecipes()
                let urls = recipes.flatMap { [$0.thumbUrl, $0.imageUrl] }.compactMap { client.resolve($0) }
                await prefetch(Array(Set(urls)))
            }

            recipeCount = await OfflineStore.shared.recipeCount
            lastSync = .now
            UserDefaults.standard.set(lastSync, forKey: Self.lastSyncKey)
            state = .idle
        } catch let error as APIError where error.isOffline {
            state = .idle   // lost the connection part-way; try again when it's back
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func refreshCount() async { recipeCount = await OfflineStore.shared.recipeCount }

    /// Erases the offline copy (and forgets when we last synced).
    func clear() async {
        await OfflineStore.shared.clear()
        URLCache.shared.removeAllCachedResponses()
        UserDefaults.standard.removeObject(forKey: Self.lastSyncKey)
        lastSync = nil; recipeCount = 0; state = .idle
    }

    private func prefetch(_ urls: [URL]) async {
        var todo: [URL] = []
        for url in urls where !(await ImageStore.shared.has(url)) { todo.append(url) }
        guard !todo.isEmpty else { return }
        state = .syncing("Downloading pictures (0 of \(todo.count))…")
        var done = 0
        await withTaskGroup(of: Void.self) { group in
            var iterator = todo.makeIterator()
            for _ in 0..<4 { if let url = iterator.next() { group.addTask { await ImageStore.shared.prefetch(url) } } }
            while await group.next() != nil {
                done += 1
                if done % 5 == 0 { state = .syncing("Downloading pictures (\(done) of \(todo.count))…") }
                if let url = iterator.next() { group.addTask { await ImageStore.shared.prefetch(url) } }
            }
        }
    }
}
