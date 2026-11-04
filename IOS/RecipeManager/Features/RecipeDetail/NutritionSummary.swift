import Foundation

/// What the recipe page's nutrition block says, worked out from `nutrition_facts` (or the older `nutrition` estimate)
/// and the page's ½×–3× scale. Pure, so the wording is tested rather than eyeballed; the view only lays it out.
/// Per-serving figures never scale; whole-recipe figures and the yield do.
struct NutritionSummary: Equatable, Sendable {
    struct Macro: Equatable, Sendable {
        let name: String     // "Protein"
        let grams: String    // "32 g"
        var spoken: String { "\(name) \(grams.replacingOccurrences(of: " g", with: " grams"))" }
    }

    /// One ingredient line in "How this was estimated".
    struct ExplainedLine: Equatable, Sendable, Identifiable {
        let id: Int
        let text: String
        /// "plain flour · 300 g", when the estimate matched a food.
        let detail: String?
        /// "455 kcal" or "—".
        let value: String
        /// "not counted" (negligible) or "not recognised" (unmatched); nil when counted.
        let note: String?
        /// The whole row for VoiceOver, as one element.
        let spoken: String
    }

    /// The big number: "520".
    let headline: String
    /// Beside it: "kcal per serving", "kcal per cookie", or "kcal whole recipe".
    let headlineUnit: String
    /// The headline for VoiceOver: "520 calories per serving".
    let headlineSpoken: String
    /// Under it, when the headline is per serving: "2,080 kcal whole recipe · serves 4".
    let totalLine: String?
    /// Protein, carbs and fat that are known (nulls are left out, never shown as 0).
    let macros: [Macro]
    /// What the macros are for: "Per serving", "Per cookie" or "Whole recipe".
    let macrosBasis: String?
    /// "From the recipe", "You entered", "Estimate · medium confidence", or nil for a source we don't know.
    let sourceLabel: String?
    /// The estimate's lines can be shown ("How this was estimated").
    let canExplain: Bool
    /// The button title for that: "How this was estimated", or "See our estimate" when the figures came from elsewhere.
    let explainTitle: String

    init?(recipe: RecipeDetail, scale: Double = 1, locale: Locale = .current) {
        let facts: NutritionFacts
        if let f = recipe.nutritionFacts, f.hasFigures {
            facts = f
        } else if let n = recipe.nutrition {
            facts = Self.facts(fromLegacy: n)
        } else {
            return nil
        }
        self.init(facts: facts, scale: scale, locale: locale)
    }

    init?(facts: NutritionFacts, scale: Double = 1, locale: Locale = .current) {
        let servings = facts.servings.flatMap { $0 >= 1 ? $0 : nil }
        // Whole recipe: what the server sent, else the estimate (it is for the whole recipe), else per serving × servings.
        var total = facts.total ?? (facts.source == .estimate || facts.source == nil ? facts.estimate?.amounts : nil)
        var per = facts.perServing
        if let s = servings {
            if total?.kcal == nil, let p = per { total = Self.times(p, Double(s), keeping: total) }
            if per?.kcal == nil, let t = total { per = Self.times(t, 1 / Double(s), keeping: per) }
        }
        let unitOne = Self.singular(facts.yieldUnit)
        let fmt = { (v: Double) in Self.number(v, locale: locale) }

        if let perKcal = per?.kcal {
            headline = fmt(perKcal)
            headlineUnit = "kcal per \(unitOne)"
            headlineSpoken = "\(fmt(perKcal)) calories per \(unitOne)"
            if let totalKcal = total?.kcal {
                var parts = ["\(fmt(totalKcal * scale)) kcal whole recipe"]
                if let s = servings { parts.append(Self.yield(Double(s) * scale, unit: facts.yieldUnit, locale: locale)) }
                totalLine = parts.joined(separator: " · ")
            } else {
                totalLine = nil
            }
        } else if let totalKcal = total?.kcal {
            headline = fmt(totalKcal * scale)
            headlineUnit = "kcal whole recipe"
            headlineSpoken = "\(fmt(totalKcal * scale)) calories for the whole recipe"
            totalLine = nil
        } else {
            return nil
        }

        // Macros per serving when any are known there, else whole recipe (scaled).
        let perMacros = Self.macros(per, factor: 1)
        if !perMacros.isEmpty {
            macros = perMacros
            macrosBasis = "Per \(unitOne)"
        } else {
            macros = Self.macros(total, factor: scale)
            macrosBasis = macros.isEmpty ? nil : "Whole recipe"
        }

        if facts.source == .manual {
            sourceLabel = "You entered"
        } else if facts.source == .recipe {
            sourceLabel = "From the recipe"
        } else if facts.source == .estimate || facts.source == nil {
            sourceLabel = facts.estimate?.confidence.map { "Estimate · \(Self.confidenceWord($0)) confidence" } ?? "Estimate"
        } else {
            sourceLabel = nil   // a source this build doesn't know: show the figures, claim nothing about them
        }
        canExplain = !(facts.estimate?.lines.isEmpty ?? true)
        explainTitle = facts.source == .estimate || facts.source == nil ? "How this was estimated" : "See our estimate"
    }

    // MARK: Explanation

    /// "Counted 9 of 11 ingredients".
    static func countedLine(_ estimate: NutritionFacts.Estimate) -> String? {
        let total = estimate.totalLines ?? (estimate.lines.isEmpty ? nil : estimate.lines.count)
        let counted = estimate.countedLines ?? estimate.matched
            ?? (estimate.lines.isEmpty ? nil : estimate.lines.filter { $0.status != .unmatched }.count)
        guard let total, let counted, total > 0 else { return nil }
        return "Counted \(counted) of \(total) ingredient\(total == 1 ? "" : "s")"
    }

