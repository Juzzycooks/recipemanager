import SwiftUI

/// Everything a screen can push. IDs, not models: each destination loads fresh data from the server.
enum AppRoute: Hashable {
    case recipe(Int)
    case collection(Int)
    case recipeList(RecipeListKind)
    case mealPlan
    case shoppingList
    case devices
    case settings
    case adminSettings
    case adminUsers
    case adminCategories
}

enum RecipeListKind: Hashable {
    case all
    case favorites

    var title: String { self == .all ? "All Recipes" : "Favorites" }
}

extension View {
    /// Registers every `AppRoute` destination on the enclosing NavigationStack.
    func appDestinations() -> some View {
        // The app draws its own tab bar, so the system one must stay hidden on roots and on every pushed screen.
        toolbarVisibility(.hidden, for: .tabBar)
            .navigationDestination(for: AppRoute.self) { route in
                Group {
                    switch route {
                    case .recipe(let id): RecipeDetailView(id: id)
                    case .collection(let id): CollectionDetailView(id: id)
                    case .recipeList(let kind): RecipeListView(kind: kind)
                    case .mealPlan: MealPlanView()
                    case .shoppingList: ShoppingListView()
                    case .devices: DevicesView()
                    case .settings: SettingsView()
                    case .adminSettings: AdminSettingsView()
                    case .adminUsers: AdminUsersView()
                    case .adminCategories: AdminCategoriesView()
                    }
                }
                .toolbarVisibility(.hidden, for: .tabBar)
            }
    }
}
