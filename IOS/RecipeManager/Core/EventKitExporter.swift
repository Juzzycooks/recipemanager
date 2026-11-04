import EventKit
import os
import SwiftUI
import UIKit

/// Writes the meal plan to Calendar and the shopping list to Reminders. The decisions (what to create, change or
/// remove; which items are new) are in `CalendarExportDiff` and `ReminderExport`; this type only talks to EventKit.
/// Everything runs on the main actor: the work is a few dozen items, and EventKit's objects aren't Sendable.
@MainActor
final class EventKitExporter {
    static let shared = EventKitExporter()

    private let store = EKEventStore()
    private let defaults: UserDefaults
    private static let log = Logger(subsystem: "com.justinrahme.Spoonmate", category: "EventKit")

    private static let mappingKey = "calendarExport.events"
    static let calendarKey = "calendarExport.calendarID"
    private static let reminderListKey = "reminderExport.listID"
    private static let remindersUsedKey = "reminderExport.used"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    enum ExportError: LocalizedError {
        case noCalendar
        case noReminderSource

        var errorDescription: String? {
            switch self {
            case .noCalendar: "There's no calendar on this iPhone that can take new events. Add one in the Calendar app."
            case .noReminderSource: "There's nowhere to make a Reminders list. Turn on Reminders for iCloud or an account in Settings."
            }
        }
    }

    // MARK: Access

    /// Asks for full Calendar access the first time; true when Spoonmate has it.
    func requestCalendarAccess() async -> Bool {
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess { return true }
        return await withCheckedContinuation { done in
            store.requestFullAccessToEvents { granted, _ in done.resume(returning: granted) }
        }
    }

    func requestRemindersAccess() async -> Bool {
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess { return true }
        return await withCheckedContinuation { done in
            store.requestFullAccessToReminders { granted, _ in done.resume(returning: granted) }
        }
    }

    // MARK: Calendar

    struct CalendarChoice: Identifiable, Hashable {
        let id: String
        let title: String
        let color: Color
        let account: String
    }

    /// Calendars that can take new events, the default one first.
    var writableCalendars: [CalendarChoice] {
        let defaultID = store.defaultCalendarForNewEvents?.calendarIdentifier
        return store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .sorted { ($0.calendarIdentifier == defaultID ? 0 : 1, $0.title) < ($1.calendarIdentifier == defaultID ? 0 : 1, $1.title) }
            .map { CalendarChoice(id: $0.calendarIdentifier, title: $0.title, color: Color(cgColor: $0.cgColor), account: $0.source?.title ?? "") }
    }

    /// The calendar chosen last time if it still exists, otherwise the default calendar for new events.
    var preferredCalendarID: String? {
        let writable = writableCalendars
        if let saved = defaults.string(forKey: Self.calendarKey), writable.contains(where: { $0.id == saved }) { return saved }
        return store.defaultCalendarForNewEvents?.calendarIdentifier ?? writable.first?.id
    }

    struct WeekResult: Equatable { let added: Int; let updated: Int; let removed: Int }

    /// Puts the week's meals in Calendar as all-day events. Meals exported before are updated (moved, renamed) rather
    /// than added again, and events for meals no longer planned that week are removed.
    func exportWeek(_ entries: [PlanEntry], from: String, to: String, calendarID: String?) throws -> WeekResult {
        guard let calendar = calendarID.flatMap(store.calendar(withIdentifier:)) ?? store.defaultCalendarForNewEvents,
              calendar.allowsContentModifications else { throw ExportError.noCalendar }
        defaults.set(calendar.calendarIdentifier, forKey: Self.calendarKey)

        var mapping = exported
        let wanted = entries.filter { $0.id > 0 }.map(MealEvent.init)     // not yet on the server: no lasting id
        var existing: [String: ExistingEvent] = [:]
        var events: [String: EKEvent] = [:]
        for meal in wanted {
            guard let mapped = mapping[meal.entryID], let event = store.event(withIdentifier: mapped.eventID) else { continue }
            events[mapped.eventID] = event
            existing[mapped.eventID] = ExistingEvent(title: event.title ?? "", date: PlanDay.key(event.startDate), link: event.url, notes: event.notes)
        }
        let plan = CalendarExportDiff.plan(wanted: wanted, exported: mapping, existing: existing, from: from, to: to)

        var created: [(entryID: Int, date: String, event: EKEvent)] = []
        for meal in plan.create {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            try fill(event, with: meal)
            created.append((meal.entryID, meal.date, event))
        }
        for change in plan.update {
            guard let event = events[change.eventID] else { continue }
            event.calendar = calendar
            try fill(event, with: change.event)
            mapping[change.event.entryID] = ExportedEvent(eventID: change.eventID, date: change.event.date)
        }
        for removal in plan.remove {
            if let event = store.event(withIdentifier: removal.eventID) { try store.remove(event, span: .thisEvent, commit: false) }
            mapping[removal.entryID] = nil
        }
        try store.commit()
        for item in created {
            if let id = item.event.eventIdentifier { mapping[item.entryID] = ExportedEvent(eventID: id, date: item.date) }
        }
        exported = mapping
        return WeekResult(added: plan.create.count, updated: plan.update.count, removed: plan.remove.count)
    }

