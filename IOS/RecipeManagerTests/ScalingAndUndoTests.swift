import Foundation
import Testing
@testable import RecipeManager

/// The same cases as `tests/test_units.js`, which runs `scaleLine` in `static/units.js`: keep the two lists identical.
struct IngredientScalingTests {
    private func scale(_ line: String, _ factor: Double) -> String { IngredientScaling.scale(line, by: factor) }

    @Test func mixedNumbersFractionsGlyphsAndDecimals() {
        #expect(scale("1 1/2 cups flour", 2) == "3 cups flour")
        #expect(scale("½ cup oil", 2) == "1 cup oil")
        #expect(scale("1½ tbsp honey", 2) == "3 tbsp honey")
        #expect(scale("1 ½ tbsp honey", 2) == "3 tbsp honey")
        #expect(scale("1/2 tsp salt", 3) == "1 ½ tsp salt")
        #expect(scale("0.5 kg beef", 3) == "1 ½ kg beef")
        #expect(scale("1,5 l stock", 2) == "3 l stock")
        #expect(scale(".5 cup milk", 3) == "1 ½ cup milk")
        #expect(scale("⅛ tsp chilli", 2) == "¼ tsp chilli")
    }

    @Test func resultsAreFractionsWhenCloseOtherwiseTwoPlaces() {
        #expect(scale("3 eggs", 0.5) == "1 ½ eggs")
        #expect(scale("1/3 cup sugar", 2) == "⅔ cup sugar")
        #expect(scale("2/3 cup sugar", 0.5) == "⅓ cup sugar")
        #expect(scale("3/4 cup milk", 3) == "2 ¼ cup milk")
        #expect(scale("1 1/4 cups milk", 0.5) == "⅔ cups milk")
        #expect(scale("2 1/3 cups", 3) == "7 cups")
        #expect(scale("1/8 tsp salt", 0.5) == "0.06 tsp salt")
        #expect(scale("10 g yeast", 0.33) == "3 ⅓ g yeast")
        #expect(scale("250 g butter", 3) == "750 g butter")
        #expect(scale("0 g", 2) == "0 g")
        #expect(scale("2", 2) == "4")
    }

    @Test func onlyTheLeadingAmountChanges() {
        #expect(scale("2 x 400g tins tomatoes", 2) == "4 x 400g tins tomatoes")
        #expect(scale("400g flour", 0.5) == "200 g flour")
        #expect(scale("1 egg", 3) == "3 egg")
        #expect(scale("  2 eggs", 2) == "  4 eggs")
    }

    @Test func leavesEverythingElseAlone() {
        #expect(scale("Salt and pepper", 2) == "Salt and pepper")
        #expect(scale("a pinch of salt", 2) == "a pinch of salt")
        #expect(scale("Serves 4", 2) == "Serves 4")
        #expect(scale("100g", 1) == "100g")
        #expect(scale("1/0 cup water", 2) == "1/0 cup water")
    }

    /// Ranges scale both ends and keep their separator; a broken end leaves the line alone.
    @Test func rangesScaleBothEnds() {
        #expect(scale("1-2 cloves garlic", 2) == "2-4 cloves garlic")
        #expect(scale("1–2 cloves garlic", 2) == "2–4 cloves garlic")
        #expect(scale("1 - 2 tbsp oil", 3) == "3 - 6 tbsp oil")
        #expect(scale("1 to 2 cups stock", 2) == "2 to 4 cups stock")
        #expect(scale("½-1 cup milk", 2) == "1-2 cup milk")
        #expect(scale("1 1/2-2 cups flour", 0.5) == "¾-1 cups flour")
        #expect(scale("2-3 x 400g tins", 2) == "4-6 x 400g tins")
        #expect(scale("2-1/0 cup water", 2) == "2-1/0 cup water")
        #expect(scale("2 tomatoes", 2) == "4 tomatoes")
        #expect(scale("3 to taste", 2) == "6 to taste")
    }

    /// Thousands commas (groups of exactly three) vs decimal commas; results print without a separator.
    @Test func thousandsCommas() {
        #expect(scale("1,000 g flour", 2) == "2000 g flour")
        #expect(scale("1,500 ml water", 0.5) == "750 ml water")
        #expect(scale("1,000.5 g", 2) == "2001 g")
        #expect(scale("1,000-2,000 g", 0.5) == "500-1000 g")
        #expect(scale("1,25 l milk", 2) == "2 ½ l milk")
    }

