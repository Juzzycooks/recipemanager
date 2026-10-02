import SwiftUI
import Observation

enum AppTab: String, CaseIterable, Identifiable {
    case home, search, collections, profile
    var id: String { rawValue }
    var title: String {
        switch self { case .home: "Home"; case .search: "Search"; case .collections: "Collections"; case .profile: "Profile" }
    }
    var symbol: String {
        switch self { case .home: "house"; case .search: "magnifyingglass"; case .collections: "books.vertical"; case .profile: "person" }
    }
    var selectedSymbol: String {
        switch self { case .home: "house.fill"; case .search: "magnifyingglass"; case .collections: "books.vertical.fill"; case .profile: "person.fill" }
    }
}

/// UI state shared across tabs: which tab is showing, the Add sheet, transient messages.
@MainActor @Observable
final class AppState {
    var tab: AppTab = .home
    var showingAdd = false
    var notice: String?
    /// Bumped to ask the Search tab to focus its field (tapping the search bar on Home).
    var searchFocusRequest = 0
    /// A recipe to open on Home (after saving a new one from the Add sheet).
    var pendingRecipeID: Int?
    /// Screens that replace the tab bar with their own bottom action (recipe detail) register here.
    private(set) var tabBarHiders = 0

    var tabBarHidden: Bool { tabBarHiders > 0 }

    func hideTabBar() { tabBarHiders += 1 }
    func showTabBar() { tabBarHiders = max(0, tabBarHiders - 1) }

    func open(recipe id: Int) {
        tab = .home
        pendingRecipeID = id
    }

    /// Bumped by the Home button on pushed screens; every tab's stack pops back to its root.
    private(set) var homeRequest = 0

    func goHome() {
        tab = .home
        homeRequest += 1
    }

    func openSearch() {
        tab = .search
        searchFocusRequest += 1
    }

    func say(_ text: String) {
        notice = text
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if notice == text { notice = nil }
        }
    }
}

extension View {
    /// Hides the custom tab bar while this screen is on screen.
    func hidesAppTabBar() -> some View { modifier(HidesTabBar()) }
}

private struct HidesTabBar: ViewModifier {
    @Environment(AppState.self) private var app
    func body(content: Content) -> some View {
        content
            .onAppear { app.hideTabBar() }
            .onDisappear { app.showTabBar() }
    }
}
