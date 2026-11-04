import Foundation
import Observation
import UIKit

/// The kitchen timers. App-wide (they survive closing cooking mode), each backed by a system timer that rings
/// with the app closed (see `SystemTimer`). Several can run at once ("Pasta", "Sauce"). This class only tracks
/// what the UI needs to show.
@MainActor @Observable
final class CookTimer {
    struct Running: Identifiable, Equatable {
        let id: UUID
        let name: String
        let startDate: Date
        let fireDate: Date
        var finished = false
        /// True when a real alarm (not the notification fallback) is backing this timer.
        var isAlarm = false
        /// For a range ("2–3 hours", started at 2): the minutes a finished timer offers to add ("+60 min"). 0 otherwise.
        var extraMinutes = 0
        var recipeTitle = ""
    }

    /// The most a cook can sensibly watch at once (and it keeps the notification fallback under iOS's pending limit).
    static let maxTimers = 6

    private(set) var timers: [Running] = []
    /// Set when both Alarms and Notifications are turned off, so the UI can explain why nothing will ring.
    private(set) var permissionDenied = false

    private var finishTasks: [UUID: Task<Void, Never>] = [:]

    var isActive: Bool { !timers.isEmpty }
    var canAddMore: Bool { timers.count < Self.maxTimers }
    /// True when any running timer is on the notification fallback rather than a ringing alarm.
    var usesFallback: Bool { timers.contains { !$0.isAlarm && !$0.finished } }
    /// A finished timer first (it needs attention), otherwise the one that rings next.
    var soonest: Running? { timers.first { $0.finished } ?? timers.min { $0.fireDate < $1.fireDate } }

    /// The name a new timer gets when the cook doesn't type one: "Timer 2" and so on.
    var nextDefaultName: String { "Timer \(timers.count + 1)" }

    @discardableResult
    func start(seconds: Int, name: String, recipeTitle: String, extraMinutes: Int = 0) async -> UUID? {
        guard seconds > 0, canAddMore else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty ? nextDefaultName : trimmed
        let newID = UUID()
        let now = Date.now
        timers.append(Running(id: newID, name: label, startDate: now, fireDate: now.addingTimeInterval(TimeInterval(seconds)),
                              extraMinutes: max(0, extraMinutes), recipeTitle: recipeTitle))
        permissionDenied = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let outcome = await SystemTimer.schedule(id: newID, seconds: seconds, name: label, recipeTitle: recipeTitle,
                                                 extraMinutes: max(0, extraMinutes))
        guard let i = timers.firstIndex(where: { $0.id == newID }) else {
            SystemTimer.cancel(id: newID)   // cancelled while we were asking for permission: don't leave it ringing
            return nil
        }
        switch outcome {
        case .alarm: timers[i].isAlarm = true
        case .notification: timers[i].isAlarm = false
        case .denied: timers[i].isAlarm = false; permissionDenied = true
        }
        let fire = timers[i].fireDate
        finishTasks[newID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, fire.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self, let j = self.timers.firstIndex(where: { $0.id == newID }) else { return }
            self.timers[j].finished = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        return newID
    }

    func start(minutes: Int, name: String, recipeTitle: String) async {
        await start(seconds: minutes * 60, name: name, recipeTitle: recipeTitle)
    }

    /// Starts a step's own time: the low end of a range, with the rest offered when it rings.
    @discardableResult
    func start(_ duration: StepDuration, name: String, recipeTitle: String) async -> UUID? {
        await start(seconds: duration.seconds, name: name, recipeTitle: recipeTitle, extraMinutes: duration.extraMinutes)
    }

    /// "+N min" on a finished range timer: stops its ringing and runs the rest of the range under the same name.
    @discardableResult
    func extend(_ id: UUID) async -> UUID? {
        guard let old = timers.first(where: { $0.id == id }), old.extraMinutes > 0 else { return nil }
        cancel(id)
        return await start(seconds: old.extraMinutes * 60, name: old.name, recipeTitle: old.recipeTitle)
    }

    /// The same from the alarm's "+N min" button (`ExtendKitchenTimerIntent`), which may run after a relaunch when
    /// this process never knew the timer.
    func extend(alarmID: UUID, minutes: Int, name: String, recipeTitle: String) async {
        if timers.contains(where: { $0.id == alarmID }) { cancel(alarmID) } else { SystemTimer.cancel(id: alarmID) }
        guard minutes > 0 else { return }
        await start(seconds: minutes * 60, name: name, recipeTitle: recipeTitle)
    }

    /// Stops one countdown (and its ringing, if it already started).
    func cancel(_ id: UUID) {
        finishTasks.removeValue(forKey: id)?.cancel()
        SystemTimer.cancel(id: id)
        timers.removeAll { $0.id == id }
        if timers.isEmpty { permissionDenied = false }
    }

    func cancelAll() {
        for timer in timers { cancel(timer.id) }
    }

    /// Call when the app returns to the foreground: drop timers the system stopped elsewhere, mark the ones that rang.
    func reconcile() {
        for timer in timers {
            if timer.isAlarm && !SystemTimer.isStillScheduled(id: timer.id) {
                finishTasks.removeValue(forKey: timer.id)?.cancel()
                timers.removeAll { $0.id == timer.id }
            } else if timer.fireDate <= .now, !timer.finished, let i = timers.firstIndex(where: { $0.id == timer.id }) {
                timers[i].finished = true
            }
        }
        if timers.isEmpty { permissionDenied = false }
    }

    /// The first time a step mentions, in minutes (the low end of a range): "cook for 1–2 minutes" → 1; "simmer 20 min"
    /// → 20; "bake for 1 hour" → 60. Nil when the step names no time. See `StepDurations` for the whole list.
    nonisolated static func detectMinutes(in text: String) -> Int? {
        StepDurations.find(in: text).first?.minutes
    }
}
