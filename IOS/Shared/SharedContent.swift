import Foundation

/// What was shared to the "Save to Spoonmate" extension.
enum SharedSource: Equatable, Sendable {
    case link(URL)
    case text(String)
}

enum SharedContent {
    /// A web link found in the shared pieces of text if any; otherwise long text counts as a pasted recipe.
    /// (Instagram and TikTok share a caption with a link inside it.)
    static func source(fromText texts: [String]) -> SharedSource? {
        for text in texts { if let url = firstWebLink(in: text) { return .link(url) } }
        let longest = texts.max { $0.count < $1.count } ?? ""
        return longest.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 ? .text(longest) : nil
    }

    static func firstWebLink(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.matches(in: text, range: range).compactMap(\.url).first { $0.scheme == "http" || $0.scheme == "https" }
    }
}
