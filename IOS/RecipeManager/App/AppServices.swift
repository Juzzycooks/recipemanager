import Foundation

/// The app's long-lived objects, created once per process. The SwiftUI scene puts them in the environment, and App
/// Intents (Siri, Shortcuts, Spotlight) use the same instances, so an intent that runs while the app is open, or in a
/// process iOS started in the background just for it, signs in, queues offline changes and starts timers exactly as
/// the screens do. There is no second sign-in path.
@MainActor
enum AppServices {
    static let session = Session()
    static let app = AppState()
    static let timer = CookTimer()
    static let offlineSync = OfflineSync()

    /// True when credentials are saved. (`Session.isSignedIn` only turns true once `/me` answers; an intent started
    /// with the app closed can't wait for that, and `Session.run` signs out on a revoked token anyway.)
    static var hasAccount: Bool { session.hasCredentials }
}