    static func explainedLines(_ estimate: NutritionFacts.Estimate, locale: Locale = .current) -> [ExplainedLine] {
        estimate.lines.enumerated().map { index, line in
            let food = line.food.flatMap { $0.isEmpty ? nil : $0 }
            let grams = line.grams.map { "\(number($0, locale: locale)) g" }
            let detail = [food, grams].compactMap { $0 }.joined(separator: " · ")
            let value: String, note: String?, spokenValue: String
            if line.status == .negligible {
                (value, note, spokenValue) = ("—", "not counted", "not counted")
            } else if let kcal = line.kcal, line.status != .unmatched {
                (value, note, spokenValue) = ("\(number(kcal, locale: locale)) kcal", nil, "\(number(kcal, locale: locale)) calories")
            } else if line.status == .matched {
                (value, note, spokenValue) = ("—", nil, "no calories")
            } else {
                (value, note, spokenValue) = ("—", "not recognised", "not recognised")
            }
            let spokenDetail = [food.map { "read as \($0)" }, line.grams.map { "\(number($0, locale: locale)) grams" }]
                .compactMap { $0 }.joined(separator: ", ")
            let spoken = [line.text, spokenDetail.isEmpty ? nil : spokenDetail, spokenValue].compactMap { $0 }.joined(separator: ", ")
            return ExplainedLine(id: index, text: line.text, detail: detail.isEmpty ? nil : detail, value: value, note: note, spoken: spoken)
        }
    }

    // MARK: Wording helpers

    /// "cookies" → "cookie", "loaves" → "loaf", nil or "servings" → "serving".
    static func singular(_ unit: String?) -> String {
        let trimmed = (unit ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return "serving" }
        var words = trimmed.split(separator: " ").map(String.init)
        let last = words.removeLast()
        return (words + [singularWord(last)]).joined(separator: " ")
    }

    /// "serves 4", or "makes 12 cookies" / "makes 1 loaf" for other units.
    static func yield(_ count: Double, unit: String?, locale: Locale = .current) -> String {
        let one = singular(unit)
        let n = count.rounded() == count ? number(count, locale: locale) : count.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        if one == "serving" { return "serves \(n)" }
        return "makes \(n) \(count == 1 ? one : plural(one))"
    }

    private static let irregular: [String: String] = [
        "cookies": "cookie", "brownies": "brownie", "pies": "pie", "smoothies": "smoothie", "loaves": "loaf",
        "halves": "half", "knives": "knife", "leaves": "leaf", "people": "person", "potatoes": "potato", "tomatoes": "tomato",
    ]

    private static func singularWord(_ word: String) -> String {
        if let found = irregular[word] { return found }
        if word.hasSuffix("ies"), word.count > 4 { return String(word.dropLast(3)) + "y" }      // patties
        for ending in ["ches", "shes", "sses", "xes", "zes"] where word.hasSuffix(ending) { return String(word.dropLast(2)) }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), word.count > 2 { return String(word.dropLast()) }
        return word
    }

    private static func plural(_ word: String) -> String {
        if let found = irregular.first(where: { $0.value == word })?.key { return found }
        let last = word.split(separator: " ").last.map(String.init) ?? word
        let head = word.dropLast(last.count)
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        let out: String
        if last.hasSuffix("y"), let before = last.dropLast().last, !vowels.contains(before) { out = String(last.dropLast()) + "ies" }
        else if ["ch", "sh", "s", "x", "z"].contains(where: { last.hasSuffix($0) }) { out = last + "es" }
        else { out = last + "s" }
        return String(head) + out
    }

    private static func confidenceWord(_ c: NutritionFacts.Confidence) -> String {
        c.rawValue.isEmpty ? "unknown" : c.rawValue.lowercased()
    }

    /// Whole calories or grams, with the locale's grouping: "2,080".
    static func number(_ value: Double, locale: Locale = .current) -> String {
        Int(value.rounded()).formatted(.number.locale(locale))
    }

    private static func macros(_ a: NutritionFacts.Amounts?, factor: Double) -> [Macro] {
        guard let a else { return [] }
        return [("Protein", a.protein), ("Carbs", a.carbs), ("Fat", a.fat)].compactMap { name, value in
            value.map { Macro(name: name, grams: "\(Int(($0 * factor).rounded())) g") }
        }
    }

    private static func times(_ a: NutritionFacts.Amounts, _ k: Double, keeping known: NutritionFacts.Amounts?) -> NutritionFacts.Amounts {
        NutritionFacts.Amounts(kcal: known?.kcal ?? a.kcal.map { $0 * k }, protein: known?.protein ?? a.protein.map { $0 * k },
                               fat: known?.fat ?? a.fat.map { $0 * k }, carbs: known?.carbs ?? a.carbs.map { $0 * k })
    }

    /// The pre-`nutrition_facts` shape: always an estimate for the whole recipe, plus per serving when servings were known.
    static func facts(fromLegacy n: Nutrition) -> NutritionFacts {
        NutritionFacts(source: .estimate, servings: n.servings, yieldUnit: "serving",
                       perServing: n.perServing.map { .init(kcal: $0.kcal, protein: $0.protein, fat: $0.fat, carbs: $0.carbs) },
                       total: .init(kcal: n.kcal, protein: n.protein, fat: n.fat, carbs: n.carbs))
    }
}
