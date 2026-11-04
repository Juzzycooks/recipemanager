import Foundation
import ImageIO
import UniformTypeIdentifiers
import WidgetKit

/// The app's side of the widgets: writes the App Group snapshots whenever the plan or shopping list is saved, reloads
/// the widget that changed, and takes ticks made on the widget while offline into the Outbox.
///
/// Every `GET /shopping` and `GET /mealplan` response (and every local edit, which the screens save the same way) passes
/// through `OfflineStore.store`, which calls `saved(_:for:)`, so there is one hook and no screen has to remember it.
enum WidgetBridge {
    /// How far ahead the plan snapshot looks (the widget only shows today, but tomorrow is ready at midnight).
    static let planDays = 7

    static func saved(_ data: Data, for url: URL) {
        let path = url.path
        if path.hasSuffix("/api/v1/shopping") {
            guard let list = try? APIClient.decoder.decode(ShoppingList.self, from: HTMLEntities.clean(data)) else { return }
            publish(shopping: list)
        } else if path.hasSuffix("/api/v1/mealplan") {
            guard let week = try? APIClient.decoder.decode(PlanWeek.self, from: HTMLEntities.clean(data)) else { return }
            publish(plan: week.entries, from: week.from, to: week.to, base: url)
        }
    }

    static func publish(shopping list: ShoppingList, store: SnapshotStore = .shared) {
        // Ticks still waiting in the App Group stay ticked, so the widget doesn't bring them back.
        let snapshot = ShoppingSnapshot(list).applying(store.pendingTicks)
        if store.write(shopping: snapshot) { WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.shopping) }
    }

    static func publish(plan entries: [PlanEntry], from: String, to: String, base: URL?, now: Date = .now,
                        store: SnapshotStore = .shared) {
        let today = PlanDay.key(now)
        let meals = entries.map { WidgetMeal($0, base: base) }
        let merged = (store.plan ?? PlanSnapshot(meals: []))
            .merging(meals, from: from, to: to, today: today, keepUntil: PlanDay.key(daysFrom: now, planDays))
        copyPictures(for: merged.meals.filter { $0.date <= PlanDay.key(daysFrom: now, 1) }, store: store)
        if store.write(plan: merged) {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.tonight)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.week)
        }
    }

    // MARK: Random recipe

    /// Longest side of the Random Recipe widget's thumbnails, in pixels.
    static let thumbnailSide = 300

    /// Writes the Random Recipe widget's pool from the offline library (after each sync): up to 100 recipes, and up to
    /// 60 per collection, each with a small JPEG made from the picture the app already downloaded. Recipes already in
    /// the pool stay in it while they exist, so thumbnails aren't remade every time, and unused thumbnails are deleted.
    /// Runs off the main actor (it decodes pictures).
    nonisolated static func publishRecipePool(library: [RecipeDetail], base: URL?, store: SnapshotStore = .shared) async {
        guard let folder = store.thumbnailsDirectory else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let previous = store.recipePool
        var rng = SystemRandomNumberGenerator()
        let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = byID.keys.sorted()

        var made: [Int: PoolRecipe] = [:]
        func entry(_ id: Int) -> PoolRecipe? {
            if let done = made[id] { return done }
            guard let recipe = byID[id] else { return nil }
            let pool = PoolRecipe(id: id, title: recipe.title, image: thumbnail(for: recipe, base: base, folder: folder))
            made[id] = pool
            return pool
        }

        let all = RecipePoolSnapshot.select(ids, previous: previous?.all.map(\.id) ?? [], cap: RecipePoolSnapshot.allCap, using: &rng)
            .compactMap(entry)
        var members: [Int: (name: String, ids: [Int])] = [:]
        for recipe in library {
            for collection in recipe.collections { members[collection.id, default: (name: collection.name, ids: [])].ids.append(recipe.id) }
        }
        let collections = members.sorted { $0.value.name.localizedCaseInsensitiveCompare($1.value.name) == .orderedAscending }
            .map { id, member in
                let before = previous?.collections.first { $0.id == id }?.recipes.map(\.id) ?? []
                let picked = RecipePoolSnapshot.select(member.ids.sorted(), previous: before, cap: RecipePoolSnapshot.collectionCap, using: &rng)
                return PoolCollection(id: id, name: member.name, recipes: picked.compactMap(entry))
            }

        let snapshot = RecipePoolSnapshot(all: all, collections: collections)
        let changed = store.write(recipePool: snapshot)
        // Prune thumbnails nothing refers to any more (recipes dropped from the pool, pictures that changed).
        let keep = snapshot.imageNames
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where !keep.contains(name) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
        if changed { WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.randomRecipe) }
    }

    /// The recipe's thumbnail file name, made now from the downloaded picture if it isn't there yet. Named after the
    /// recipe and its picture's address, so a new picture gets a new file. Nil when the app has no copy of the picture.
    private nonisolated static func thumbnail(for recipe: RecipeDetail, base: URL?, folder: URL) -> String? {
        let path = recipe.thumbUrl.isEmpty ? recipe.imageUrl : recipe.thumbUrl
        guard let link = WidgetMeal.resolve(path, base: base) else { return nil }
        let name = "\(recipe.id)-\(SnapshotStore.digest(link.absoluteString).prefix(16)).jpg"
        let target = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: target.path) { return name }
        guard let source = ImageStore.shared.storedFile(for: link), let jpeg = smallJPEG(from: source) else { return nil }
        do {
            try jpeg.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return name
        } catch { return nil }
    }

    /// A JPEG no bigger than `thumbnailSide` on its longest side, decoded at that size (never the full picture).
    nonisolated static func smallJPEG(from file: URL, side: Int = thumbnailSide) -> Data? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// Copies pictures the app already has into the App Group, so the widget shows them offline without downloading.
    private static func copyPictures(for meals: [WidgetMeal], store: SnapshotStore) {
        for meal in meals {
            guard let link = meal.imageURL.flatMap(URL.init(string:)), let target = store.imageFile(for: link),
                  !FileManager.default.fileExists(atPath: target.path),
                  let source = ImageStore.shared.storedFile(for: link) else { continue }
            try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: source, to: target)
        }
    }

    /// Signed out (or a different account): the widgets forget the old plan and list and say "Sign in".
    static func clear(store: SnapshotStore = .shared) {
        store.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Moves ticks made on the Shopping list widget while offline into the Outbox (sent with the rest when online), and
    /// marks them on the saved list so an offline launch shows them ticked.
    @MainActor static func drainPendingTicks(_ session: Session) async {
        await drainPendingTicks(client: session.client)
    }

    /// Takes the ticks only once there is a client to send them with: taking deletes them from the App Group, so with
    /// no client yet (still restoring, signed out) they stay put for the next catch-up instead of being lost.
    @MainActor static func drainPendingTicks(client: APIClient?, store: SnapshotStore = .shared) async {
        guard let client, !store.pendingTicks.isEmpty else { return }
        let ticks = store.takePendingTicks()
        guard !ticks.isEmpty else { return }
        for tick in ticks {
            if tick.itemID < 0 { Outbox.shared.setAddChecked(name: tick.name, checked: tick.checked) }
            else { Outbox.shared.enqueue(.setShoppingChecked(itemID: tick.itemID, checked: tick.checked)) }
        }
        guard let url = client.url("/shopping"), let data = await OfflineStore.shared.cached(for: url),
              var list: ShoppingList = try? client.decode(data) else { return }
        for tick in ticks {
            if let i = list.items.firstIndex(where: { $0.id == tick.itemID }) { list.items[i].checked = tick.checked }
        }
        if let updated = try? APIClient.encoder.encode(list) { await OfflineStore.shared.store(updated, for: url) }
    }
}
