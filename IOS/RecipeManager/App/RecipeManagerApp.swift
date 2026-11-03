import CoreSpotlight
import SwiftUI
import UserNotifications

@main
struct RecipeManagerApp: App {
    // Shared with App Intents (see AppServices), so Siri and the screens use the same session, timers and plan.
    @State private var session = AppServices.session
    @State private var appState = AppServices.app
    @State private var timer = AppServices.timer
    @State private var offlineSync = AppServices.offlineSync
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue

    init() {
        AppTypography.configureNavigationBar()
        // Pictures you've seen (or downloaded for offline use) stay on disk; the default cache is tiny.
        URLCache.shared = URLCache(memoryCapacity: 32 << 20, diskCapacity: 1 << 30)
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(appState)
                .environment(timer)
                .environment(offlineSync)
                .onChange(of: scenePhase) { if scenePhase == .active { timer.reconcile() } }
                // Widgets (spoonmate://recipe/12, ://plan, ://shop) and Spotlight results.
                .onOpenURL { url in if let link = DeepLink(url: url) { appState.handle(link) } }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let id = SpotlightIndexer.recipeID(from: activity) { appState.handle(.recipe(id)) }
                }
                .tint(ThemeStore.shared.theme.tint)
                .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}
