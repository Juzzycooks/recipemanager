import SwiftUI
import UIKit
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

    /// A recipe that should go straight into cook mode once its page has loaded (Siri's "Cook …").
    var pendingCook: Int?

    /// Opens a recipe and starts cook mode on it.
    func cook(recipe id: Int) {
        pendingCook = id
        if !isShowing(recipe: id) { open(recipe: id) }
    }

    /// True when that recipe's page is the screen on top of the current tab.
    func isShowing(recipe id: Int) -> Bool { paths[tab]?.last == .recipe(id) }

    /// Where a widget, Spotlight result or `spoonmate://` link points. Any sheet in the way is closed first.
    func handle(_ link: DeepLink) {
        showingAdd = false
        switch link {
        case .recipe(let id):
            if !isShowing(recipe: id) { open(recipe: id) }   // already showing it: don't stack a second copy
        case .cook(let id): cook(recipe: id)
        case .plan: tab = .plan; paths[.plan] = []
        case .shopping: tab = .shop; paths[.shop] = []
        }
    }

    /// The one Undo offer, shown in `StatusStack` (see `UndoCenter`).
    let undo = UndoCenter()

    /// Offers to take a change back for a few seconds: `app.offerUndo("Removed “Soup”") { await … }`.
    /// A newer offer replaces this one (which then commits). VoiceOver announces it, and gets longer to reach the button.
    @discardableResult
    func offerUndo(_ message: String, commit: @escaping @MainActor () async -> Void = {},
                   undo action: @escaping @MainActor () async -> Void) async -> UndoCenter.Offer.ID {
        let voiceOver = UIAccessibility.isVoiceOverRunning
        if voiceOver { UIAccessibility.post(notification: .announcement, argument: "\(message). Undo available.") }
        return await undo.offer(message, for: voiceOver ? .seconds(20) : nil, commit: commit, undo: action)
    }

    func say(_ text: String) {
        notice = text
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if notice == text { notice = nil }
        }
    }
}
