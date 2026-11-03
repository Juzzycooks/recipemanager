import Foundation
import Observation

/// The app's one "Undo" offer. A change that can be taken back (removing a planned meal, clearing ticked items,
/// deleting a recipe) offers it here; `StatusStack` shows it beside the other pills.
///
/// - Only one offer at a time: a newer one replaces it, and the replaced one simply commits.
/// - An offer expires after `duration` and commits.
/// - `perform()` runs the undo instead; the offer's commit is then never run.
///
/// `commit` is for changes that are held back until the offer ends (Clear completed deletes then); a change that
/// was made at once (removing a meal) has nothing to commit.
@MainActor @Observable
final class UndoCenter {
    struct Offer: Identifiable, Equatable {
        let id = UUID()
        let message: String
        fileprivate let undo: @MainActor () async -> Void
        fileprivate let commit: @MainActor () async -> Void

        static func == (a: Offer, b: Offer) -> Bool { a.id == b.id }
    }

    private(set) var current: Offer?
    /// How long an offer stays when none is given.
    let duration: Duration
    @ObservationIgnored private var expiry: Task<Void, Never>?

    init(duration: Duration = .seconds(6)) { self.duration = duration }

    /// Shows a new offer at once, then commits the one it replaces.
    @discardableResult
    func offer(_ message: String, for duration: Duration? = nil,
               commit: @escaping @MainActor () async -> Void = {},
               undo: @escaping @MainActor () async -> Void) async -> Offer.ID {
        let replaced = current
        let offer = Offer(message: message, undo: undo, commit: commit)
        current = offer
        expiry?.cancel()
        let wait = duration ?? self.duration, id = offer.id
        expiry = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            await self?.expire(id)
        }
        if let replaced { await replaced.commit() }
        return offer.id
    }

    /// Takes the change back (the Undo button).
    func perform() async {
        guard let offer = current else { return }
        end()
        await offer.undo()
    }

    /// The offer's time is up: it goes away and commits. Does nothing if that offer has already gone.
    func expire(_ id: Offer.ID) async {
        guard let offer = current, offer.id == id else { return }
        end()
        await offer.commit()
    }

    /// Ends the current offer now and commits it (before a change that would conflict with it, or leaving the app).
    func commitNow() async {
        guard let offer = current else { return }
        end()
        await offer.commit()
    }

    /// Takes an offer away without committing or undoing (the change it offered to undo failed).
    func withdraw(_ id: Offer.ID) {
        guard current?.id == id else { return }
        end()
    }

    private func end() {
        current = nil
        expiry?.cancel()
        expiry = nil
    }
}
