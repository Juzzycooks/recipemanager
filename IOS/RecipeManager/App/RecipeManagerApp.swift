import SwiftUI
import UserNotifications

@main
struct RecipeManagerApp: App {
    @State private var session = Session()
    @State private var appState = AppState()
    @State private var timer = CookTimer()
    @State private var offlineSync = OfflineSync()
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
