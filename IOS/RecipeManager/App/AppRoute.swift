import SwiftUI

/// Everything a screen can push. IDs, not models: each destination loads fresh data from the server.
/// Meal plan and shopping list are tabs, not destinations.
enum AppRoute: Hashable {
    case recipe(Int)
    case collection(Int)
    case recipeList(RecipeListKind)
    case devices
    /// Every cook, newest first (Profile).
    case cookLog
    /// Your cooks of one recipe (its "Made N times").
    case cookHistory(Int)
    case household
    case settings
    case adminSettings
    case adminUsers
    case adminCategories
}

enum RecipeListKind: Hashable {
    case all
    case favorites

    var title: String { self == .all ? "All recipes" : "Favorites" }
}

extension View {
    /// Registers every `AppRoute` destination on the enclosing NavigationStack.
    func appDestinations() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .recipe(let id): RecipeDetailView(id: id)
            case .collection(let id): CollectionDetailView(id: id)
            case .recipeList(let kind): RecipeListView(kind: kind)
            case .devices: DevicesView()
            case .cookLog: CookLogView(recipeID: nil)
            case .cookHistory(let id): CookLogView(recipeID: id)
            case .household: HouseholdView()
            case .settings: SettingsView()
            case .adminSettings: AdminSettingsView()
            case .adminUsers: AdminUsersView()
            case .adminCategories: AdminCategoriesView()
            }
        }
    }
}
