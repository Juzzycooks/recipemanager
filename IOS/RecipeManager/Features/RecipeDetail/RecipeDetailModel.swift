import SwiftUI
import Observation

extension RecipeDetail {
    struct NumberedStep: Identifiable { let number: Int; let heading: String?; let section: String?; let text: String; var id: Int { number } }

    /// Steps flattened across sections and numbered 1…n; the first step of a section carries its heading.
    var numberedSteps: [NumberedStep] {
        var out: [NumberedStep] = []
        for section in instructionSections {
            for (i, line) in section.lines.enumerated() {
                out.append(NumberedStep(number: out.count + 1, heading: i == 0 ? section.heading : nil, section: section.heading, text: line))
            }
        }
        return out
    }

    /// The ingredient lines a step mentions (shown against the step in cook mode).
    func ingredients(for step: NumberedStep) -> [String] {
        StepIngredients.match(step: step.text, section: step.section, in: ingredientSections)
    }
}

/// Loads one recipe and performs everything you can do to it. The view only holds presentation state.
@MainActor @Observable
final class RecipeDetailModel {
    let id: Int
    var recipe: RecipeDetail?
    var error: String?

    init(id: Int) { self.id = id }

    func load(_ session: Session) async {
        do { recipe = try await session.run { [id] in try await $0.get("/recipes/\(id)") }; error = nil }
        catch is CancellationError {}
        catch let e as URLError where e.code == .cancelled {}
        catch { self.error = error.localizedDescription }
    }

    func toggleFavorite(_ session: Session) async {
        guard var r = recipe else { return }
        let wanted = !r.isFavorite
        r.isFavorite = wanted; recipe = r
        do { _ = try await session.runOrQueue(.favorite(recipeID: id, wanted: wanted)) { [id] in try await $0.send(wanted ? "PUT" : "DELETE", "/recipes/\(id)/favorite") }; session.recipesChanged() }
        catch { recipe?.isFavorite = !wanted; self.error = error.localizedDescription }
    }

    func rate(_ score: Int, _ session: Session) async {
        struct Body: Encodable, Sendable { let score: Int }
        struct Result: Decodable, Sendable { let myRating: Int?; let avgRating: Double?; let ratingCount: Int }
        do {
            let result: Result? = try await session.runOrQueue(.rate(recipeID: id, score: score)) { [id] in
                try await $0.send("PUT", "/recipes/\(id)/rating", body: Body(score: score))
            }
            if let result {
                recipe?.myRating = result.myRating; recipe?.avgRating = result.avgRating; recipe?.ratingCount = result.ratingCount
            } else {
                recipe?.myRating = score   // saved on this phone; sent when you're back online
            }
        } catch { self.error = error.localizedDescription }
    }

