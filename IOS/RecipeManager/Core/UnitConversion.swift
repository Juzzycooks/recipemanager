import Foundation
import Synchronization

/// Which measuring system to show amounts in. `original` leaves recipes exactly as written.
enum UnitSystem: String, CaseIterable, Identifiable, Sendable {
    case original, metric, imperial

    static let storageKey = "unitSystem"
    var id: String { rawValue }
    var title: String {
        switch self { case .original: "As written"; case .metric: "Metric"; case .imperial: "US" }
    }

    /// The saved preference from Settings.
    static var preferred: UnitSystem { UnitSystem(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .original }
}

/// The ingredient table behind cup and ounce conversion, from the server's `GET /units` (static/unit-ingredients.json).
struct UnitIngredients: Codable, Sendable {
    struct Solid: Codable, Sendable {
        let name: String
        let gramsPerCup: Double
        let usCups: Bool
    }
    let liquids: [String]
    let solids: [Solid]
}

/// Converts amounts and oven temperatures inside ingredient lines and method steps, for display only.
/// Anything it can't read confidently (no unit, odd wording) is left exactly as written.
enum UnitConversion {
    static func convert(_ text: String, to system: UnitSystem) -> String {
        guard system != .original, !text.isEmpty else { return text }
        return amounts(temperatures(text, to: system), to: system)
    }

    // MARK: Units

    private enum Kind { case weight, volume }

    private struct Unit {
        let kind: Kind
        let toBase: Double      // grams or millilitres
        let metric: Bool
        var spoon = false       // tsp / tbsp: spices and small amounts, kept as spoons when converting to metric
        var cup = false         // cups measure dry goods too, so what they become depends on the ingredient
    }

    private static func unit(_ raw: String, remainder: Substring) -> Unit? {
        let key = raw.lowercased().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
        switch key {
        case "lb", "lbs", "pound", "pounds": return Unit(kind: .weight, toBase: 453.592, metric: false)
        case "oz", "ounce", "ounces":
            return ingredient(remainder) == .liquid ? Unit(kind: .volume, toBase: 29.5735, metric: false) : Unit(kind: .weight, toBase: 28.3495, metric: false)
        case "floz", "fluidounce", "fluidounces": return Unit(kind: .volume, toBase: 29.5735, metric: false)
        case "cup", "cups": return Unit(kind: .volume, toBase: 236.588, metric: false, cup: true)
        case "tbsp", "tbsps", "tbs", "tablespoon", "tablespoons": return Unit(kind: .volume, toBase: 14.7868, metric: false, spoon: true)
        case "tsp", "tsps", "teaspoon", "teaspoons": return Unit(kind: .volume, toBase: 4.92892, metric: false, spoon: true)
        case "pint", "pints", "pt": return Unit(kind: .volume, toBase: 473.176, metric: false)
        case "quart", "quarts", "qt": return Unit(kind: .volume, toBase: 946.353, metric: false)
        case "gallon", "gallons": return Unit(kind: .volume, toBase: 3785.41, metric: false)
        case "g", "gram", "grams": return Unit(kind: .weight, toBase: 1, metric: true)
        case "kg", "kilo", "kilos", "kilogram", "kilograms": return Unit(kind: .weight, toBase: 1000, metric: true)
        case "ml", "milliliter", "milliliters", "millilitre", "millilitres": return Unit(kind: .volume, toBase: 1, metric: true)
        case "l", "liter", "liters", "litre", "litres": return Unit(kind: .volume, toBase: 1000, metric: true)
        default: return nil
        }
    }

    // MARK: Ingredients

    /// What a cup (or an ounce) of something is: poured, or a dry good with a known weight per US cup.
    private enum Ingredient: Equatable {
        case liquid
        case solid(gramsPerCup: Double, cupsInUS: Bool)   // cupsInUS: US recipes measure it in cups (flour), not ounces (butter)
    }

    /// The table, ready to search.
    private struct Lookup: @unchecked Sendable {        // NSRegularExpression is immutable once built
        let solids: [String: Ingredient]
        let regex: NSRegularExpression?

