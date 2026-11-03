import AppIntents
import Foundation
import WidgetKit

/// The Shopping list widget's tick. Compiled into the app and the widget extension; it only needs what both share:
/// the keychain credentials and the App Group snapshots.
///
/// The item is ticked in the saved snapshot at once (the widget redraws without it), then sent to the server.
/// With no connection the tick is kept in the App Group, and the app moves it into its Outbox the next time it opens
/// (the widget also retries on its next refresh).
struct TickShoppingItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Tick Shopping Item"
    static let description = IntentDescription("Ticks an item off your Spoonmate shopping list.")
    static let isDiscoverable = false

    @Parameter(title: "Item ID") var itemID: Int
    @Parameter(title: "Item name") var name: String

    init() {}
    init(itemID: Int, name: String) {
        self.itemID = itemID
        self.name = name
    }

    func perform() async throws -> some IntentResult {
        let store = SnapshotStore.shared
        store.markChecked(itemID)
        let tick = PendingTick(itemID: itemID, name: name, checked: true)
        switch await ShoppingTicks.send(tick) {
        case .sent, .rejected: break
        case .offline: store.addPendingTick(tick)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.shopping)
        return .result()
    }
}

/// Sends widget ticks with the shared credentials.
enum ShoppingTicks {
    enum Outcome: Equatable { case sent, offline, rejected }

    static func send(_ tick: PendingTick) async -> Outcome {
        // Items added offline in the app have a temporary negative id; only the app can resolve those.
        guard tick.itemID > 0 else { return .offline }
        guard let saved = CredentialStore.read(), let base = URL(string: saved.server) else { return .rejected }
        struct Body: Encodable, Sendable { let checked: Bool }
        let client = APIClient(baseURL: base, token: saved.token)
        do {
            try await client.send("PATCH", "/shopping/items/\(tick.itemID)", body: Body(checked: tick.checked))
            return .sent
        } catch let error as APIError {
            if case .network = error { return .offline }
            return .rejected   // signed out, or the item was deleted elsewhere: nothing to retry
        } catch {
            return .offline
        }
    }

    /// Retries ticks still waiting (the widget calls this when a refresh shows the server is reachable).
    static func flush() async {
        let store = SnapshotStore.shared
        var done = Set<Int>()
        for tick in store.pendingTicks where tick.itemID > 0 {
            if await send(tick) != .offline { done.insert(tick.itemID) }
        }
        if !done.isEmpty { store.removePendingTicks(done) }
    }
}
