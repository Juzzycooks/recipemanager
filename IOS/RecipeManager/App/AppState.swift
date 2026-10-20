import SwiftUI
import Observation

/// The system tab bar's sections. Add is an action (a toolbar button), Profile sits behind the avatar on Recipes.
enum AppTab: String, CaseIterable, Identifiable {
    case recipes, plan, shop, collections, search
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recipes: "Recipes"; case .plan: "Plan"; case .shop: "Shop"; case .collections: "Collections"; case .search: "Search"
        }
    }
    var symbol: String {
        switch self {
        case .recipes: "book.closed"; case .plan: "calendar"; case .shop: "cart"; case .collections: "books.vertical"; case .search: "magnifyingglass"
        }
    }
}

/// UI state shared across tabs: which tab is showing, each tab's navigation path, the Add sheet, transient messages.
@MainActor @Observable
final class AppState {
    var tab: AppTab = .recipes
    var showingAdd = false
    var notice: String?
    /// Each tab's NavigationStack path, so any screen (or the Add sheet) can push onto a tab and re-tapping a tab can pop it.
    var paths: [AppTab: [AppRoute]] = [:]

    func path(_ tab: AppTab) -> Binding<[AppRoute]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    /// The tab bar's selection. Tapping the tab that's already showing pops it back to its root, as in system apps.
    var selection: Binding<AppTab> {
        Binding(get: { self.tab }, set: { picked in
            if picked == self.tab { self.paths[picked] = [] } else { self.tab = picked }
        })
    }

    func push(_ route: AppRoute, on tab: AppTab) {
        paths[tab, default: []].append(route)
    }

    /// Shows a recipe on the Recipes tab (after saving a new one from the Add sheet).
    func open(recipe id: Int) {
        tab = .recipes
        push(.recipe(id), on: .recipes)
    }

    func say(_ text: String) {
        notice = text
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if notice == text { notice = nil }
        }
    }
}
