import CryptoKit
import Foundation

/// The App Group the app and the widget extension share. The app writes small JSON snapshots of today's plan and the
/// shopping list there whenever they sync or change; the widgets read them (and refresh them from the server when they can).
enum AppGroup {
    static let identifier = "group.com.justinrahme.Spoonmate"

    /// Nil when the entitlement is missing (an unsigned build): every snapshot read and write is then a no-op.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

/// Widget kinds, so the app can reload exactly the widget whose data changed.
enum WidgetKind {
    static let tonight = "TonightDinner"
    static let shopping = "ShoppingList"
    static let week = "WeekPlan"
    static let randomRecipe = "RandomRecipe"
}

/// Meal order within a day, as the meal plan shows it.
enum MealOrder {
    static let all = ["breakfast", "lunch", "dinner", "snack"]
    static func rank(_ mealType: String) -> Int { all.firstIndex(of: mealType) ?? all.count }
}

/// `yyyy-MM-dd` for a date in the given calendar's time zone (the meal-plan API's day keys).
enum PlanDay {
    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func key(daysFrom date: Date, _ offset: Int, calendar: Calendar = .current) -> String {
        key(calendar.date(byAdding: .day, value: offset, to: date) ?? date, calendar: calendar)
    }
}

// MARK: Plan

/// One planned meal, as small as the widgets and Siri need it.
struct WidgetMeal: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let recipeID: Int
    let title: String
    let date: String        // yyyy-MM-dd
    let mealType: String    // breakfast, lunch, dinner, snack
    /// "Cook 30 min", "Prep 10 min" or "" when the recipe gives no times.
    let time: String
    /// Absolute picture URL (thumbnail preferred), nil when the recipe has none.
    let imageURL: String?

    var mealTitle: String { mealType.capitalized }
}

struct PlanSnapshot: Codable, Equatable, Sendable {
    var meals: [WidgetMeal]

    /// Replaces what the snapshot knew about `from...to` with `incoming` (one fetched or edited week), keeping other
    /// days, dropping days before `today` and anything more than `keepDays` ahead so the file stays small.
    func merging(_ incoming: [WidgetMeal], from: String, to: String, today: String, keepUntil: String) -> PlanSnapshot {
        let kept = meals.filter { $0.date < from || $0.date > to }
        let all = (kept + incoming).filter { $0.date >= today && $0.date <= keepUntil }
        return PlanSnapshot(meals: all.sorted { ($0.date, MealOrder.rank($0.mealType), $0.id) < ($1.date, MealOrder.rank($1.mealType), $1.id) })
    }

    /// Everything planned for the day `now` falls on in `calendar`'s time zone, in meal order.
    func meals(on now: Date, calendar: Calendar = .current) -> [WidgetMeal] {
        let key = PlanDay.key(now, calendar: calendar)
        return meals.filter { $0.date == key }.sorted { (MealOrder.rank($0.mealType), $0.id) < (MealOrder.rank($1.mealType), $1.id) }
    }

    /// Tonight's dinner: the first dinner planned for today in the device's time zone.
    func dinner(on now: Date, calendar: Calendar = .current) -> WidgetMeal? {
        meals(on: now, calendar: calendar).first { $0.mealType == "dinner" }
    }
}

/// One day on the week widget: the meal it shows (dinner, else the first meal) and how many more are planned.
struct WidgetDay: Hashable, Sendable, Identifiable {
    let date: String        // yyyy-MM-dd
    let isToday: Bool
    let meal: WidgetMeal?
    let others: Int

    var id: String { date }
}

extension PlanSnapshot {
    /// Today and the next `days - 1` days (a rolling week: nothing already eaten, and tomorrow is always there), each
    /// with its dinner or, when no dinner is planned, its first meal.
    func week(from now: Date, days: Int = 7, calendar: Calendar = .current) -> [WidgetDay] {
        let start = calendar.startOfDay(for: now)
        return (0..<days).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            let planned = meals(on: day, calendar: calendar)
            let shown = planned.first { $0.mealType == "dinner" } ?? planned.first
            return WidgetDay(date: PlanDay.key(day, calendar: calendar), isToday: offset == 0, meal: shown,
                             others: max(0, planned.count - (shown == nil ? 0 : 1)))
        }
    }
}

