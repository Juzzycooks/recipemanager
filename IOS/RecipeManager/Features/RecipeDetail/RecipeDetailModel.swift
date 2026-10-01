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

    func madeIt(_ session: Session, _ app: AppState) async {
        struct Result: Decodable, Sendable { let madeCount: Int }
        do {
            let result: Result? = try await session.runOrQueue(.madeIt(recipeID: id)) { [id] in try await $0.send("POST", "/recipes/\(id)/made") }
            let count = result?.madeCount ?? ((recipe?.madeCount ?? 0) + 1)
            recipe?.madeCount = count; recipe?.lastMade = .now
            app.say(result == nil ? "Saved. It will sync when you're online." : "Logged. Made \(count) time\(count == 1 ? "" : "s").")
        } catch { self.error = error.localizedDescription }
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

    /// Returns true when deleted (the caller pops the screen).
    func delete(_ session: Session) async -> Bool {
        struct Result: Decodable, Sendable { let restoreToken: String }
        guard let title = recipe?.title else { return false }
        do {
            let result: Result = try await session.run { [id] in try await $0.send("DELETE", "/recipes/\(id)") }
            session.recipeDeleted(title: title, token: result.restoreToken)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