    private func fill(_ event: EKEvent, with meal: MealEvent) throws {
        guard let day = Date.fromAPIDay(meal.date) else { return }
        let start = Calendar.current.startOfDay(for: day)
        event.title = meal.title
        event.isAllDay = true
        event.startDate = start
        event.endDate = start
        event.url = meal.link
        event.notes = meal.notes
        try store.save(event, span: .thisEvent, commit: false)
    }

    /// Entry id → event, saved in UserDefaults (it only means anything on this phone's calendars).
    private var exported: [Int: ExportedEvent] {
        get {
            guard let data = defaults.data(forKey: Self.mappingKey),
                  let raw = try? JSONDecoder().decode([String: ExportedEvent].self, from: data) else { return [:] }
            return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in Int(k).map { ($0, v) } })
        }
        set {
            let raw = Dictionary(uniqueKeysWithValues: newValue.map { (String($0.key), $0.value) })
            defaults.set(try? JSONEncoder().encode(raw), forKey: Self.mappingKey)
        }
    }

    // MARK: Reminders

    /// Adds the unticked shopping items to the "Spoonmate shopping" list (made if it's missing), skipping any it
    /// already has open. Completed reminders are left alone. Returns how many were added.
    func exportShopping(_ names: [String]) async throws -> Int {
        let list = try reminderList(create: true)
        guard let list else { throw ExportError.noReminderSource }
        let open = await openReminders(in: list)
        let toAdd = ReminderExport.namesToAdd(open: names, existingOpen: open.map(\.title))
        for name in toAdd {
            let reminder = EKReminder(eventStore: store)
            reminder.title = name
            reminder.calendar = list
            try store.save(reminder, commit: false)
        }
        if !toAdd.isEmpty { try store.commit() }
        defaults.set(true, forKey: Self.remindersUsedKey)
        return toAdd.count
    }

    /// Ticking an item in the app completes its open reminder, once the list has been sent to Reminders and access is
    /// already granted (this never asks).
    func completeReminder(named name: String) async {
        guard defaults.bool(forKey: Self.remindersUsedKey), EKEventStore.authorizationStatus(for: .reminder) == .fullAccess,
              let list = try? reminderList(create: false) else { return }
        let key = ReminderExport.key(name)
        var changed = false
        for item in await openReminders(in: list) where ReminderExport.key(item.title) == key {
            guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { continue }
            reminder.isCompleted = true
            do { try store.save(reminder, commit: false); changed = true }
            catch { Self.log.error("Couldn't complete reminder: \(String(describing: error), privacy: .public)") }
        }
        if changed { try? store.commit() }
    }

    private func reminderList(create: Bool) throws -> EKCalendar? {
        let lists = store.calendars(for: .reminder)
        if let id = defaults.string(forKey: Self.reminderListKey), let saved = lists.first(where: { $0.calendarIdentifier == id }) { return saved }
        if let named = lists.first(where: { $0.title == ReminderExport.listTitle }) {
            defaults.set(named.calendarIdentifier, forKey: Self.reminderListKey)
            return named
        }
        guard create else { return nil }
        guard let source = store.defaultCalendarForNewReminders()?.source
                ?? store.sources.first(where: { $0.sourceType == .local }) else { return nil }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = ReminderExport.listTitle
        list.source = source
        try store.saveCalendar(list, commit: true)
        defaults.set(list.calendarIdentifier, forKey: Self.reminderListKey)
        return list
    }

    private struct OpenReminder: Sendable { let id: String; let title: String }

    /// The list's open reminders, as plain values (the fetch answers on another thread).
    private func openReminders(in list: EKCalendar) async -> [OpenReminder] {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [list])
        return await withCheckedContinuation { done in
            store.fetchReminders(matching: predicate) { reminders in
                done.resume(returning: (reminders ?? []).map { OpenReminder(id: $0.calendarItemIdentifier, title: $0.title ?? "") })
            }
        }
    }
}

// MARK: When access is off

/// Calendar or Reminders access was refused: say so briefly and offer Settings.
struct SettingsPrompt: Identifiable, Equatable {
    let title: String
    let message: String
    var id: String { title }

    static let calendar = SettingsPrompt(title: "Calendar access is off",
                                         message: "To add your meal plan to Calendar, allow Spoonmate full access to Calendars in Settings.")
    static let reminders = SettingsPrompt(title: "Reminders access is off",
                                          message: "To add your shopping list to Reminders, allow Spoonmate full access to Reminders in Settings.")
}

extension View {
    func settingsPrompt(_ prompt: Binding<SettingsPrompt?>) -> some View {
        alert(prompt.wrappedValue?.title ?? "", isPresented: Binding(get: { prompt.wrappedValue != nil },
                                                                     set: { if !$0 { prompt.wrappedValue = nil } })) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Not now", role: .cancel) {}
        } message: { Text(prompt.wrappedValue?.message ?? "") }
    }
}
