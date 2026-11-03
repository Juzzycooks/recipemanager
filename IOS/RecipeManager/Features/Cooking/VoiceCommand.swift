import Foundation

/// What the cook can say in hands-free cook mode. `parse(_:)` is pure (no Speech framework), so the whole grammar is
/// unit tested; `HandsFreeController` feeds it one utterance at a time (the words since the last pause or command).
enum VoiceCommand: Equatable, Sendable {
    case next
    case back
    /// Read the current step aloud.
    case repeatStep
    /// Read this step's ingredients (or all of them).
    case ingredients
    /// "how much butter" → `howMuch("butter")`.
    case howMuch(String)
    case setTimer(seconds: Int)
    /// Start the timer the current step mentions ("simmer for 20 minutes").
    case startStepTimer
    case stopListening

    /// The short caption shown when a command is heard, so the cook knows it registered.
    var caption: String {
        switch self {
        case .next: "Next step"
        case .back: "Previous step"
        case .repeatStep: "Reading the step"
        case .ingredients: "Ingredients"
        case .howMuch(let name): "How much \(name)"
        case .setTimer(let seconds): "Timer for \(Self.spokenDuration(seconds))"
        case .startStepTimer: "Step timer"
        case .stopListening: "Stopped listening"
        }
    }

    // MARK: Parsing

    /// Lower case, apostrophes dropped ("what's" → "whats"), every other non-letter, non-digit except `.`, `/` and the
    /// fraction glyphs turned into a space, then split into words.
    static func words(_ text: String) -> [String] {
        var cleaned = ""
        for ch in text.lowercased() {
            if ch == "'" || ch == "’" { continue }
            if ch.isLetter || ch.isNumber || ch == "." || ch == "/" { cleaned.append(ch) } else { cleaned.append(" ") }
        }
        // A sentence-ending full stop ("Next.") is punctuation; "1.5" is a number.
        return cleaned.split(separator: " ").map { word in
            var w = String(word)
            while w.hasSuffix(".") || w.hasSuffix("/") { w.removeLast() }
            while w.hasPrefix(".") && !(w.dropFirst().first?.isNumber ?? false) { w.removeFirst() }
            return w
        }.filter { !$0.isEmpty }
    }

    private static let leadingFillers: Set<String> = ["ok", "okay", "hey", "um", "umm", "uh", "er", "erm", "so", "and", "now", "alright",
                                                      "right", "spoonmate", "then", "oh", "please", "well", "yeah", "yes"]
    private static let trailingFillers: Set<String> = ["please", "now", "thanks", "again"]

    private static func trimmed(_ words: [String]) -> [String] {
        var w = ArraySlice(words)
        while let first = w.first, leadingFillers.contains(first) { w.removeFirst() }
        while true {
            if let last = w.last, trailingFillers.contains(last) { w.removeLast(); continue }
            if w.count >= 2, w.suffix(2).elementsEqual(["thank", "you"]) { w.removeLast(2); continue }
            break
        }
        return Array(w)
    }

    private static let phrases: [String: VoiceCommand] = {
        var map: [String: VoiceCommand] = [:]
        func add(_ command: VoiceCommand, _ list: [String]) { for p in list { map[p] = command } }
        add(.next, ["next", "next step", "next one", "continue", "go next", "go on", "move on", "go forward", "forward",
                    "go to the next step", "on to the next step", "onto the next step", "whats next", "what is next"])
        add(.back, ["back", "go back", "previous", "previous step", "step back", "back one", "go back one", "back a step",
                    "go back a step", "go to the previous step", "the previous step"])
        add(.repeatStep, ["repeat", "repeat that", "repeat it", "repeat the step", "repeat step", "repeat this step", "read it",
                          "read it out", "read that", "read the step", "read step", "read this step", "read me the step",
                          "whats the step", "what is the step", "whats this step", "what is this step", "whats the current step",
                          "say that", "say it", "come again", "pardon", "what was that"])
        add(.ingredients, ["ingredients", "the ingredients", "read the ingredients", "read ingredients", "list the ingredients",
                           "what ingredients", "which ingredients", "what do i need", "what do we need", "what do i need for this step",
                           "what do we need for this step", "what do i need here", "what goes in", "what goes in this step",
                           "ingredients for this step", "what ingredients do i need", "how much do i need", "how much of everything"])
        add(.stopListening, ["stop listening", "stop hands free", "turn off hands free", "hands free off", "stop voice",
                             "stop voice control", "turn off voice", "turn off voice control", "stop listening to me"])
        add(.startStepTimer, ["start the timer", "start timer", "start a timer", "start this timer", "start the step timer",
                              "start the steps timer", "start step timer", "start that timer", "timer start", "begin the timer",
                              "start the timer for this step"])
        return map
    }()

