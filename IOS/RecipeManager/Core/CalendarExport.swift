import Foundation

// The decisions behind "Add week to Calendar" and "Add to Reminders", kept apart from EventKit so they can be tested.
// `EventKitExporter` (EventKitExporter.swift) does the reading and writing.

/// One meal as it should appear in Calendar: an all-day event on its day.
struct MealEvent: Equatable, Sendable {
    let entryID: Int
    let recipeID: Int
    /// "Dinner: Lasagne"
    let title: String
    /// yyyy-MM-dd
    let date: String

    var link: URL { DeepLink.recipe(recipeID).url }
    /// The event's notes: the link, so it can be tapped from any calendar app.
    var notes: String { link.absoluteString }

    init(entryID: Int, recipeID: Int, title: String, date: String) {
        self.entryID = entryID; self.recipeID = recipeID; self.title = title; self.date = date
    }

    init(_ entry: PlanEntry) {
        self.init(entryID: entry.id, recipeID: entry.recipe.id, title: "\(entry.mealType.title): \(entry.recipe.title)", date: entry.date)
    }
}

/// What an exported event looks like in Calendar now (nil fields when the user cleared them).
struct ExistingEvent: Equatable, Sendable {
    let title: String
    let date: String
    let link: URL?
    let notes: String?
}

/// The events Spoonmate made, by meal-plan entry id, so exporting a week again updates them instead of duplicating.
struct ExportedEvent: Codable, Equatable, Sendable {
    let eventID: String
    /// The entry's day when it was exported, which says which week the event belongs to.
    let date: String
}

enum CalendarExportDiff {
    struct Update: Equatable, Sendable { let eventID: String; let event: MealEvent }
    struct Removal: Equatable, Sendable { let entryID: Int; let eventID: String }

    struct Plan: Equatable, Sendable {
        var create: [MealEvent] = []
        var update: [Update] = []
        var unchanged: [Int] = []
        var remove: [Removal] = []

        var isEmpty: Bool { create.isEmpty && update.isEmpty && remove.isEmpty }
    }

    /// Compares the week's meals with what was exported before.
    /// - `wanted`: the week's meals (entries not yet on the server, with negative ids, should be left out by the caller).
    /// - `exported`: every entry → event mapping saved so far, any week.
    /// - `existing`: the mapped events Calendar still has, by event id (one the user deleted is missing, so it's made again).
    /// - `from`...`to`: the week. A mapped entry dated in it that is no longer planned has its event removed.
    static func plan(wanted: [MealEvent], exported: [Int: ExportedEvent], existing: [String: ExistingEvent],
                     from: String, to: String) -> Plan {
        var plan = Plan()
        let wantedIDs = Set(wanted.map(\.entryID))
        for meal in wanted.sorted(by: { ($0.date, $0.entryID) < ($1.date, $1.entryID) }) {
            guard let mapped = exported[meal.entryID], let current = existing[mapped.eventID] else {
                plan.create.append(meal)
                continue
            }
            if current.title == meal.title && current.date == meal.date && current.link == meal.link && current.notes == meal.notes {
                plan.unchanged.append(meal.entryID)
            } else {
                plan.update.append(Update(eventID: mapped.eventID, event: meal))
            }
        }
        for (entryID, mapped) in exported.sorted(by: { $0.key < $1.key })
        where !wantedIDs.contains(entryID) && mapped.date >= from && mapped.date <= to {
            plan.remove.append(Removal(entryID: entryID, eventID: mapped.eventID))
        }
        return plan
    }

    /// The confirmation: "Added 5 meals to Calendar", or a summary when meals were also changed or removed.
    static func summary(added: Int, updated: Int, removed: Int) -> String {
        func meals(_ n: Int) -> String { n == 1 ? "1 meal" : "\(n) meals" }
        if added == 0 && updated == 0 && removed == 0 { return "Calendar already has this week." }
        if updated == 0 && removed == 0 { return "Added \(meals(added)) to Calendar" }
        var parts: [String] = []
        if added > 0 { parts.append("\(added) added") }
        if updated > 0 { parts.append("\(updated) updated") }
        if removed > 0 { parts.append("\(removed) removed") }
        return "Calendar updated: " + parts.joined(separator: ", ")
    }
}

enum ReminderExport {
    static let listTitle = "Spoonmate shopping"

    /// The unticked items to add as reminders: each name once (ignoring case and spacing), and none the list already
    /// has open. Completed reminders don't count: buying milk last week doesn't mean it's on the list now.
    static func namesToAdd(open items: [String], existingOpen reminders: [String]) -> [String] {
        var seen = Set(reminders.map(key))
        return items.compactMap { name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(key(trimmed)).inserted else { return nil }
            return trimmed
        }
    }

    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func summary(added: Int) -> String {
        switch added {
        case 0: "Reminders already has everything on your list."
        case 1: "Added 1 item to Reminders"
        default: "Added \(added) items to Reminders"
        }
    }
}