extension WidgetMeal {
    /// From a plan entry; `base` resolves the server's relative picture paths.
    init(_ entry: PlanEntry, base: URL?) {
        let r = entry.recipe
        let time = !r.cookTime.isEmpty ? "Cook \(r.cookTime)" : !r.prepTime.isEmpty ? "Prep \(r.prepTime)" : ""
        let path = r.thumbUrl.isEmpty ? r.imageUrl : r.thumbUrl
        self.init(id: entry.id, recipeID: r.id, title: r.title, date: entry.date, mealType: entry.mealType.rawValue,
                  time: time, imageURL: WidgetMeal.resolve(path, base: base)?.absoluteString)
    }

    static func resolve(_ path: String, base: URL?) -> URL? {
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        guard let base else { return nil }
        return URL(string: path, relativeTo: base)?.absoluteURL
    }
}

// MARK: Shopping

struct WidgetShoppingItem: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let name: String
    let aisle: String
    var checked: Bool
}

struct ShoppingSnapshot: Codable, Equatable, Sendable {
    var aisleOrder: [String]
    var items: [WidgetShoppingItem]

    init(aisleOrder: [String], items: [WidgetShoppingItem]) { self.aisleOrder = aisleOrder; self.items = items }

    init(_ list: ShoppingList) {
        self.init(aisleOrder: list.aisleOrder,
                  items: list.items.map { WidgetShoppingItem(id: $0.id, name: $0.name, aisle: $0.aisle, checked: $0.checked) })
    }

    /// Ticks the items the widget ticked but the server hasn't heard about yet.
    func applying(_ ticks: [PendingTick]) -> ShoppingSnapshot {
        var copy = self
        for tick in ticks {
            if let i = copy.items.firstIndex(where: { $0.id == tick.itemID }) { copy.items[i].checked = tick.checked }
        }
        return copy
    }

    /// Unticked items grouped by aisle in the store's order, as the app's "All items" view shows them.
    /// (Aisles the order doesn't name go last, so nothing unticked is ever hidden.)
    var openByAisle: [(aisle: String, items: [WidgetShoppingItem])] {
        let open = items.filter { !$0.checked }
        let grouped = Dictionary(grouping: open, by: \.aisle)
        let extra = grouped.keys.filter { !aisleOrder.contains($0) }.sorted()
        return (aisleOrder + extra).compactMap { a in grouped[a].map { (a, $0) } }
    }

    var openCount: Int { items.filter { !$0.checked }.count }

    enum Row: Hashable, Sendable {
        case aisle(String)
        case item(WidgetShoppingItem)
    }

    /// What fits in `lines` rows of a widget: aisle headings (when `headings`) and unticked items, in aisle order, plus
    /// how many items didn't fit. A heading is never left at the bottom with no item under it.
    func widgetRows(lines: Int, headings: Bool) -> (rows: [Row], hidden: Int) {
        var rows: [Row] = [], shown = 0
        for group in openByAisle {
            let room = lines - rows.count - (headings ? 1 : 0)
            guard room > 0 else { break }
            if headings { rows.append(.aisle(group.aisle)) }
            for item in group.items.prefix(room) { rows.append(.item(item)); shown += 1 }
        }
        return (rows, openCount - shown)
    }
}

/// A tick made on the widget that hasn't reached the server yet. The app moves these into its Outbox on launch.
struct PendingTick: Codable, Hashable, Sendable {
    let itemID: Int
    let name: String
    let checked: Bool
}

// MARK: Random recipe

/// A recipe the Random Recipe widget can show: its picture is a small JPEG in the App Group (`Thumbs/<image>`), made
/// by the app from the copy it already downloaded, since the widget can't page through the library itself.
struct PoolRecipe: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let title: String
    /// File name in the thumbnails folder, nil when the app has no picture for it (the widget shows the letter tile).
    let image: String?
}

struct PoolCollection: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let name: String
    let recipes: [PoolRecipe]
}

/// What the Random Recipe widget picks from: up to `allCap` recipes, and up to `collectionCap` from each collection.
struct RecipePoolSnapshot: Codable, Equatable, Sendable {
    static let allCap = 100
    static let collectionCap = 60

    var all: [PoolRecipe]
    var collections: [PoolCollection]

    /// The pool for a collection, or every recipe for nil (or a collection that has since gone).
    func recipes(in collectionID: Int?) -> [PoolRecipe] {
        guard let collectionID, let match = collections.first(where: { $0.id == collectionID }) else { return all }
        return match.recipes
    }

    /// Every thumbnail the snapshot uses (the rest can be deleted).
    var imageNames: Set<String> {
        Set((all + collections.flatMap(\.recipes)).compactMap(\.image))
    }

