import AppIntents

/// The phrases Siri knows without any setup. A phrase can carry at most one value, and only a recipe (entity) or a
/// listed choice (enum), never free text or a number, so the shopping item, the day and an unusual timer length are
/// asked for after the phrase ("What would you like to add?").
struct SpoonmateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddToShoppingListIntent(), phrases: [
            "Add to my shopping list in \(.applicationName)",
            "Add something to my \(.applicationName) shopping list",
            "Add an item to my shopping list in \(.applicationName)",
        ], shortTitle: "Add to Shopping List", systemImageName: "cart.badge.plus")

        AppShortcut(intent: WhatsForDinnerIntent(), phrases: [
            "What's for dinner in \(.applicationName)",
            "What's for dinner tonight in \(.applicationName)",
            "What's on the \(.applicationName) meal plan today",
        ], shortTitle: "What's for Dinner", systemImageName: "fork.knife")

        AppShortcut(intent: OpenRecipeIntent(), phrases: [
            "Open \(\.$target) in \(.applicationName)",
            "Show \(\.$target) in \(.applicationName)",
            "Open a recipe in \(.applicationName)",
        ], shortTitle: "Open Recipe", systemImageName: "book.closed")

        AppShortcut(intent: CookRecipeIntent(), phrases: [
            "Cook \(\.$recipe) in \(.applicationName)",
            "Start cooking \(\.$recipe) in \(.applicationName)",
            "Start cooking in \(.applicationName)",
        ], shortTitle: "Cook a Recipe", systemImageName: "flame")

        AppShortcut(intent: QuickTimerIntent(), phrases: [
            "Start a \(\.$length) timer in \(.applicationName)",
            "Set a \(\.$length) timer in \(.applicationName)",
        ], shortTitle: "Quick Timer", systemImageName: "timer")

        AppShortcut(intent: StartTimerIntent(), phrases: [
            "Start a timer in \(.applicationName)",
            "Start a kitchen timer in \(.applicationName)",
        ], shortTitle: "Kitchen Timer", systemImageName: "timer")

        AppShortcut(intent: PlanRecipeIntent(), phrases: [
            "Plan \(\.$recipe) in \(.applicationName)",
            "Add \(\.$recipe) to my \(.applicationName) meal plan",
            "Plan a meal in \(.applicationName)",
        ], shortTitle: "Plan a Recipe", systemImageName: "calendar.badge.plus")
    }

    static let shortcutTileColor = ShortcutTileColor.orange
}
