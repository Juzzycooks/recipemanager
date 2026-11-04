import Foundation

/// When the shopping list asks the server whether someone else changed it (households share one list).
///
/// While the list is on screen and the app is active it asks `GET /shopping/version` every 15 seconds (and once on
/// coming back to the app), and reloads only when the version moved. It never asks, and never reloads over, a list
/// with changes of this phone's own still on the way: offline, queued in the Outbox, a request in flight, or a held-back
/// "Clear completed" with its Undo on offer. Those would otherwise flash back to the server's copy.
enum ShoppingPoll {
    static let interval: Duration = .seconds(15)

    struct Conditions: Equatable {
        var offline = false
        /// The server has no `/shopping/version` (an older one): stop asking.
        var unsupported = false
        /// Nothing loaded yet: the first load is the screen's own job.
        var hasList = true
        /// Shopping changes waiting in the Outbox, or the Outbox replaying.
        var pendingChanges = false
        /// An add, tick, delete or clear from this screen still on its way.
        var busy = false
        /// An Undo is on offer (a held-back "Clear completed" would come back on a reload).
        var undoOffered = false
    }

    /// Whether to ask the server for its version now.
    static func shouldAsk(_ c: Conditions) -> Bool {
        !c.offline && !c.unsupported && c.hasList && !c.pendingChanges && !c.busy && !c.undoOffered
    }

    /// Whether the server's answer means the list here is out of date. A nil answer (a server without versions)
    /// never does; a list saved without a version (before the update) does once the server has one.
    static func needsReload(have: String?, server: String?) -> Bool {
        guard let server, !server.isEmpty else { return false }
        return have != server
    }
}

extension OutboxOp {
    /// A queued change to the shopping list.
    var isShopping: Bool {
        switch self {
        case .addShoppingItem, .setShoppingChecked, .deleteShoppingItem: true
        default: false
        }
    }
}