    /// Which ids go in a capped pool: those already in it (so pictures aren't remade on every sync) while they still
    /// exist, topped up at random from the rest.
    static func select(_ candidates: [Int], previous: [Int], cap: Int, using rng: inout some RandomNumberGenerator) -> [Int] {
        let available = Set(candidates)
        var seen = Set<Int>()
        let kept = previous.filter { available.contains($0) && seen.insert($0).inserted }.prefix(cap)
        let rest = candidates.filter { !seen.contains($0) }.shuffled(using: &rng)
        return Array(kept) + rest.prefix(max(0, cap - kept.count))
    }

    /// `count` different recipes in random order (repeating only when the pool is smaller than `count`).
    static func picks(from pool: [PoolRecipe], count: Int, using rng: inout some RandomNumberGenerator) -> [PoolRecipe] {
        guard !pool.isEmpty, count > 0 else { return [] }
        var out: [PoolRecipe] = []
        while out.count < count {
            var round = pool.shuffled(using: &rng)
            // No recipe twice in a row across rounds.
            if let last = out.last, round.first == last, round.count > 1 { round.swapAt(0, round.count - 1) }
            out += round.prefix(count - out.count)
        }
        return out
    }
}

// MARK: Storage

/// Reads and writes the snapshots in the App Group container (or any folder, for tests).
struct SnapshotStore: Sendable {
    let directory: URL?

    static var shared: SnapshotStore {
        SnapshotStore(directory: AppGroup.containerURL?.appendingPathComponent("Widgets", isDirectory: true))
    }

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e }()

    var plan: PlanSnapshot? { read("plan.json") }
    var shopping: ShoppingSnapshot? { read("shopping.json") }
    var pendingTicks: [PendingTick] { read("pending-ticks.json") ?? [] }
    var recipePool: RecipePoolSnapshot? { read("recipe-pool.json") }

    /// Writes the snapshot; true when it differs from what was there (so the caller knows to reload the widget).
    @discardableResult func write(plan: PlanSnapshot) -> Bool { write(plan, "plan.json") }
    @discardableResult func write(shopping: ShoppingSnapshot) -> Bool { write(shopping, "shopping.json") }
    @discardableResult func write(recipePool: RecipePoolSnapshot) -> Bool { write(recipePool, "recipe-pool.json") }

    /// The Random Recipe widget's small JPEGs (`PoolRecipe.image`).
    var thumbnailsDirectory: URL? { directory?.appendingPathComponent("Thumbs", isDirectory: true) }

    func thumbnail(named name: String) -> URL? { thumbnailsDirectory?.appendingPathComponent(name) }

    func addPendingTick(_ tick: PendingTick) {
        var ticks = pendingTicks.filter { $0.itemID != tick.itemID }
        ticks.append(tick)
        write(ticks, "pending-ticks.json")
    }

    func removePendingTicks(_ ids: Set<Int>) {
        write(pendingTicks.filter { !ids.contains($0.itemID) }, "pending-ticks.json")
    }

    /// Every pending tick, removed from the file (the app has taken them into its Outbox).
    func takePendingTicks() -> [PendingTick] {
        let ticks = pendingTicks
        if !ticks.isEmpty, let url = file("pending-ticks.json") { try? FileManager.default.removeItem(at: url) }
        return ticks
    }

    /// Ticks an item in the saved list straight away, so the widget redraws without it.
    func markChecked(_ id: Int, checked: Bool = true) {
        guard var snapshot = shopping, let i = snapshot.items.firstIndex(where: { $0.id == id }) else { return }
        snapshot.items[i].checked = checked
        write(shopping: snapshot)
    }

    /// Where a copy of a picture lives (named like `ImageStore`'s files, so the app can copy its own straight in).
    func imageFile(for url: URL) -> URL? {
        guard let directory else { return nil }
        return directory.appendingPathComponent("Images", isDirectory: true).appendingPathComponent(Self.digest(url.absoluteString))
    }

    func clear() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Internals

    private func file(_ name: String) -> URL? { directory?.appendingPathComponent(name) }

    private func read<T: Decodable>(_ name: String) -> T? {
        guard let url = file(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    private func write<T: Encodable>(_ value: T, _ name: String) -> Bool {
        guard let directory, let url = file(name), let data = try? Self.encoder.encode(value) else { return false }
        if let old = try? Data(contentsOf: url), old == data { return false }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Readable after first unlock, so the widget can refresh on a locked phone.
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return true
    }
}