        init(_ table: UnitIngredients) {
            solids = Dictionary(table.solids.map { ($0.name.lowercased(), .solid(gramsPerCup: $0.gramsPerCup, cupsInUS: $0.usCups)) },
                                uniquingKeysWith: { first, _ in first })
            // Longest names first, so "peanut butter" wins over "peanut" and "buttermilk" over "butter" at the same spot.
            let names = (table.liquids + table.solids.map(\.name)).sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:))
            regex = names.isEmpty ? nil
                : try? NSRegularExpression(pattern: "(?<![\\w-])(\(names.joined(separator: "|")))(?:e?s)?(?![\\w-])", options: .caseInsensitive)
        }
    }

    private static let defaultsKey = "unitIngredients"
    /// Starts from the copy saved last time, so conversion works at launch and offline.
    private static let lookup = Mutex(Lookup(saved() ?? UnitIngredients(liquids: [], solids: [])))

    private static func saved() -> UnitIngredients? {
        UserDefaults.standard.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(UnitIngredients.self, from: $0) }
    }

    /// Switches to a table fetched from the server (`GET /units`) and keeps it for next launch.
    static func use(_ table: UnitIngredients, save: Bool = true) {
        guard !table.liquids.isEmpty || !table.solids.isEmpty else { return }
        lookup.withLock { $0 = Lookup(table) }
        if save, let data = try? JSONEncoder().encode(table) { UserDefaults.standard.set(data, forKey: defaultsKey) }
    }

    /// The first ingredient named soon after an amount: "1 cup water, plus flour for dusting" is water.
    /// Nil when nothing is recognised (or the table hasn't arrived yet), which leaves cups as written.
    private static func ingredient(_ remainder: Substring) -> Ingredient? {
        let nearby = String(remainder.prefix(50))
        let table = lookup.withLock { $0 }
        guard let match = table.regex?.firstMatch(in: nearby, range: NSRange(location: 0, length: (nearby as NSString).length)) else { return nil }
        let name = (nearby as NSString).substring(with: match.range(at: 1)).lowercased()
        return table.solids[name] ?? .liquid
    }

    // MARK: Amounts

    private static let fraction = "[¼½¾⅓⅔⅛⅜⅝⅞]"
    private static let quantity = "(?:\\d+\\s+\\d+/\\d+|\\d+\\s*\(fraction)|\\d+/\\d+|\\d+(?:[.,]\\d+)?|\(fraction))"
    private static let unitWords = "fluid\\s+ounces?|fl\\.?\\s?oz|pounds?|lbs?|ounces?|oz|cups?|tablespoons?|tbsps?|tbs|teaspoons?|tsps?|pints?|pt|quarts?|qt|gallons?|kilograms?|kilos?|kg|grams?|g|milliliters?|millilitres?|ml|liters?|litres?|l"
    private static let amountPattern = "(?<![\\w/.,])(\(quantity))(?:\\s*(?:-|–|—|to)\\s*(\(quantity)))?\\s*(\(unitWords))\\b(?:\\.(?=\\s+[a-z]))?"
    private static let amountRegex = try! NSRegularExpression(pattern: amountPattern, options: .caseInsensitive)
    private static let parenRegex = try! NSRegularExpression(pattern: "^\\s*\\(\\s*([^()]*?)\\s*\\)", options: [])

    private static func amounts(_ text: String, to system: UnitSystem) -> String {
        let source = text as NSString
        let result = NSMutableString(string: text)
        let wantMetric = system == .metric
        for match in amountRegex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            let after = source.substring(from: match.range.upperBound)
            guard let from = unit(source.substring(with: match.range(at: 3)), remainder: Substring(after)), from.metric != wantMetric, !(wantMetric && from.spoon),
                  let low = number(source.substring(with: match.range(at: 1))) else { continue }
            var range = match.range
            // "1 lb (450 g)": the recipe already gives the other system, so use that instead of converting.
            if let paren = parenRegex.firstMatch(in: after, range: NSRange(location: 0, length: (after as NSString).length)) {
                let inner = (after as NSString).substring(with: paren.range(at: 1))
                if let own = amountRegex.firstMatch(in: inner, range: NSRange(location: 0, length: (inner as NSString).length)),
                   own.range.location == 0, own.range.length == (inner as NSString).length,
                   let theirs = unit((inner as NSString).substring(with: own.range(at: 3)), remainder: ""), theirs.metric == wantMetric {
                    range.length = paren.range.upperBound + match.range.length
                    result.replaceCharacters(in: range, with: inner)
                    continue
                }
            }
            // What one of the written unit comes to, in grams or millilitres.
            var kind = from.kind, perUnit = from.toBase, cupsOnly = false
            let food = ingredient(Substring(after))
            if wantMetric, from.cup {
                // A cup of nuts is weighed, a cup of milk is poured; a cup of something unknown stays a cup.
                switch food {
                case .liquid?: break
                case .solid(let grams, _)?: (kind, perUnit) = (.weight, grams)
                case nil: continue
                }
            } else if !wantMetric, from.kind == .weight, case .solid(let grams, true)? = food {
                (kind, perUnit, cupsOnly) = (.volume, from.toBase / grams * 236.588, true)   // 250 g flour -> 2 cups
            }
            let high = match.range(at: 2).location == NSNotFound ? nil : number(source.substring(with: match.range(at: 2)))
            var a = render(low * perUnit, kind: kind, metric: wantMetric, cupsOnly: cupsOnly)
            if let high {
                var b = render(high * perUnit, kind: kind, metric: wantMetric, cupsOnly: cupsOnly)
                if wantMetric, a.unit != b.unit {   // a range that crosses 1 kg / 1 L reads best in the bigger unit for both ends
                    a = (plain(round(low * perUnit / 1000, to: 0.05)), b.unit)
                    b = (plain(round(high * perUnit / 1000, to: 0.05)), b.unit)
                }
                result.replaceCharacters(in: range, with: a.unit == b.unit ? "\(a.value)–\(b.value) \(a.unit)" : "\(a.value) \(a.unit)–\(b.value) \(b.unit)")
            } else {
                result.replaceCharacters(in: range, with: "\(a.value) \(a.unit)")
            }
        }
        return result as String
    }

    // MARK: Numbers

    private static let glyphs: [Character: Double] = ["¼": 0.25, "½": 0.5, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875]

    private static func number(_ raw: String) -> Double? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if let glyph = s.last, let value = glyphs[glyph] {
            let whole = Double(s.dropLast().trimmingCharacters(in: .whitespaces)) ?? 0
            return whole + value
        }
        if s.contains("/") {
            let parts = s.split(whereSeparator: { $0 == " " || $0 == "/" }).compactMap { Double($0) }
            if parts.count == 3, parts[2] != 0 { return parts[0] + parts[1] / parts[2] }
            if parts.count == 2, parts[1] != 0 { return parts[0] / parts[1] }
            return nil
        }
        return Double(s.replacingOccurrences(of: ",", with: "."))
    }

    private static func round(_ value: Double, to step: Double) -> Double { (value / step).rounded() * step }

    private static func plain(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.contains("."), text.hasSuffix("0") || text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// 1.5 -> "1 ½", 0.25 -> "¼"; rounded to the nearest `step`.
    private static func fractional(_ value: Double, step: Double) -> String {
        let v = max(round(value, to: step), step)
        let whole = Int(v.rounded(.down)), rest = v - Double(whole)
        let glyph: String
        switch rest {
        case 0.99...: return "\(whole + 1)"
        case 0.87...: glyph = "⅞"
        case 0.7...: glyph = "¾"
        case 0.6...: glyph = "⅝"
        case 0.45...: glyph = "½"
        case 0.35...: glyph = "⅜"
        case 0.3...: glyph = "⅓"
        case 0.2...: glyph = "¼"
        case 0.1...: glyph = "⅛"
        default: return "\(whole)"
        }
        return whole == 0 ? glyph : "\(whole) \(glyph)"
    }

    /// An amount in grams or millilitres, written the way a cook in that system would.
    /// `cupsOnly`: dry goods go up to cups but never quarts (8 cups of flour, not 2 qt).
    private static func render(_ base: Double, kind: Kind, metric: Bool, cupsOnly: Bool = false) -> (value: String, unit: String) {
        if metric {
            var v = base < 5 ? round(base, to: 0.5) : base < 10 ? round(base, to: 1) : base < 100 ? round(base, to: 5) : round(base, to: 10)
            if v >= 1000 { v = round(v / 1000, to: 0.05); return (plain(v), kind == .weight ? "kg" : "L") }
            return (plain(max(v, 0.5)), kind == .weight ? "g" : "ml")
        }
        switch kind {
        case .weight:
            let oz = base / 28.3495
            if base < 450 { return (oz < 1 ? fractional(oz, step: 0.25) : fractional(oz, step: oz < 10 ? 0.5 : 1), "oz") }
            return (fractional(base / 453.592, step: 0.25), "lb")
        case .volume:
            if base < 15 { return (fractional(base / 4.92892, step: 0.25), "tsp") }
            if base < 60 { return (fractional(base / 14.7868, step: 0.5), "tbsp") }
            if base < 950 || cupsOnly {
                let cups = base / 236.588
                return (fractional(cups, step: 0.25), cups > 1.12 ? "cups" : "cup")
            }
            return (fractional(base / 946.353, step: 0.25), "qt")
        }
    }

    // MARK: Temperatures

    private static let degrees = "(?:°|º|˚)"
    private static let fahrenheit = try! NSRegularExpression(
        pattern: "(?<![\\d.])(\\d{2,3})(?:\\s*\(degrees)\\s*|\\s+degrees?\\s+|(?=F\\b))F(?:ahrenheit)?\\b(?:\\s*\\(\\s*(\\d{2,3})\\s*\(degrees)?\\s*C(?:elsius)?\\s*\\))?", options: [])
    private static let celsius = try! NSRegularExpression(
        pattern: "(?<![\\d.])(\\d{2,3})(?:\\s*\(degrees)\\s*|\\s+degrees?\\s+)C(?:elsius)?\\b(?:\\s*\\(\\s*(\\d{2,3})\\s*\(degrees)?\\s*F(?:ahrenheit)?\\s*\\))?", options: [])

    private static func temperatures(_ text: String, to system: UnitSystem) -> String {
        let regex = system == .metric ? fahrenheit : celsius
        let source = text as NSString
        let result = NSMutableString(string: text)
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            guard let value = Double(source.substring(with: match.range(at: 1))) else { continue }
            let given = match.range(at: 2).location == NSNotFound ? nil : source.substring(with: match.range(at: 2))
            let out: String
            if let given { out = given }        // already written both ways: keep the author's own figure
            else if system == .metric { out = String(Int(round((value - 32) * 5 / 9, to: 5))) }
            else { out = String(Int(round(value * 9 / 5 + 32, to: 5))) }
            result.replaceCharacters(in: match.range, with: "\(out)°\(system == .metric ? "C" : "F")")
        }
        return result as String
    }
}
