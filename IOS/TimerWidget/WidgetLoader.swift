import Foundation
import UIKit

/// Fetches fresh data for the widgets with the app's shared credentials, falling back to the App Group snapshots the
/// app wrote. Requests are cut short so a slow server can't stall the widget refresh.
enum WidgetLoader {
    static var isSignedIn: Bool { CredentialStore.read() != nil }

    private static func client() -> APIClient? {
        guard let saved = CredentialStore.read(), let base = URL(string: saved.server) else { return nil }
        return APIClient(baseURL: base, token: saved.token)
    }

    /// Today's plan (and the next week), refreshed from the server when it answers in time.
    static func plan(now: Date = .now) async -> PlanSnapshot? {
        let store = SnapshotStore.shared
        if let client = client() {
            let from = PlanDay.key(now), to = PlanDay.key(daysFrom: now, 6)
            if let week: PlanWeek = await deadline(8, { try await client.get("/mealplan", query: ["from": from, "to": to]) }) {
                let merged = (store.plan ?? PlanSnapshot(meals: []))
                    .merging(week.entries.map { WidgetMeal($0, base: client.baseURL) }, from: from, to: to, today: from, keepUntil: to)
                store.write(plan: merged)
                return merged
            }
        }
        return store.plan
    }

    /// The shopping list with the ticks still waiting applied. A successful refresh also sends those ticks.
    static func shopping() async -> ShoppingSnapshot? {
        let store = SnapshotStore.shared
        if let client = client(), let list: ShoppingList = await deadline(8, { try await client.get("/shopping") }) {
            await ShoppingTicks.flush()
            let snapshot = ShoppingSnapshot(list).applying(store.pendingTicks)
            store.write(shopping: snapshot)
            return snapshot
        }
        return store.shopping?.applying(store.pendingTicks)
    }

    /// A small copy of the meal's picture: the App Group copy (the app puts its downloaded ones there), else downloaded.
    static func picture(for meal: WidgetMeal, side: CGFloat = 320) async -> Data? {
        guard let link = meal.imageURL.flatMap(URL.init(string:)) else { return nil }
        let file = SnapshotStore.shared.imageFile(for: link)
        var data = file.flatMap { try? Data(contentsOf: $0) }
        if data == nil, let fetched = await deadline(6, { try await URLSession.shared.data(from: link).0 }), UIImage(data: fetched) != nil {
            data = fetched
            if let file {
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fetched.write(to: file, options: .atomic)
            }
        }
        // Widgets have a tight memory limit: hand the view a small JPEG, not the full picture.
        guard let data, let image = UIImage(data: data) else { return nil }
        let scale = min(1, side / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return image.preparingThumbnail(of: size)?.jpegData(compressionQuality: 0.8)
    }

    /// The result of `operation`, or nil if it fails or takes longer than `seconds`.
    static func deadline<T: Sendable>(_ seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { try? await operation() }
            group.addTask { try? await Task.sleep(for: .seconds(seconds)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
