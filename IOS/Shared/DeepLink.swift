import Foundation

/// `spoonmate://` links the widgets (and anything else) use to open a place in the app.
enum DeepLink: Equatable, Sendable {
    case recipe(Int)
    case cook(Int)
    case plan
    case shopping

    static let scheme = "spoonmate"

    /// `spoonmate://recipe/12`, `spoonmate://cook/12`, `spoonmate://plan`, `spoonmate://shop`. Nil for anything else.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        // The first part is the host ("recipe" in spoonmate://recipe/12); tolerate spoonmate:///recipe/12 too.
        let parts = ([url.host() ?? ""] + url.pathComponents).filter { !$0.isEmpty && $0 != "/" }.map { $0.lowercased() }
        guard let head = parts.first else { return nil }
        let id = parts.count == 2 ? Int(parts[1]) : nil
        switch head {
        case "recipe": guard let id, id > 0 else { return nil }; self = .recipe(id)
        case "cook": guard let id, id > 0 else { return nil }; self = .cook(id)
        case "plan" where parts.count == 1: self = .plan
        case "shop" where parts.count == 1, "shopping" where parts.count == 1: self = .shopping
        default: return nil
        }
    }

    var url: URL {
        switch self {
        case .recipe(let id): URL(string: "\(Self.scheme)://recipe/\(id)")!
        case .cook(let id): URL(string: "\(Self.scheme)://cook/\(id)")!
        case .plan: URL(string: "\(Self.scheme)://plan")!
        case .shopping: URL(string: "\(Self.scheme)://shop")!
        }
    }
}
