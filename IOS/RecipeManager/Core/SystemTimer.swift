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

    static func schedule(id: UUID, seconds: Int, title: String, detail: String) async -> Outcome {
        if #available(iOS 26.1, *) {
            switch await scheduleAlarm(id: id, seconds: seconds, title: title, detail: detail) {
            case .some(let outcome): return outcome
            case .none: break   // AlarmKit refused; try notifications
            }
        }
        return await scheduleNotifications(id: id, seconds: seconds, title: title, detail: detail)
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
    private static func scheduleAlarm(id: UUID, seconds: Int, title: String, detail: String) async -> Outcome? {
        let manager = AlarmManager.shared
        if manager.authorizationState == .notDetermined {
            do { _ = try await manager.requestAuthorization() }
            catch { log.error("AlarmKit authorization failed: \(String(describing: error), privacy: .public)") }
        }
        guard manager.authorizationState == .authorized else {
            log.notice("AlarmKit not authorized (state \(String(describing: manager.authorizationState), privacy: .public)); falling back to notifications")
            return nil
        }

        let presentation = AlarmPresentation(
            alert: AlarmPresentation.Alert(title: "\(title): time's up"),
            countdown: AlarmPresentation.Countdown(title: LocalizedStringResource(stringLiteral: title)),
            paused: nil)
        let attributes = AlarmAttributes(presentation: presentation,
                                         metadata: TimerMetadata(recipeTitle: title, detail: detail),
                                         tintColor: ThemeStore.shared.theme.tint)
        let configuration = AlarmManager.AlarmConfiguration.timer(duration: TimeInterval(seconds), attributes: attributes, sound: .default)
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

    private static func scheduleNotifications(id: UUID, seconds: Int, title: String, detail: String) async -> Outcome {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return .denied }
        for n in 0..<burstCount {
            let content = UNMutableNotificationContent()
            content.title = "\(title): time's up"
            content.body = detail.isEmpty ? "Your kitchen timer has finished." : detail
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
