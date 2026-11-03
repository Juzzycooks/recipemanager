import Foundation

/// Scales the leading amount of an ingredient line, for display only ("1 1/2 cups" × 2 → "3 cups").
/// A Swift port of `scaleLine` in `static/units.js`: keep the two in step. Both run the same cases
/// (`IngredientScalingTests` here, `tests/test_units.js` on the web), including the web's quirks.
enum IngredientScaling {
    /// The factors the recipe page offers, as on the web (`templates/recipes/view.html`, the `.scale-btn` buttons).
    static let factors: [Double] = [0.5, 1, 2, 3]

    /// "½×", "1×", "2×", "3×".
    static func title(_ factor: Double) -> String {
        (factor == 0.5 ? "½" : format(factor)) + "×"
    }

    /// What VoiceOver reads for each factor (the web's aria-labels).
    static func spokenTitle(_ factor: Double) -> String {
        switch factor {
        case 0.5: "Half"
        case 1: "Original quantity"
        case 2: "Double"
        case 3: "Triple"
        default: "\(format(factor)) times"
        }
    }

    private static let glyphs: [Character: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "⅛": 0.125]
    private static let glyphsOut: [(value: Double, glyph: String)] = [(0.25, "¼"), (1.0 / 3, "⅓"), (0.5, "½"), (2.0 / 3, "⅔"), (0.75, "¾")]

    /// `QTY` and `QTY_RE` from units.js, with `\d` spelled `[0-9]` (ICU's `\d` also matches other scripts' digits).
    /// One amount: "1 1/2", "1/2", "1,000" or "1,000.5" (thousands: groups of exactly three), "1.5" or "1,5", "1½", "2", "½";
    /// the line may start with one amount or a range of two ("1-2", "1–2", "1 to 2"), whose separator is kept as written.
    private struct Pattern: @unchecked Sendable {   // NSRegularExpression is immutable once built
        static let amount = "(?:[0-9]+\\s+[0-9]+/[0-9]+|[0-9]+/[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+(?:\\.[0-9]+)?(?![0-9,])|[0-9]*[.,][0-9]+|[0-9]+\\s*[½¼¾⅓⅔⅛]|[0-9]+|[½¼¾⅓⅔⅛])"
        let regex = try? NSRegularExpression(
            pattern: "^(\\s*)(\(Pattern.amount))(?:(\\s*[-–—]\\s*|\\s+to\\s+)(\(Pattern.amount)))?\\s*")
        let thousands = try? NSRegularExpression(pattern: "^[0-9]{1,3}(,[0-9]{3})+(\\.[0-9]+)?$")
    }
    private static let quantity = Pattern()

    /// The line with its leading amount (or both ends of a leading range) multiplied by `factor`;
    /// unchanged at 1× or when there's no amount to read.
    static func scale(_ line: String, by factor: Double) -> String {
        guard factor != 1, let regex = quantity.regex else { return line }
        let ns = line as NSString
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return line }
        let value = parse(ns.substring(with: m.range(at: 2)))
        let upper = m.range(at: 4).location == NSNotFound ? nil : parse(ns.substring(with: m.range(at: 4)))
        guard value.isFinite, upper?.isFinite ?? true else { return line }
        let rest = ns.substring(from: m.range.upperBound)
        let amount = format(value * factor) + (upper.map { ns.substring(with: m.range(at: 3)) + format($0 * factor) } ?? "")
        return ns.substring(with: m.range(at: 1)) + amount + (rest.isEmpty ? "" : " " + rest)
    }

    /// `parseNum`: "1 1/2", "1/2", "1,000", "1.5" or "1,5", "1½" or "1 ½", "½".
    static func parse(_ raw: String) -> Double {
        let num = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if num.count == 1, let glyph = num.first, let value = glyphs[glyph] { return value }
        if let last = num.last, let value = glyphs[last] {
            let whole = num.dropLast().trimmingCharacters(in: .whitespaces)
            if !whole.isEmpty, whole.allSatisfy(\.isASCIIDigit) { return leadingInteger(whole) + value }
        }
        if num.contains("/") {
            let parts = num.split(whereSeparator: \.isWhitespace)
            if parts.count == 2 {
                let fraction = parts[1].split(separator: "/", omittingEmptySubsequences: false)
                return leadingInteger(parts[0]) + leadingInteger(fraction[0]) / leadingInteger(fraction.count > 1 ? fraction[1] : "")
            }
            let fraction = num.split(separator: "/", omittingEmptySubsequences: false)
            return leadingInteger(fraction[0]) / leadingInteger(fraction.count > 1 ? fraction[1] : "")
        }
        // Thousands: "1,000" is 1000, "1,000.5" is 1000.5.
        if let thousands = quantity.thousands,
           thousands.firstMatch(in: num, range: NSRange(num.startIndex..., in: num)) != nil {
            return Double(num.replacingOccurrences(of: ",", with: "")) ?? .nan
        }
        // parseFloat after replacing the first comma: "1,5" is 1.5.
        var decimal = num
        if let comma = decimal.firstIndex(of: ",") { decimal.replaceSubrange(comma...comma, with: ".") }
        return Double(decimal) ?? .nan
    }

    /// `fmtFrac`: whole numbers plainly, ¼ ⅓ ½ ⅔ ¾ when within 0.05, otherwise two decimal places.
    static func format(_ n: Double) -> String {
        let whole = n.rounded(.down), fraction = n - whole
        if fraction < 0.05 { return whole != 0 ? number(whole) : number(jsRound(n * 100) / 100) }
        for (value, glyph) in glyphsOut where abs(fraction - value) < 0.05 {
            return (whole != 0 ? number(whole) + " " : "") + glyph
        }
        return number(jsRound(n * 100) / 100)
    }

    /// `parseInt` on a run of ASCII digits (NaN when there are none). Kept as a Double so long numbers can't overflow.
    private static func leadingInteger(_ s: some StringProtocol) -> Double {
        Double(String(s.prefix(while: \.isASCIIDigit))) ?? .nan
    }

    /// `Math.round`: halves go up.
    private static func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

    /// JavaScript's `String(number)` for the values `format` produces: "2", "0.06", "2.1".
    private static func number(_ x: Double) -> String {
        if x == x.rounded(), abs(x) < 1e15 { return String(Int(x)) }
        return String(x)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
