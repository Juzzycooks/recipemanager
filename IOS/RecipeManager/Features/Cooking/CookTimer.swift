import Foundation
import Observation
import UIKit

/// The kitchen timer. App-wide (it survives closing cooking mode), backed by a system timer that rings with
/// the app closed (see `SystemTimer`). This class only tracks what the UI needs to show.
@MainActor @Observable
final class CookTimer {
    private(set) var startDate: Date?
    private(set) var fireDate: Date?
    private(set) var title = ""
    private(set) var finished = false
    /// Set when both Alarms and Notifications are turned off, so the UI can explain why nothing will ring.
    private(set) var permissionDenied = false
    /// True when a real alarm (not the notification fallback) is backing the timer.
    private(set) var isAlarm = false

    private var id: UUID?
    private var finishTask: Task<Void, Never>?

    var isRunning: Bool { fireDate != nil && !finished }
    var isActive: Bool { fireDate != nil }

    func start(minutes: Int, title: String, detail: String) async {
        cancel()
        let seconds = minutes * 60
        let newID = UUID()
        id = newID
        self.title = title
        let now = Date.now
        startDate = now; fireDate = now.addingTimeInterval(TimeInterval(seconds)); finished = false; permissionDenied = false

        switch await SystemTimer.schedule(id: newID, seconds: seconds, title: title, detail: detail) {
        case .alarm: isAlarm = true
        case .notification: isAlarm = false
        case .denied: isAlarm = false; permissionDenied = true
        }
        guard id == newID else { return }   // cancelled or replaced while we were asking for permission
        let fire = fireDate ?? now
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, fire.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self, self.id == newID else { return }
            self.finished = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    /// Stops the countdown (and the ringing, if it already started).
    func cancel() {
        finishTask?.cancel(); finishTask = nil
        if let id { SystemTimer.cancel(id: id) }
        id = nil; startDate = nil; fireDate = nil; finished = false; permissionDenied = false; isAlarm = false
    }

    /// Call when the app returns to the foreground: if the system timer was stopped elsewhere, drop ours.
    func reconcile() {
        guard let id, isActive else { return }
        if isAlarm && !SystemTimer.isStillScheduled(id: id) {
            finishTask?.cancel(); finishTask = nil
            self.id = nil; startDate = nil; fireDate = nil; finished = false; isAlarm = false
        } else if let fireDate, fireDate <= .now, !finished {
            finished = true
        }
    }

    /// "cook for 1–2 minutes" → 2; "simmer 20 min" → 20; "bake for 1 hour" → 60. Nil when the step names no time.
    nonisolated static func detectMinutes(in text: String) -> Int? {
        let pattern = #"(\d+)(?:\s*(?:–|-|to)\s*(\d+))?\s*(minutes?|mins?|hours?|hrs?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ i: Int) -> String? { Range(match.range(at: i), in: text).map { String(text[$0]) } }
        guard let first = group(1).flatMap(Int.init) else { return nil }
        let value = group(2).flatMap(Int.init) ?? first
        let unit = group(3)?.lowercased() ?? "min"
        let minutes = unit.hasPrefix("h") ? value * 60 : value
        return minutes > 0 && minutes <= 600 ? minutes : nil
    }
}