    /// One utterance → a command, or nil when it isn't one (ordinary kitchen talk). The whole utterance must be the
    /// command (fillers like "okay" and "please" aside), so "we'll do that next" doesn't turn the page.
    static func parse(_ utterance: String) -> VoiceCommand? {
        let w = trimmed(words(utterance))
        guard !w.isEmpty else { return nil }
        if let command = phrases[w.joined(separator: " ")] { return command }
        if let command = howMuch(w) { return command }
        if let command = timer(w) { return command }
        return nil
    }

    /// True when the utterance is the start of a command that is probably still being said ("set a timer for…",
    /// "how much"), so the controller waits for more instead of treating the pause as the end.
    static func isIncomplete(_ utterance: String) -> Bool {
        let w = trimmed(words(utterance))
        guard let last = w.last else { return false }
        if ["for", "much", "many", "of", "a", "an", "and", "timer"].contains(last) { return w.contains("timer") || w.contains("how") }
        return false
    }

    private static func howMuch(_ w: [String]) -> VoiceCommand? {
        guard w.count >= 2, w[0] == "how", w[1] == "much" || w[1] == "many" else { return nil }
        var rest = Array(w.dropFirst(2))
        let tails: [[String]] = [["do", "i", "need"], ["do", "we", "need"], ["do", "i", "use"], ["do", "we", "use"], ["is", "it"],
                                 ["goes", "in"], ["go", "in"], ["is", "there"], ["in", "this", "step"], ["for", "this", "step"],
                                 ["for", "this"], ["in", "it"], ["do", "i", "add"], ["do", "we", "add"], ["do", "i", "put", "in"]]
        var changed = true
        while changed {
            changed = false
            for tail in tails where rest.count > tail.count && rest.suffix(tail.count).elementsEqual(tail) {
                rest.removeLast(tail.count); changed = true
            }
        }
        while let first = rest.first, ["of", "the", "is", "are", "do", "does"].contains(first) { rest.removeFirst() }
        guard !rest.isEmpty else { return .ingredients }   // "how much do I need"
        return .howMuch(rest.joined(separator: " "))
    }

    private static let timerLeadIn: Set<String> = ["set", "start", "make", "put", "add", "begin", "can", "could", "would", "you", "me",
                                                   "i", "want", "need", "a", "an", "the", "new", "another", "on", "us", "up", "for"]

    private static func timer(_ w: [String]) -> VoiceCommand? {
        guard let t = w.firstIndex(where: { $0 == "timer" || $0 == "timers" }) else { return nil }
        var before = ArraySlice(w[..<t])
        while let first = before.first, timerLeadIn.contains(first) { before.removeFirst() }
        var after = ArraySlice(w[(t + 1)...])
        while let first = after.first, first == "for" || first == "of" || first == "to" { after.removeFirst() }
        if !before.isEmpty {
            // "set a ten minute timer"
            guard after.isEmpty, let seconds = duration(Array(before)) else { return nil }
            return .setTimer(seconds: seconds)
        }
        if !after.isEmpty {
            // "set a timer for an hour and a half"
            guard let seconds = duration(Array(after)) else { return nil }
            return .setTimer(seconds: seconds)
        }
        return nil   // "set a timer" with no time: wait for more (see isIncomplete); "start the timer" is a phrase above
    }

    // MARK: Durations

