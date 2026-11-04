import Foundation

/// A time a recipe step mentions. A port of `findDurations` in static/js/cook.js: keep the two in step (same cases in
/// `CookAndExportTests.swift` and `tests/test_cook.js`).
///
/// The web works in fractional minutes ("30 seconds" is 0.5); here the time is kept in whole seconds, which is what a
/// timer starts with, and `minutes` is that rounded for display and older callers.
struct StepDuration: Equatable, Sendable {
    /// What the timer starts at: the low end of a range.
    let seconds: Int
    /// The high end of a range ("2–3 hours" → 10 800); equal to `seconds` for a single time.
    let maxSeconds: Int
    /// The words it came from, as written ("2–3 hours", "1 hr, 15 min", "overnight", "until doubled in size").
    let text: String
    /// True for a rough time ("overnight", "until doubled"), false for a stated one.
    let approx: Bool

    init(seconds: Int, maxSeconds: Int, text: String, approx: Bool = false) {
        self.seconds = seconds; self.maxSeconds = max(seconds, maxSeconds); self.text = text; self.approx = approx
    }

    init(minutes: Int, maxMinutes: Int, text: String, approx: Bool = false) {
        self.init(seconds: minutes * 60, maxSeconds: maxMinutes * 60, text: text, approx: approx)
    }

    /// The start time in whole minutes (rounded; "30 seconds" is 1). Prefer `seconds` for starting a timer.
    var minutes: Int { Self.wholeMinutes(seconds) }
    var maxMinutes: Int { Self.wholeMinutes(maxSeconds) }

    var isRange: Bool { maxSeconds > seconds }
    /// How much a finished timer can be extended by to reach the top of the range, in whole minutes.
    var extraMinutes: Int { max(0, Self.wholeMinutes(maxSeconds - seconds)) }

    /// "Overnight · about 8 hr" for a rough time; "2 hr", "45 sec" or "2 hr–3 hr" for a stated one.
    var label: String {
        if approx {
            let words = text.prefix(1).uppercased() + text.dropFirst()
            return "\(words) · about \(TimerSheet.format(seconds: seconds))"
        }
        return isRange ? "\(TimerSheet.format(seconds: seconds))–\(TimerSheet.format(seconds: maxSeconds))" : TimerSheet.format(seconds: seconds)
    }

    private static func wholeMinutes(_ seconds: Int) -> Int { Int((Double(seconds) / 60).rounded()) }
}

enum StepDurations {
    /// The longest time a step can start a timer for (72 hours, as on the web).
    static let maxSeconds = 72 * 60 * 60

