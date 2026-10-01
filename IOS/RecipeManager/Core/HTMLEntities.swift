import Foundation

/// Imported recipes sometimes carry HTML entities (`&quot;`, `&#39;`, `&nbsp;`) in their text. The server stores
/// them as it received them, so the app cleans every API response before decoding it.
enum HTMLEntities {
    private static let pattern = try! NSRegularExpression(pattern: "&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[A-Za-z0-9]{2,8});")
    private static let named: [String: String] = [
        "amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">", "nbsp": " ", "ndash": "–", "mdash": "—",
        "hellip": "…", "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "deg": "°", "frac12": "½",
        "frac14": "¼", "frac34": "¾", "eacute": "é", "egrave": "è", "agrave": "à", "ccedil": "ç", "ouml": "ö",
        "uuml": "ü", "auml": "ä", "ntilde": "ñ", "times": "×",
    ]

    /// Replaces known entities; anything unrecognised is left as written.
    static func decode(_ text: String) -> String {
        guard text.contains("&"), text.contains(";") else { return text }
        let ns = text as NSString
        var out = "", last = 0
        for m in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1))
            var replacement: String?
            if name.hasPrefix("#") {
                let hex = name.dropFirst().first == "x" || name.dropFirst().first == "X"
                let digits = name.dropFirst(hex ? 2 : 1)
                if let code = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                    replacement = code == 0xA0 ? " " : String(Character(scalar))
                }
            } else { replacement = named[name] ?? named[name.lowercased()] }
            guard let replacement else { continue }
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last)) + replacement
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }

    /// Cleans every string in a JSON response. Bodies without entities come back untouched (and unparsed).
    static func clean(_ data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8), text.contains("&"),
              pattern.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil,
              let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let cleaned = try? JSONSerialization.data(withJSONObject: walk(json), options: [.fragmentsAllowed])
        else { return data }
        return cleaned
    }

    private static func walk(_ value: Any) -> Any {
        switch value {
        case let s as String: return decode(s)
        case let a as [Any]: return a.map(walk)
        case let d as [String: Any]: return d.mapValues(walk)
        default: return value
        }
    }
}