    private static let unitSeconds: [String: Double] = [
        "second": 1, "seconds": 1, "sec": 1, "secs": 1,
        "minute": 60, "minutes": 60, "min": 60, "mins": 60,
        "hour": 3600, "hours": 3600, "hr": 3600, "hrs": 3600,
    ]
    private static let ones: [String: Double] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
        "nineteen": 19,
    ]
    private static let tens: [String: Double] = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70,
                                                 "eighty": 80, "ninety": 90]
    private static let glyphs: [Character: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3]

    /// A number written in digits ("10", "1.5", "1/2", "1½") or one word ("ten", "a", "half").
    private static func simpleNumber(_ word: String) -> Double? {
        if let v = ones[word] ?? tens[word] { return v }
        if let v = Double(word) { return v }
        if let last = word.last, let fraction = glyphs[last] {
            let head = word.dropLast()
            if head.isEmpty { return fraction }
            return Double(head).map { $0 + fraction }
        }
        let parts = word.split(separator: "/")
        if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 { return a / b }
        return nil
    }

    /// Reads a number phrase at `i`: "twenty five", "one and a half", "half a", "a quarter of an", "three quarters of a",
    /// "a couple of". Returns the value and how many words it used.
    private static func number(_ w: [String], at i: Int) -> (Double, Int)? {
        func word(_ k: Int) -> String? { w.indices.contains(k) ? w[k] : nil }
        var j = i
        var value: Double
        switch word(j) {
        case "half"?:
            value = 0.5; j += 1
            if word(j) == "of" { j += 1 }
            if word(j) == "a" || word(j) == "an" { j += 1 }        // "half an hour"
            return (value, j - i)
        case "quarter"?:
            value = 0.25; j += 1
            if word(j) == "of" { j += 1 }
            if word(j) == "a" || word(j) == "an" { j += 1 }        // "quarter of an hour"
            return (value, j - i)
        case "a"?, "an"?:
            if word(j + 1) == "half" || word(j + 1) == "quarter" { return number(w, at: j + 1).map { ($0.0, $0.1 + 1) } }
            if word(j + 1) == "couple" { j += 2; if word(j) == "of" { j += 1 }; return (2, j - i) }
            value = 1; j += 1
        case "couple"?:
            j += 1; if word(j) == "of" { j += 1 }
            return (2, j - i)
        case let x? where tens[x] != nil:
            value = tens[x]!; j += 1
            if let next = word(j), let one = ones[next], one > 0, one < 10 { value += one; j += 1 }   // "twenty five"
        case let x? where simpleNumber(x) != nil:
            value = simpleNumber(x)!; j += 1
        default:
            return nil
        }
        // "three quarters (of an)"
        if word(j) == "quarters" {
            value *= 0.25; j += 1
            if word(j) == "of" { j += 1 }
            if word(j) == "a" || word(j) == "an" { j += 1 }
            return (value, j - i)
        }
        // "one and a half", "two and a quarter", "1 and 3 quarters"
        if word(j) == "and", let (fraction, used) = number(w, at: j + 1), fraction < 1, fraction > 0 {
            let after = word(j + 1 + used)
            if after == nil || unitSeconds[after!] != nil { return (value + fraction, j + 1 + used - i) }
        }
        return (value, j - i)
    }

    /// "ten minutes", "an hour and a half", "half an hour", "1 hour 20", "90 seconds", "1.5 hours" → seconds.
    /// A bare number is minutes. Nil for nothing sensible (zero, or more than ten hours).
    static func duration(_ w: [String]) -> Int? {
        var total = 0.0
        var pending: Double?
        var lastUnit: Double?
        var i = 0
        var understood = false
        while i < w.count {
            let word = w[i]
            if let unit = unitSeconds[word] {
                total += (pending ?? 1) * unit
                lastUnit = unit; pending = nil; understood = true
                i += 1
            } else if word == "and" || word == "of" || word == "for" {
                i += 1
            } else if let (value, used) = number(w, at: i) {
                if let p = pending, value < 1 { pending = p + value } else if pending != nil, let unit = lastUnit {
                    total += pending! * smaller(than: unit); pending = value
                } else { pending = value }
                i += used
            } else {
                i += 1   // a word we don't know ("timer", "please")
            }
        }
        if let p = pending {
            if let unit = lastUnit {
                // "an hour and a half" (a fraction of the last unit), "an hour twenty" (the next unit down)
                total += p < 1 ? p * unit : p * smaller(than: unit)
            } else {
                total += p * 60    // "set a timer for ten": minutes
            }
            understood = true
        }
        let seconds = Int(total.rounded())
        guard understood, seconds > 0, seconds <= 10 * 3600 else { return nil }
        return seconds
    }

    private static func smaller(than unit: Double) -> Double { unit >= 3600 ? 60 : 1 }

    /// 600 → "10 minutes", 5400 → "1 hour 30 minutes", 90 → "1 minute 30 seconds".
    static func spokenDuration(_ seconds: Int) -> String {
        func part(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s")" }
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return [h > 0 ? part(h, "hour") : nil, m > 0 ? part(m, "minute") : nil, s > 0 ? part(s, "second") : nil]
            .compactMap { $0 }.joined(separator: " ")
    }

    // MARK: Answers

    private static func stem(_ word: String) -> String {
        if word.count > 4, word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.count > 4, ["oes", "ches", "shes", "sses", "xes"].contains(where: word.hasSuffix) { return String(word.dropLast(2)) }
        if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
        return word
    }
    private static let ignored: Set<String> = ["the", "a", "an", "of", "some", "my", "for", "in", "to", "and"]

    /// The ingredient lines that name everything the cook asked about ("how much brown sugar" → "100 g brown sugar").
    /// When no line has every word, the lines with the most of them. At most three lines.
    static func lines(matching query: String, in lines: [String]) -> [String] {
        let wanted = Set(words(query).filter { !ignored.contains($0) }.map(stem))
        guard !wanted.isEmpty else { return [] }
        let scored = lines.map { line in (line, wanted.intersection(Set(words(line).map(stem))).count) }
        let best = scored.map(\.1).max() ?? 0
        guard best > 0 else { return [] }
        if best < wanted.count, wanted.count > 1, best * 2 < wanted.count { return [] }   // matched too little to trust
        return Array(scored.filter { $0.1 == best }.map(\.0).prefix(3))
    }

    private static let spokenUnits: [String: String] = [
        "g": "grams", "kg": "kilograms", "mg": "milligrams", "ml": "millilitres", "l": "litres", "tbsp": "tablespoons",
        "tbs": "tablespoons", "tsp": "teaspoons", "oz": "ounces", "lb": "pounds", "lbs": "pounds", "cm": "centimetres",
        "mm": "millimetres", "min": "minutes", "mins": "minutes", "hr": "hours", "hrs": "hours", "°c": "degrees Celsius",
        "°f": "degrees Fahrenheit", "c": "degrees Celsius", "f": "degrees Fahrenheit",
    ]
    private static let spokenGlyphs: [Character: (alone: String, after: String)] = [
        "½": ("half", "and a half"), "¼": ("a quarter", "and a quarter"), "¾": ("three quarters", "and three quarters"),
        "⅓": ("a third", "and a third"), "⅔": ("two thirds", "and two thirds"), "⅛": ("an eighth", "and an eighth"),
    ]

    /// Text as it should be read aloud: "1 ½ cups" → "1 and a half cups", "250 g" → "250 grams", "180°C" → "180 degrees Celsius".
    static func spoken(_ text: String) -> String {
        var out = ""
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            if let glyph = spokenGlyphs[ch] {
                let prev = out.last(where: { $0 != " " })
                let afterNumber = prev?.isNumber == true
                if !out.isEmpty, out.last != " " { out.append(" ") }
                out += afterNumber ? glyph.after : glyph.alone
                if i + 1 < chars.count, chars[i + 1] != " " { out.append(" ") }
            } else {
                out.append(ch)
            }
        }
        // A unit right after a number: "250 g", "250g", "180°C", "180 °C".
        let pattern = #"(\d|half|quarter|third|thirds|eighth)\s*(°\s*[cCfF]|[A-Za-z]+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return out }
        let ns = out as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
            let unitRange = match.range(at: 2)
            let raw = ns.substring(with: unitRange)
            let key = raw.replacingOccurrences(of: " ", with: "").lowercased()
            // Bare "c"/"f" only count as temperatures when written with a degree sign.
            guard let word = spokenUnits[key], key.count > 1 || raw.hasPrefix("°") || key == "g" || key == "l" else { continue }
            result += ns.substring(with: NSRange(location: last, length: match.range(at: 1).upperBound - last))
            result += " " + word
            last = unitRange.upperBound
        }
        result += ns.substring(from: last)
        return result
    }
}