    /// The web's quirks, pinned so both sides change together.
    @Test func knownQuirksMatchTheWeb() {
        #expect(scale("1-inch piece ginger", 2) == "2 -inch piece ginger")
        #expect(scale("180°C oven", 2) == "360 °C oven")
    }

    @Test func factorTitles() {
        #expect(IngredientScaling.factors.map(IngredientScaling.title) == ["½×", "1×", "2×", "3×"])
        #expect(IngredientScaling.spokenTitle(0.5) == "Half")
    }

    /// Scaling comes first, then metric / US conversion, as on the web.
    @Test func scalesBeforeConverting() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../static/unit-ingredients.json")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        UnitConversion.use(try decoder.decode(UnitIngredients.self, from: Data(contentsOf: file)), save: false)
        #expect(UnitConversion.convert(scale("1 lb chicken thighs", 2), to: .metric) == "910 g chicken thighs")
        #expect(UnitConversion.convert(scale("1-2 lb brisket", 2), to: .metric) == "0.9–1.8 kg brisket")
        #expect(UnitConversion.convert(scale("1-2 cups flour", 2), to: .metric) == "240–480 g flour")
        #expect(UnitConversion.convert(scale("1,000 ml water", 2), to: .imperial) == "2 qt water")
    }
}

/// The shared Undo offer: one at a time, the replaced one commits, it expires and commits, Undo runs instead of commit.
@MainActor struct UndoCenterTests {
    /// Records what each offer did.
    @MainActor final class Log { var events: [String] = [] }

    @discardableResult
    private func offer(_ center: UndoCenter, _ name: String, _ log: Log, for duration: Duration? = nil) async -> UndoCenter.Offer.ID {
        await center.offer(name, for: duration, commit: { log.events.append("commit \(name)") }, undo: { log.events.append("undo \(name)") })
    }

    @Test func undoRunsTheUndoAndNeverCommits() async {
        let center = UndoCenter(), log = Log()
        let id = await offer(center, "A", log)
        #expect(center.current?.message == "A")
        await center.perform()
        #expect(center.current == nil)
        await center.expire(id)     // too late: already gone
        await center.commitNow()
        await center.perform()      // a second tap does nothing
        #expect(log.events == ["undo A"])
    }

    @Test func aNewerOfferReplacesAndCommitsTheOlder() async {
        let center = UndoCenter(), log = Log()
        let first = await offer(center, "A", log)
        await offer(center, "B", log)
        #expect(center.current?.message == "B")
        #expect(log.events == ["commit A"])
        await center.expire(first)   // A's timer can't end B
        #expect(center.current?.message == "B")
        await center.perform()
        #expect(log.events == ["commit A", "undo B"])
    }

    @Test func expiryCommitsOnce() async {
        let center = UndoCenter(), log = Log()
        let id = await offer(center, "A", log)
        await center.expire(id)
        await center.expire(id)
        #expect(center.current == nil)
        #expect(log.events == ["commit A"])
    }

    @Test func theTimerEndsTheOffer() async throws {
        let center = UndoCenter(duration: .milliseconds(50)), log = Log()
        await offer(center, "A", log)
        for _ in 0..<100 where center.current != nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(center.current == nil)
        #expect(log.events == ["commit A"])
    }

    @Test func aReplacedOffersTimerDoesNotEndTheNewOne() async throws {
        let center = UndoCenter(), log = Log()
        await offer(center, "A", log, for: .milliseconds(30))
        await offer(center, "B", log, for: .seconds(30))
        try await Task.sleep(for: .milliseconds(150))
        #expect(center.current?.message == "B")
        #expect(log.events == ["commit A"])
    }

    @Test func commitNowAndWithdraw() async {
        let center = UndoCenter(), log = Log()
        await offer(center, "A", log)
        await center.commitNow()
        #expect(center.current == nil)
        let id = await offer(center, "B", log)
        center.withdraw(id)
        #expect(center.current == nil)
        await center.commitNow()
        #expect(log.events == ["commit A"])
    }
}