    // The web's DURATION_RE, unchanged: "a/an/one hour", or a number (decimal with . or ,, "1/2", "1 1/2", "1½", "½"),
    // optionally a range ("2-3", "2–3", "2 to 3"), then a unit (hours, minutes or seconds, "30-second" too).
    private static let number = #"(?:\d+\s+\d/\d|\d+/\d+|\d+(?:[.,]\d+)?[½¼¾]?|[½¼¾])"#
    private static let unitWords = "hours?|hrs?|minutes?|mins?|seconds?|secs?"
    private static let duration = try! NSRegularExpression(
        pattern: #"(?:\b(?:an?|one)\s+(?:"# + unitWords + #")\b)|("# + number + #")(?:\s*(?:-|–|—|to)\s*("# + number
            + #"))?[\s-]*("# + unitWords + #")\b"#,
        options: .caseInsensitive)
    private static let unitOnly = try! NSRegularExpression(pattern: "(" + unitWords + ")", options: .caseInsensitive)
    private static let overnight = try! NSRegularExpression(pattern: #"\bovernight\b"#, options: .caseInsensitive)
    private static let doubled = try! NSRegularExpression(
        pattern: #"until\s+(?:it\s+)?(?:has\s+)?doubled?s?(?:\s+in\s+(?:size|bulk))?"#, options: .caseInsensitive)

    private static let fractions: [Character: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75]

    /// The web's parseNum: "1,5" and "1.5" → 1.5, "1/2" → 0.5, "1 1/2" → 1.5, "1½" → 1.5, "½" → 0.5. Nil if not a number.
    static func parseNumber(_ raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let comma = s.firstIndex(of: ",") { s.replaceSubrange(comma...comma, with: ".") }   // the first comma, as JS replace does
        func groups(_ pattern: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
            return (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: s).map { String(s[$0]) } ?? "" }
        }
        if let g = groups(#"^(\d+)\s+(\d)/(\d)$"#), let whole = Double(g[0]), let a = Double(g[1]), let b = Double(g[2]) {
            return whole + a / b
        }
        if let g = groups(#"^(\d)/(\d)$"#), let a = Double(g[0]), let b = Double(g[1]) { return a / b }
        if let g = groups(#"^(\d+(?:\.\d+)?)([½¼¾])$"#), let whole = Double(g[0]), let f = g[1].first.flatMap({ fractions[$0] }) {
            return whole + f
        }
        if s.count == 1, let f = s.first.flatMap({ fractions[$0] }) { return f }
        // parseFloat: the leading number, ignoring whatever follows ("10/12" → 10).
        if let g = groups(#"^(\d+(?:\.\d+)?)"#) { return Double(g[0]) }
        return nil
    }

    /// Seconds in one of the unit: hours, minutes or seconds by the first letter.
    private static func unitSeconds(_ unit: String) -> Double {
        switch unit.lowercased().first {
        case "h": 3600
        case "m": 60
        default: 1
        }
    }

    /// Hours outrank minutes outrank seconds; only a smaller unit joins onto the time before it.
    private static func unitRank(_ unit: String) -> Int {
        switch unit.lowercased().first {
        case "h": 3
        case "m": 2
        default: 1
        }
    }

    /// Words between two times that make them one ("1 hour and 30 minutes", "1 hr, 15 min", "1 hour 30 minutes").
    private static let joiners: Set<String> = ["", "and", ",", "&"]

    private struct Found {
        var low: Double      // seconds
        var high: Double
        var start: Int       // UTF-16 offsets, like JS string indexes
        var end: Int
        var rank: Int
        var text: String
        var approx = false
    }

    /// Every time the step mentions, in the order they appear. "Until doubled" counts only when no stated time does.
    static func find(in text: String) -> [StepDuration] {
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        func group(_ match: NSTextCheckingResult, _ i: Int) -> String? {
            let r = match.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }

        var found: [Found] = []
        for match in duration.matches(in: text, range: whole) {
            let matched = ns.substring(with: match.range)
            let unit: String, low: Double, high: Double
            if let first = group(match, 1), let unitText = group(match, 3) {
                guard let lo = parseNumber(first) else { continue }
                unit = unitText
                low = lo
                high = group(match, 2).flatMap(parseNumber) ?? lo
            } else {
                // "an hour", "a minute", "one hour"
                guard let u = unitOnly.firstMatch(in: matched, range: NSRange(location: 0, length: (matched as NSString).length)) else { continue }
                unit = (matched as NSString).substring(with: u.range)
                low = 1; high = 1
            }
            guard low.isFinite, high.isFinite, low > 0 else { continue }
            let end = match.range.location + match.range.length
            if var prev = found.last {
                let gap = ns.substring(with: NSRange(location: prev.end, length: match.range.location - prev.end))
                    .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if joiners.contains(gap), unitRank(unit) < prev.rank {
                    prev.low += low * unitSeconds(unit)
                    prev.high = prev.low
                    prev.end = end
                    prev.rank = unitRank(unit)
                    prev.text = ns.substring(with: NSRange(location: prev.start, length: end - prev.start))
                    found[found.count - 1] = prev
                    continue
                }
            }
            found.append(Found(low: low * unitSeconds(unit), high: high * unitSeconds(unit), start: match.range.location, end: end,
                               rank: unitRank(unit), text: matched.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        found = found.filter { $0.low > 0 && $0.low <= Double(maxSeconds) }

        // Rough waits with no number: "overnight" is 8–12 hours. "Until doubled" is about 1–1½ hours, but only when the
        // step gives no proper time of its own ("rise 1-2 hours until doubled").
        let plain = found.count
        for match in overnight.matches(in: text, range: whole) {
            found.append(Found(low: 480 * 60, high: 720 * 60, start: match.range.location, end: 0, rank: 0,
                               text: ns.substring(with: match.range), approx: true))
        }
        if plain == 0, let match = doubled.firstMatch(in: text, range: whole) {
            found.append(Found(low: 60 * 60, high: 90 * 60, start: match.range.location, end: 0, rank: 0,
                               text: ns.substring(with: match.range), approx: true))
        }
        // A stable sort, as JS's is, so equal starts keep their order.
        return found.enumerated().sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }.map { item in
            let d = item.element
            return StepDuration(seconds: Int(d.low.rounded()), maxSeconds: Int(d.high.rounded()), text: d.text, approx: d.approx)
        }
    }
}
