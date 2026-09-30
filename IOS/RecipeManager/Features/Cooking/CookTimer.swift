import Foundation
import Observation
import UIKit

/// One kitchen timer for the cooking screen. Counts down in whole seconds; buzzes when it reaches zero.
@MainActor @Observable
final class CookTimer {
    private(set) var remaining = 0
    private(set) var total = 0
    private(set) var finished = false
    private var task: Task<Void, Never>?

    var isRunning: Bool { task != nil }

    var display: String {
        let m = remaining / 60, s = remaining % 60
        return String(format: "%d:%02d", m, s)
    }

    func start(minutes: Int) {
        cancel()
        total = minutes * 60; remaining = total; finished = false
        task = Task { [weak self] in
            while let self, self.remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                self.remaining -= 1
            }
            guard let self, !Task.isCancelled else { return }
            self.finished = true
            self.task = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    func cancel() {
        task?.cancel(); task = nil
        remaining = 0; total = 0; finished = false
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
