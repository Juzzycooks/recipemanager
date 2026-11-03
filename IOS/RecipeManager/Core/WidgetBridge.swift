import Foundation
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
        if store.write(plan: merged) { WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.tonight) }
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
