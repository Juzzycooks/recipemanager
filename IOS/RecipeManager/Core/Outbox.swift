import Foundation
import Observation

/// A change made while offline, replayed to the server when the connection returns.
enum OutboxOp: Codable, Sendable, Equatable {
    case favorite(recipeID: Int, wanted: Bool)
    case rate(recipeID: Int, score: Int)
    case madeIt(recipeID: Int)
    case addShoppingItem(name: String, checked: Bool)
    case setShoppingChecked(itemID: Int, checked: Bool)
    case deleteShoppingItem(itemID: Int)
}

/// Persistent queue of offline changes. Later changes to the same thing replace earlier ones.
@MainActor @Observable
final class Outbox {
    static let shared = Outbox()

    private(set) var ops: [OutboxOp] = []
    private(set) var isReplaying = false
    var count: Int { ops.count }

    private let file: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        file = base.appendingPathComponent("outbox.json")
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([OutboxOp].self, from: data) { ops = saved }
    }

    func enqueue(_ op: OutboxOp) {
        switch op {
        case .favorite(let id, _): ops.removeAll { if case .favorite(let other, _) = $0 { other == id } else { false } }
        case .rate(let id, _): ops.removeAll { if case .rate(let other, _) = $0 { other == id } else { false } }
        case .setShoppingChecked(let id, _): ops.removeAll { if case .setShoppingChecked(let other, _) = $0 { other == id } else { false } }
        case .deleteShoppingItem(let id):
            ops.removeAll { if case .setShoppingChecked(let other, _) = $0 { other == id } else { false } }
        default: break
        }
        ops.append(op)
        save()
    }

    /// Removes a not-yet-sent "add" (the person deleted that item again before we were online).
    func cancelAdd(name: String) {
        if let i = ops.lastIndex(where: { if case .addShoppingItem(let n, _) = $0 { n == name } else { false } }) { ops.remove(at: i); save() }
    }

    /// Updates the ticked state of a not-yet-sent "add".
    func setAddChecked(name: String, checked: Bool) {
        if let i = ops.lastIndex(where: { if case .addShoppingItem(let n, _) = $0 { n == name } else { false } }) {
            ops[i] = .addShoppingItem(name: name, checked: checked); save()
        }
    }

    func clear() { ops = []; save() }

    /// Sends queued changes in order. Stops at the first connectivity failure; drops changes the server rejects
    /// (for example a recipe that was deleted elsewhere).
    func replay(_ session: Session) async {
        guard !isReplaying, !ops.isEmpty else { return }
        isReplaying = true
        defer { isReplaying = false }
        while let op = ops.first {
            do {
                try await send(op, session)
                ops.removeFirst(); save()
            } catch let error as APIError where error.isOffline || error.isUnauthorized {
                return
            } catch {
                ops.removeFirst(); save()   // rejected: nothing sensible to retry
            }
        }
        session.recipesChanged()
    }

    private func send(_ op: OutboxOp, _ session: Session) async throws {
        struct Checked: Encodable, Sendable { let checked: Bool }
        struct Name: Encodable, Sendable { let name: String }
        struct Score: Encodable, Sendable { let score: Int }
        switch op {
        case .favorite(let id, let wanted):
            try await session.run { try await $0.send(wanted ? "PUT" : "DELETE", "/recipes/\(id)/favorite") }
        case .rate(let id, let score):
            try await session.run { try await $0.send("PUT", "/recipes/\(id)/rating", body: Score(score: score)) }
        case .madeIt(let id):
            try await session.run { try await $0.send("POST", "/recipes/\(id)/made") }
        case .setShoppingChecked(let id, let checked):
            try await session.run { try await $0.send("PATCH", "/shopping/items/\(id)", body: Checked(checked: checked)) }
        case .deleteShoppingItem(let id):
            try await session.run { try await $0.send("DELETE", "/shopping/items/\(id)") }
        case .addShoppingItem(let name, let checked):
            try await session.run { try await $0.send("POST", "/shopping/items", body: Name(name: name)) }
            if checked {
                // The add returns counts, not the item. The newest item with this name is the one we just made
                // (if the server merged it into an existing line there is nothing to tick).
                let list: ShoppingList = try await session.run { try await $0.get("/shopping") }
                if let item = list.items.filter({ $0.name == name && !$0.checked }).max(by: { $0.id < $1.id }) {
                    try await session.run { try await $0.send("PATCH", "/shopping/items/\(item.id)", body: Checked(checked: true)) }
                }
            }
        }
    }

    private func save() {
        try? JSONEncoder().encode(ops).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

extension APIError {
    var isUnauthorized: Bool { if case .unauthorized = self { true } else { false } }
}
