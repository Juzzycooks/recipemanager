import Foundation

/// Which ingredients does a step mention? A port of `matchIngredients` in static/js/cook.js, so cook mode
/// on the phone and on the web list the same things. Prefers ingredients from the step's own "# Section".
enum StepIngredients {
    private static let stop: Set<String> = Set(("fresh large small medium big ripe chopped diced sliced minced grated ground cold warm hot boiling plain extra virgin " +
        "dried whole skinless boneless finely roughly coarsely thinly freshly to taste for serving optional and or of the a an plus more " +
        "about approximately a few some good quality your favourite favorite each into in with at").split(separator: " ").map(String.init))
    private static let units: Set<String> = Set(("g kg mg ml l oz lb lbs cup cups tbsp tsp tablespoon tablespoons teaspoon teaspoons clove cloves pinch pinches handful " +
        "handfuls can cans tin tins slice slices stick sticks sprig sprigs bunch bunches piece pieces dash splash knob head heads").split(separator: " ").map(String.init))

    private static func stem(_ word: String) -> String {
        let w = word.lowercased()
        if w.count > 4, w.hasSuffix("ies") { return String(w.dropLast(3)) + "y" }
        if w.count > 4, ["oes", "ches", "shes", "sses", "xes"].contains(where: w.hasSuffix) { return String(w.dropLast(2)) }
        if w.count > 3, w.hasSuffix("s"), !w.hasSuffix("ss") { return String(w.dropLast()) }
        return w
    }

    private static func tokens(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
    }

    /// "250 g bread flour, sifted" -> "flour" (the last meaningful word, stemmed).
    private static func head(of ingredient: String) -> String? {
        var text = ingredient
        while let open = text.firstIndex(of: "("), let close = text[open...].firstIndex(of: ")") { text.replaceSubrange(open...close, with: " ") }
        let first = text.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? text
        let words = tokens(first).filter { $0.count > 1 && !stop.contains($0) && !units.contains($0) }
        guard let last = words.last else { return nil }
        let h = stem(last)
        return h.count >= 3 ? h : nil
    }

    static func match(step: String, section: String?, in sections: [RecipeSection]) -> [String] {
        let stepStems = Set(tokens(step).map(stem))
        func run(_ lines: [String]) -> [String] { lines.filter { line in head(of: line).map(stepStems.contains) ?? false } }
        if let section, !section.isEmpty {
            let same = sections.filter { $0.heading?.lowercased() == section.lowercased() }.flatMap(\.lines)
            let hit = run(same)
            if !hit.isEmpty { return hit }
        }
        return run(sections.flatMap(\.lines))
    }
}
