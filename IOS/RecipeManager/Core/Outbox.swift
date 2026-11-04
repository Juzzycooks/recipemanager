import Foundation
import Observation

/// A change made while offline (favourites, ratings, made-it, shopping and the meal plan), replayed to the server when the connection returns.
enum OutboxOp: Codable, Sendable, Equatable {
    case favorite(recipeID: Int, wanted: Bool)
    case rate(recipeID: Int, score: Int)
    /// "I made this", with the cook's note and photo when there are any. `photo` is the name of a JPEG kept in
    /// `Outbox.photoDirectory` until it's sent (older queues have neither field and still decode).
    case madeIt(recipeID: Int, note: String? = nil, photo: String? = nil)
    case addShoppingItem(name: String, checked: Bool)
    case setShoppingChecked(itemID: Int, checked: Bool)
    case deleteShoppingItem(itemID: Int)
    /// `localID` is the temporary negative id the entry has on this phone until it's sent.
    case addPlanEntry(localID: Int, recipeID: Int, date: String, mealType: String)
    case movePlanEntry(entryID: Int, date: String, mealType: String)
    case deletePlanEntry(entryID: Int)
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
        case .movePlanEntry(let id, _, _): ops.removeAll { if case .movePlanEntry(let other, _, _) = $0 { other == id } else { false } }
        case .deletePlanEntry(let id): ops.removeAll { if case .movePlanEntry(let other, _, _) = $0 { other == id } else { false } }
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

    /// Removes a not-yet-sent meal-plan add (the entry was removed again before we were online).
    func cancelPlanAdd(localID: Int) {
        ops.removeAll { if case .addPlanEntry(let id, _, _, _) = $0 { id == localID } else { false } }
        save()
    }

    /// Moves a not-yet-sent meal-plan add to another day or meal.
    func movePlanAdd(localID: Int, date: String, mealType: String) {
        guard let i = ops.firstIndex(where: { if case .addPlanEntry(let id, _, _, _) = $0 { id == localID } else { false } }),
              case .addPlanEntry(_, let recipeID, _, _) = ops[i] else { return }
        ops[i] = .addPlanEntry(localID: localID, recipeID: recipeID, date: date, mealType: mealType); save()
    }

    /// Takes back a not-yet-sent meal-plan removal (undo while offline). False if it was already sent.
    func cancelPlanDelete(entryID: Int) -> Bool {
        guard let i = ops.lastIndex(where: { if case .deletePlanEntry(let id) = $0 { id == entryID } else { false } }) else { return false }
        ops.remove(at: i); save()
        return true
    }

    func clear() {
        ops = []; save()
        try? FileManager.default.removeItem(at: Self.photoDirectory)
    }

    // MARK: Photos waiting to go with a queued "I made this"

    /// Where queued cook photos wait (Application Support, excluded from backups, removed with the queue).
    nonisolated static var photoDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OutboxPhotos", isDirectory: true)
    }

    /// Keeps a photo until its "I made this" is sent; returns the name to queue, or nil if it couldn't be saved.
    nonisolated static func keepPhoto(_ jpeg: Data) -> String? {
        var dir = photoDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        let name = UUID().uuidString + ".jpg"
        do {
            try jpeg.write(to: dir.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return name
        } catch { return nil }
    }

    nonisolated static func keptPhoto(_ name: String) -> Data? {
        try? Data(contentsOf: photoDirectory.appendingPathComponent(name))
    }

    nonisolated static func discardPhoto(_ name: String?) {
        guard let name else { return }
        try? FileManager.default.removeItem(at: photoDirectory.appendingPathComponent(name))
    }

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
                Self.discardPhoto(op.photoName)
            } catch let error as APIError where error.isOffline || error.isUnauthorized {
                return
            } catch {
                ops.removeFirst(); save()   // rejected: nothing sensible to retry
                Self.discardPhoto(op.photoName)
            }
        }
        session.recipesChanged()
    }

    private func send(_ op: OutboxOp, _ session: Session) async throws {
        struct Checked: Encodable, Sendable { let checked: Bool }
        struct Name: Encodable, Sendable { let name: String }
        struct Score: Encodable, Sendable { let score: Int }
        struct PlanAdd: Encodable, Sendable { let recipeId: Int; let date: String; let mealType: String }
        struct PlanMove: Encodable, Sendable { let date: String; let mealType: String }
        switch op {
        case .favorite(let id, let wanted):
            try await session.run { try await $0.send(wanted ? "PUT" : "DELETE", "/recipes/\(id)/favorite") }
        case .rate(let id, let score):
            try await session.run { try await $0.send("PUT", "/recipes/\(id)/rating", body: Score(score: score)) }
        case .madeIt(let id, let note, let photo):
            let jpeg = photo.flatMap(Self.keptPhoto)
            do {
                _ = try await session.run { try await CookLog.logMade($0, recipeID: id, note: note, photo: jpeg) }
            } catch let APIError.server(status, _, _) where jpeg != nil && CookLog.isPhotoRejection(status) {
                // The server won't take the photo (too big, not a picture): the cook still counts, without it.
                _ = try await session.run { try await CookLog.logMade($0, recipeID: id, note: note, photo: nil) }
            }
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
        case .addPlanEntry(_, let recipeID, let date, let mealType):
            try await session.run { try await $0.send("POST", "/mealplan", body: PlanAdd(recipeId: recipeID, date: date, mealType: mealType)) }
        case .movePlanEntry(let id, let date, let mealType):
            try await session.run { try await $0.send("PATCH", "/mealplan/\(id)", body: PlanMove(date: date, mealType: mealType)) }
        case .deletePlanEntry(let id):
            try await session.run { try await $0.send("DELETE", "/mealplan/\(id)") }
        }
    }

    private func save() {
        try? JSONEncoder().encode(ops).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

extension OutboxOp {
    /// The queued photo file this change carries, if any.
    var photoName: String? { if case .madeIt(_, _, let photo) = self { photo } else { nil } }
}

extension APIError {
    var isUnauthorized: Bool { if case .unauthorized = self { true } else { false } }
}
