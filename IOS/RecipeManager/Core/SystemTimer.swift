import AlarmKit
import os
import SwiftUI
import UserNotifications

/// Hands a countdown to the operating system so it keeps running (and rings) with the app closed.
///
/// - iOS 26.1+: an AlarmKit timer. Rings like the Clock app (overrides silent mode and Focus) and shows a
///   countdown on the Lock Screen and in the Dynamic Island (see the TimerWidget extension).
/// - Earlier iOS: a burst of local notifications with sound, repeated for about a minute, since there is
///   no alarm API. It is a chime, not a true alarm.
@MainActor
enum SystemTimer {
    enum Outcome {
        case alarm            // a real system timer
        case notification     // notification fallback
        case denied           // the person has turned both off
    }

    /// One notification every `burstInterval` seconds for `burstCount` rings on the fallback path.
    private static let log = Logger(subsystem: "com.justinrahme.Spoonmate", category: "SystemTimer")

    static let burstInterval = 10
    static let burstCount = 6

    /// `name` is what the cook called this timer ("Pasta", "Step 3"); several can be scheduled at once, each under its own id.
    /// `extraMinutes` > 0 (a range timer) adds a "+N min" button to the alarm that runs the rest of the range.
    static func schedule(id: UUID, seconds: Int, name: String, recipeTitle: String, extraMinutes: Int = 0) async -> Outcome {
        if #available(iOS 26.1, *) {
            switch await scheduleAlarm(id: id, seconds: seconds, name: name, recipeTitle: recipeTitle, extraMinutes: extraMinutes) {
            case .some(let outcome): return outcome
            case .none: break   // AlarmKit refused; try notifications
            }
        }
        return await scheduleNotifications(id: id, seconds: seconds, name: name, recipeTitle: recipeTitle)
    }

    static func cancel(id: UUID) {
        if #available(iOS 26.1, *) { try? AlarmManager.shared.cancel(id: id) }
        let center = UNUserNotificationCenter.current()
        let ids = notificationIDs(for: id)
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// Whether the system still knows the timer (false once it was stopped from the Lock Screen, for example).
    static func isStillScheduled(id: UUID) -> Bool {
        if #available(iOS 26.1, *), let alarms = try? AlarmManager.shared.alarms { return alarms.contains { $0.id == id } }
        return true
    }

    // MARK: AlarmKit

    @available(iOS 26.1, *)
    private static func scheduleAlarm(id: UUID, seconds: Int, name: String, recipeTitle: String, extraMinutes: Int) async -> Outcome? {
        let manager = AlarmManager.shared
        if manager.authorizationState == .notDetermined {
            do { _ = try await manager.requestAuthorization() }
            catch { log.error("AlarmKit authorization failed: \(String(describing: error), privacy: .public)") }
        }
        guard manager.authorizationState == .authorized else {
            log.notice("AlarmKit not authorized (state \(String(describing: manager.authorizationState), privacy: .public)); falling back to notifications")
            return nil
        }

        // A range timer ("2–3 hours", started at 2) offers the rest of the range from the alert itself.
        let alert = extraMinutes > 0
            ? AlarmPresentation.Alert(title: "\(name): time's up",
                                      secondaryButton: AlarmButton(text: "+\(extraMinutes) min", textColor: .white, systemImageName: "plus"),
                                      secondaryButtonBehavior: .custom)
            : AlarmPresentation.Alert(title: "\(name): time's up")
        let extend = extraMinutes > 0
            ? ExtendKitchenTimerIntent(alarmID: id.uuidString, minutes: extraMinutes, name: name, recipeTitle: recipeTitle) : nil
        let presentation = AlarmPresentation(
            alert: alert,
            countdown: AlarmPresentation.Countdown(title: LocalizedStringResource(stringLiteral: name)),
            paused: nil)
        // `detail` carries the timer's name, so the Live Activity can tell "Pasta" from "Sauce".
        let attributes = AlarmAttributes(presentation: presentation,
                                         metadata: TimerMetadata(recipeTitle: recipeTitle, detail: name),
                                         tintColor: ThemeStore.shared.theme.tint)
        let configuration = AlarmManager.AlarmConfiguration.timer(duration: TimeInterval(seconds), attributes: attributes,
                                                                  secondaryIntent: extend, sound: .default)
        do {
            _ = try await manager.schedule(id: id, configuration: configuration)
            return .alarm
        } catch {
            log.error("AlarmKit schedule failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: Notification fallback

    private static func notificationIDs(for id: UUID) -> [String] { (0..<burstCount).map { "\(id.uuidString)-\($0)" } }

    private static func scheduleNotifications(id: UUID, seconds: Int, name: String, recipeTitle: String) async -> Outcome {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return .denied }
        for n in 0..<burstCount {
            let content = UNMutableNotificationContent()
            content.title = "\(name): time's up"
            content.body = recipeTitle.isEmpty ? "Your kitchen timer has finished." : recipeTitle
            content.threadIdentifier = id.uuidString   // each timer's rings group together
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds + n * burstInterval), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "\(id.uuidString)-\(n)", content: content, trigger: trigger))
        }
        return .notification
    }
}

/// Lets a notification chime even while the app is open (iOS otherwise stays silent for foreground apps).
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