    func addToShopping(lines: [String], _ session: Session, _ app: AppState) async -> Bool {
        struct Body: Encodable, Sendable { let items: [String] }
        do {
            let counts: AddedCounts = try await session.run { [id] in
                lines.isEmpty ? try await $0.send("POST", "/shopping/recipe/\(id)")
                              : try await $0.send("POST", "/shopping/recipe/\(id)", body: Body(items: lines))
            }
            app.say("Added \(counts.added)" + (counts.merged > 0 ? ", combined \(counts.merged)" : "") + " to your list.")
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    /// "I made this", with an optional note and photo (cook mode's finish panel). Online it's one request (multipart
    /// when there's a photo). Offline it's queued with the note and the photo (kept on the phone until it's sent).
    func madeIt(_ session: Session, _ app: AppState, note: String = "", photo: Data? = nil) async {
        let id = self.id
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            var photoRefused: String?
            let result: MadeResult
            do {
                result = try await session.run { try await CookLog.logMade($0, recipeID: id, note: note, photo: photo) }
            } catch let APIError.server(status, _, message) where photo != nil && CookLog.isPhotoRejection(status) {
                // The server won't take this picture: log the cook anyway and say why the photo is missing.
                result = try await session.run { try await CookLog.logMade($0, recipeID: id, note: note, photo: nil) }
                photoRefused = message
            }
            let count = result.madeCount ?? ((recipe?.madeCount ?? 0) + 1)
            recipe?.madeCount = count; recipe?.lastMade = .now
            if let entry = result.entry { history.insert(entry, at: 0) }
            if let photoRefused { self.error = "Logged, but the photo wasn't saved. \(photoRefused)" }
            else { app.say("Logged. Made \(count) time\(count == 1 ? "" : "s").") }
        } catch let e as APIError where e.isOffline {
            let kept = photo.flatMap(Outbox.keepPhoto)
            let op = OutboxOp.madeIt(recipeID: id, note: note.isEmpty ? nil : note, photo: kept)
            Outbox.shared.enqueue(op)
            await OfflineStore.shared.apply(op)
            recipe?.madeCount = (recipe?.madeCount ?? 0) + 1; recipe?.lastMade = .now
            if photo != nil && kept == nil {
                // Couldn't keep the picture on the phone (no space): never drop it silently.
                self.error = "Saved without the photo: there wasn't room to keep it until you're online. Add it from Cook history later."
            } else {
                app.say(photo == nil ? "Saved. It will sync when you're online." : "Saved with your photo. It's sent when you're back online.")
            }
        } catch { self.error = error.localizedDescription }
    }

    /// Your past cooks of this recipe (newest first), for the photo strip. Empty on servers without cook history.
    var history: [CookEntry] = []
    var historyPhotos: [CookEntry] { history.filter(\.hasPhoto) }

    func loadHistory(_ session: Session) async {
        let id = self.id
        do {
            let result: ItemList<CookEntry> = try await session.run { try await $0.get("/recipes/\(id)/cook-history") }
            history = result.items
        } catch {
            // Older server (404), offline with nothing saved, or cancelled: the strip simply doesn't show.
        }
    }

    func postComment(_ text: String, _ session: Session) async -> Bool {
        struct Body: Encodable, Sendable { let text: String }
        do {
            let comment: RecipeComment = try await session.run { [id] in try await $0.send("POST", "/recipes/\(id)/comments", body: Body(text: text)) }
            recipe?.comments.insert(comment, at: 0)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func deleteComment(_ c: RecipeComment, _ session: Session) async {
        do {
            try await session.run { try await $0.send("DELETE", "/comments/\(c.id)") }
            recipe?.comments.removeAll { $0.id == c.id }
        } catch { self.error = error.localizedDescription }
    }

    func toggleShare(_ session: Session, _ app: AppState) async {
        struct Result: Decodable, Sendable { let shareUrl: String }
        let sharing = recipe?.shareUrl != nil
        do {
            if sharing {
                try await session.run { [id] in try await $0.send("DELETE", "/recipes/\(id)/share") }
                recipe?.shareUrl = nil; app.say("Stopped sharing.")
            } else {
                let result: Result = try await session.run { [id] in try await $0.send("POST", "/recipes/\(id)/share") }
                recipe?.shareUrl = result.shareUrl; app.say("Share link created.")
            }
        } catch { self.error = error.localizedDescription }
    }

    func duplicate(_ session: Session, _ app: AppState) async {
        do {
            let copy: RecipeDetail = try await session.run { [id] in try await $0.send("POST", "/recipes/\(id)/duplicate") }
            session.recipesChanged()
            app.say("Duplicated as “\(copy.title)”.")
        } catch { self.error = error.localizedDescription }
    }

    /// Returns true when deleted (the caller pops the screen). Offers Undo, which restores it from the server's trash.
    func delete(_ session: Session, _ app: AppState) async -> Bool {
        struct Result: Decodable, Sendable { let restoreToken: String }
        guard let title = recipe?.title else { return false }
        do {
            let result: Result = try await session.run { [id] in try await $0.send("DELETE", "/recipes/\(id)") }
            session.recipesChanged()
            let token = result.restoreToken
            await app.offerUndo("Deleted “\(title)”") { await session.restoreDeleted(token: token) }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
