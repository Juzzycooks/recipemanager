import SwiftUI

@main
struct RecipeManagerApp: App {
    @State private var session = Session()
    @State private var appState = AppState()
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue

    init() { AppTypography.configureNavigationBar() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(appState)
                .tint(AppColors.primary)
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
