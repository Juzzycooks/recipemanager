import CryptoKit
import Foundation
import UIKit

/// Everything saved for offline use: GET responses, plus a full local copy of the recipe library so lists,
/// search, filters and recipe pages keep working with no connection. Files live in Application Support
/// (not the Caches folder, which iOS may empty at any time) and are excluded from backups.
actor OfflineStore: ResponseCaching {
    static let shared = OfflineStore()

    private let directory: URL
    private var library: [Int: RecipeDetail]?

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var dir = base.appendingPathComponent("Offline", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        directory = dir
    }

    // MARK: ResponseCaching

    func store(_ data: Data, for url: URL) {
        try? data.write(to: file(for: url), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // Keep the library fresh whenever a recipe is fetched normally.
        if Self.recipeID(in: url.path) != nil, let detail = try? APIClient.decoder.decode(RecipeDetail.self, from: data) {
            upsert(detail)
        }
    }

    func cached(for url: URL) -> Data? { try? Data(contentsOf: file(for: url)) }

    func generated(path: String, query: [String: String]) -> Data? {
        loadLibrary()
        guard let library, !library.isEmpty else { return nil }
        if path == "/recipes" { return list(library.values.map { $0 }, query: query) }
        if let id = Self.recipeID(in: path), let recipe = library[id] { return try? APIClient.encoder.encode(recipe) }
        return nil
    }

    func reachability(_ reachable: Bool) async {
        await MainActor.run { Connectivity.shared.setReachable(reachable) }
    }

    // MARK: Library

    func allRecipes() -> [RecipeDetail] {
        loadLibrary()
        return Array((library ?? [:]).values)
    }

    var recipeCount: Int { loadLibrary(); return library?.count ?? 0 }

    func upsert(_ recipe: RecipeDetail) {
        loadLibrary()
        library?[recipe.id] = recipe
        saveLibrary()
    }

    func remove(ids: [Int]) {
        loadLibrary()
        for id in ids { library?[id] = nil }
        saveLibrary()
    }

    /// Reflects a change made while offline in the local copy, so lists and pages show it straight away.
    func apply(_ op: OutboxOp) {
        loadLibrary()
        switch op {
        case .favorite(let id, let wanted): library?[id]?.isFavorite = wanted
        case .rate(let id, let score): library?[id]?.myRating = score
        case .madeIt(let id):
            library?[id]?.madeCount += 1
            library?[id]?.lastMade = .now
        default: return
        }
        saveLibrary()
    }

    func clear() {
        library = [:]
        memoryClear()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func byteCount() -> Int {
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return walker.compactMap { (try? ($0 as? URL)?.resourceValues(forKeys: [.fileSizeKey]))?.fileSize }.reduce(0, +)
    }

    private func memoryClear() { Task { await ImageStore.shared.clearMemory() } }

    // MARK: Internals

    private var libraryFile: URL { directory.appendingPathComponent("library.json") }

    private func loadLibrary() {
        guard library == nil else { return }
        if let data = try? Data(contentsOf: libraryFile), let list = try? APIClient.decoder.decode([RecipeDetail].self, from: data) {
            library = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        } else {
            library = [:]
        }
    }

    private func saveLibrary() {
        guard let library, let data = try? APIClient.encoder.encode(Array(library.values)) else { return }
        try? data.write(to: libraryFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func file(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".json")
    }

    /// 7 from "/recipes/7" or "/api/v1/recipes/7"; nil for "/recipes", "/recipes/7/comments", "/recipes/random".
    nonisolated static func recipeID(in path: String) -> Int? {
        let parts = path.split(separator: "/")
        guard let i = parts.lastIndex(of: "recipes"), parts.index(after: i) == parts.index(before: parts.endIndex),
              let id = Int(parts[parts.index(after: i)]) else { return nil }
        return id
    }

    /// The recipe list endpoint, answered locally: same filters, sorting and paging as the server.
    private func list(_ recipes: [RecipeDetail], query: [String: String]) -> Data? {
        var items = recipes
        if let q = query["q"]?.trimmingCharacters(in: .whitespaces), !q.isEmpty {
            items = items.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.ingredients.localizedCaseInsensitiveContains(q) }
        }
        if let ingredient = query["ingredient"], !ingredient.isEmpty {
            items = items.filter { $0.ingredients.localizedCaseInsensitiveContains(ingredient) }
        }
        if let cat = query["cat"].flatMap(Int.init) { items = items.filter { $0.categories.contains { $0.id == cat } } }
        if let coll = query["collection"].flatMap(Int.init) { items = items.filter { $0.collections.contains { $0.id == coll } } }
        if query["favorites"] == "1" || query["favorites"] == "true" { items = items.filter(\.isFavorite) }
        switch query["sort"] {
        case "oldest": items.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        case "title_az": items.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case "title_za": items.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        default: items.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        }
        let perPage = min(max(query["per_page"].flatMap(Int.init) ?? 24, 1), 100)
        let page = max(query["page"].flatMap(Int.init) ?? 1, 1)
        let pages = max(1, Int((Double(items.count) / Double(perPage)).rounded(.up)))
        let slice = items.dropFirst((page - 1) * perPage).prefix(perPage).map { RecipeSummary($0) }
        guard let encoded = try? APIClient.encoder.encode(Array(slice)),
              let object = try? JSONSerialization.jsonObject(with: encoded) else { return nil }
        let body: [String: Any] = ["items": object, "page": page, "per_page": perPage, "total": items.count, "pages": pages]
        return try? JSONSerialization.data(withJSONObject: body)
    }
}

/// Pictures kept on disk next to the offline library (Application Support, so iOS never empties them the way it can
/// the URL cache). A picture is downloaded once; `OfflineStore.clear()` removes the folder with everything else.
actor ImageStore {
    static let shared = ImageStore()

    private let directory: URL
    nonisolated(unsafe) private let memory = NSCache<NSURL, UIImage>()

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Offline/Images", isDirectory: true)
        memory.totalCostLimit = 64 << 20
    }

    nonisolated func cachedImage(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    func has(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: file(for: url).path) }

    /// The picture from disk, downloading and saving it first if this is the first time.
    func image(_ url: URL) async -> UIImage? {
        if let hit = memory.object(forKey: url as NSURL) { return hit }
        let path = file(for: url)
        var data = try? Data(contentsOf: path)
        if data == nil {
            guard let (fetched, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200, UIImage(data: fetched) != nil else { return nil }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? fetched.write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            data = fetched
        }
        guard let data, let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: url as NSURL, cost: data.count)
        return image
    }

    /// Downloads to disk without decoding (used by the offline sync).
    func prefetch(_ url: URL) async {
        guard !has(url) else { return }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file(for: url), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func clearMemory() { memory.removeAllObjects() }

    private func file(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest)
    }
}
