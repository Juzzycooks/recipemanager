import AppIntents
import SwiftUI

// Siri and Shortcuts. Every intent runs in the app's process and uses `AppServices` (the same Session, Outbox, timers
// and navigation as the screens), so offline queueing, sign-out on a revoked token and AlarmKit behave the same.
// Anything that needs the server says so when nobody is signed in instead of failing.

private enum Say {
    static let signedOut: IntentDialog = "Open Spoonmate and sign in first."
    static func text(_ text: String) -> IntentDialog { IntentDialog(LocalizedStringResource(stringLiteral: text)) }
}

// MARK: Shopping list

struct AddToShoppingListIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Shopping List"
    static let description = IntentDescription("Adds an item to your Spoonmate shopping list. Works offline: the item is sent when you're back online.")
    static let openAppWhenRun = false

    @Parameter(title: "Item", requestValueDialog: "What would you like to add?")
    var item: String

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$item) to the shopping list") }

    init() {}
    init(item: String) { self.item = item }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard AppServices.hasAccount else { return .result(dialog: Say.signedOut) }
        let name = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .result(dialog: "There was nothing to add.") }
        do {
            switch try await IntentActions.addToShopping(name, AppServices.session) {
            case .sent: return .result(dialog: Say.text("Added \(name) to your shopping list."))
            case .queued: return .result(dialog: Say.text("You're offline, so \(name) is on the list on this phone. It's sent when you're back online."))
            }
        } catch {
            return .result(dialog: Say.text("Couldn't add \(name). \(error.localizedDescription)"))
        }
    }
}

// MARK: Meal plan

struct WhatsForDinnerIntent: AppIntent {
    static let title: LocalizedStringResource = "What's for Dinner"
    static let description = IntentDescription("Tells you tonight's dinner, and anything else planned for today, from your Spoonmate meal plan.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard AppServices.hasAccount else { return .result(dialog: Say.signedOut, view: TodaySnippet(meals: [])) }
        let meals = await IntentActions.todaysMeals(AppServices.session)
        return .result(dialog: Say.text(DinnerAnswer.sentence(for: meals)), view: TodaySnippet(meals: meals))
    }
}

/// What Siri says about today's plan.
enum DinnerAnswer {
    static func sentence(for meals: [WidgetMeal]) -> String {
        let dinner = meals.first { $0.mealType == "dinner" }
        let others = meals.filter { $0.id != dinner?.id }.map { "for \($0.mealType), \($0.title)" }
        var text = dinner.map { "Tonight's dinner is \($0.title)." } ?? (meals.isEmpty ? "Nothing's planned for today." : "No dinner planned yet.")
        if !others.isEmpty { text += " Also today: " + others.joined(separator: "; ") + "." }
        return text
    }
}

/// Today's meals under Siri's answer.
struct TodaySnippet: View {
    let meals: [WidgetMeal]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if meals.isEmpty {
                Text("Nothing planned").font(.system(.headline, design: .serif))
                Text("Plan a meal in the Plan tab.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(meals) { meal in
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.mealTitle.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Text(meal.title).font(.system(.headline, design: .serif)).lineLimit(2)
                    if !meal.time.isEmpty { Text(meal.time).font(.caption).foregroundStyle(.secondary) }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

enum MealOption: String, AppEnum {
    case breakfast, lunch, dinner, snack
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Meal")
    static let caseDisplayRepresentations: [MealOption: DisplayRepresentation] = [
        .breakfast: "Breakfast", .lunch: "Lunch", .dinner: "Dinner", .snack: "Snack",
    ]
    var mealType: MealType { MealType(rawValue: rawValue) ?? .dinner }
}

struct PlanRecipeIntent: AppIntent {
    static let title: LocalizedStringResource = "Plan a Recipe"
    static let description = IntentDescription("Adds a recipe to your Spoonmate meal plan. Dinner unless you pick another meal.")
    static let openAppWhenRun = false

    @Parameter(title: "Recipe", requestValueDialog: "Which recipe?")
    var recipe: RecipeEntity

    @Parameter(title: "Day", requestValueDialog: "Which day?")
    var day: Date

    @Parameter(title: "Meal", default: .dinner)
    var meal: MealOption

    static var parameterSummary: some ParameterSummary { Summary("Plan \(\.$recipe) for \(\.$meal) on \(\.$day)") }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard AppServices.hasAccount else { return .result(dialog: Say.signedOut) }
        let when = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        do {
            let queued = try await IntentActions.plan(recipeID: recipe.id, date: day.apiDay, meal: meal.mealType, AppServices.session)
            let done = "Planned \(recipe.title) for \(meal.rawValue) on \(when)."
            return .result(dialog: Say.text(queued ? done + " You're offline; it's sent when you're back online." : done))
        } catch {
            return .result(dialog: Say.text("Couldn't plan \(recipe.title). \(error.localizedDescription)"))
        }
    }
}

// MARK: Recipes

/// Opens a recipe page. Also what Spotlight runs when you tap an indexed recipe.
struct OpenRecipeIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Recipe"
    static let description = IntentDescription("Opens a recipe in Spoonmate.")

    @Parameter(title: "Recipe", requestValueDialog: "Which recipe?")
    var target: RecipeEntity

    init() {}
    init(target: RecipeEntity) { self.target = target }

    @MainActor
    func perform() async throws -> some IntentResult {
        if AppServices.hasAccount { AppServices.app.handle(.recipe(target.id)) }
        return .result()
    }
}

/// Opens a recipe straight into cook mode (the recipe page presents it as soon as it has loaded).
struct CookRecipeIntent: AppIntent {
    static let title: LocalizedStringResource = "Cook a Recipe"
    static let description = IntentDescription("Opens a recipe in Spoonmate's cook mode, one step at a time.")
    static let openAppWhenRun = true

    @Parameter(title: "Recipe", requestValueDialog: "Which recipe?")
    var recipe: RecipeEntity

    init() {}
    init(recipe: RecipeEntity) { self.recipe = recipe }

    @MainActor
    func perform() async throws -> some IntentResult {
        if AppServices.hasAccount { AppServices.app.handle(.cook(recipe.id)) }
        return .result()
    }
}

// MARK: Timers

struct StartTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a Kitchen Timer"
    static let description = IntentDescription("Starts a Spoonmate kitchen timer. It rings like an alarm on iOS 26.1 and later, with a notification before that.")
    static let openAppWhenRun = false

    @Parameter(title: "Minutes", requestValueDialog: "For how many minutes?")
    var minutes: Int

    @Parameter(title: "Name")
    var name: String?

    static var parameterSummary: some ParameterSummary { Summary("Start a \(\.$minutes) minute timer named \(\.$name)") }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: Say.text(await IntentActions.startTimer(minutes: minutes, name: name ?? "")))
    }
}

/// The "+N min" button on a range timer's alarm ("Simmer 2–3 hours" starts at 2 hours and offers +60 min when it
/// rings). AlarmKit runs it in the app's process; it is not offered in Shortcuts.
struct ExtendKitchenTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Extend a Kitchen Timer"
    static let isDiscoverable = false
    static let openAppWhenRun = false

    @Parameter(title: "Alarm") var alarmID: String
    @Parameter(title: "Minutes") var minutes: Int
    @Parameter(title: "Name") var name: String
    @Parameter(title: "Recipe") var recipeTitle: String

    init() {}
    init(alarmID: String, minutes: Int, name: String, recipeTitle: String) {
        self.alarmID = alarmID; self.minutes = minutes; self.name = name; self.recipeTitle = recipeTitle
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        await AppServices.timer.extend(alarmID: id, minutes: minutes, name: name, recipeTitle: recipeTitle)
        return .result()
    }
}

/// Common lengths, so the length can be said in the same breath: "Start a 10 minute timer in Spoonmate".
/// (An App Shortcut phrase can only carry an entity or an enum, not a free number.)
enum TimerLength: Int, AppEnum {
    case one = 1, two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7, eight = 8, ten = 10, twelve = 12, fifteen = 15,
         twenty = 20, twentyFive = 25, thirty = 30, forty = 40, fortyFive = 45, sixty = 60, ninety = 90
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Timer length")
    static let caseDisplayRepresentations: [TimerLength: DisplayRepresentation] = [
        .one: DisplayRepresentation(title: "1 minute", synonyms: ["one minute"]),
        .two: DisplayRepresentation(title: "2 minute", synonyms: ["two minute"]),
        .three: DisplayRepresentation(title: "3 minute", synonyms: ["three minute"]),
        .four: DisplayRepresentation(title: "4 minute", synonyms: ["four minute"]),
        .five: DisplayRepresentation(title: "5 minute", synonyms: ["five minute"]),
        .six: DisplayRepresentation(title: "6 minute", synonyms: ["six minute"]),
        .seven: DisplayRepresentation(title: "7 minute", synonyms: ["seven minute"]),
        .eight: DisplayRepresentation(title: "8 minute", synonyms: ["eight minute"]),
        .ten: DisplayRepresentation(title: "10 minute", synonyms: ["ten minute"]),
        .twelve: DisplayRepresentation(title: "12 minute", synonyms: ["twelve minute"]),
        .fifteen: DisplayRepresentation(title: "15 minute", synonyms: ["fifteen minute", "quarter hour"]),
        .twenty: DisplayRepresentation(title: "20 minute", synonyms: ["twenty minute"]),
        .twentyFive: DisplayRepresentation(title: "25 minute", synonyms: ["twenty five minute"]),
        .thirty: DisplayRepresentation(title: "30 minute", synonyms: ["thirty minute", "half hour"]),
        .forty: DisplayRepresentation(title: "40 minute", synonyms: ["forty minute"]),
        .fortyFive: DisplayRepresentation(title: "45 minute", synonyms: ["forty five minute"]),
        .sixty: DisplayRepresentation(title: "60 minute", synonyms: ["sixty minute", "one hour", "an hour"]),
        .ninety: DisplayRepresentation(title: "90 minute", synonyms: ["ninety minute", "hour and a half"]),
    ]
}

struct QuickTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a Quick Kitchen Timer"
    static let description = IntentDescription("Starts a Spoonmate kitchen timer of a common length.")
    static let openAppWhenRun = false

    @Parameter(title: "Length", requestValueDialog: "How long?")
    var length: TimerLength

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: Say.text(await IntentActions.startTimer(minutes: length.rawValue, name: "")))
    }
}

// MARK: Shared actions

/// What the intents do, on the same paths the screens use.
@MainActor
enum IntentActions {
    enum Delivery { case sent, queued }

    /// The shopping list's add: sent now, or (offline) put on this phone's saved list and queued in the Outbox.
    static func addToShopping(_ name: String, _ session: Session) async throws -> Delivery {
        struct Body: Encodable, Sendable { let name: String }
        do {
            try await session.run { try await $0.send("POST", "/shopping/items", body: Body(name: name)) }
            // Re-read the list: saves it for offline use and refreshes the widget (OfflineStore → WidgetBridge).
            let _: ShoppingList? = try? await session.run { try await $0.get("/shopping") }
            return .sent
        } catch let error as APIError where error.isOffline {
            Outbox.shared.enqueue(.addShoppingItem(name: name, checked: false))
            if let client = session.client, let url = client.url("/shopping"),
               let data = await OfflineStore.shared.cached(for: url), var list: ShoppingList = try? client.decode(data) {
                list.items.insert(ShoppingItem(id: -Int.random(in: 1...Int.max / 2), name: name, checked: false, recipeId: nil,
                                               recipeTitle: nil, aisle: "Other", storeUrl: nil), at: 0)
                if let updated = try? APIClient.encoder.encode(list) { await OfflineStore.shared.store(updated, for: url) }
            }
            return .queued
        }
    }

    /// Today's meals: this week's plan from the server, or the saved copy offline, or the widget snapshot as a last resort.
    static func todaysMeals(_ session: Session, now: Date = .now) async -> [WidgetMeal] {
        let monday = MealPlanModel.monday(of: now)
        let sunday = MealPlanModel.calendar.date(byAdding: .day, value: 6, to: monday) ?? monday
        if let week: PlanWeek = try? await session.run({ try await $0.get("/mealplan", query: ["from": monday.apiDay, "to": sunday.apiDay]) }) {
            return PlanSnapshot(meals: week.entries.map { WidgetMeal($0, base: session.baseURL) }).meals(on: now)
        }
        return SnapshotStore.shared.plan?.meals(on: now) ?? []
    }

    /// Plans a recipe through the meal plan's own add (queued offline). True when it was queued.
    static func plan(recipeID: Int, date: String, meal: MealType, _ session: Session) async throws -> Bool {
        let detail: RecipeDetail
        if let saved = await OfflineStore.shared.allRecipes().first(where: { $0.id == recipeID }) { detail = saved }
        else { detail = try await session.run { try await $0.get("/recipes/\(recipeID)") } }
        let brief = RecipeBrief(id: detail.id, title: detail.title, description: detail.description, prepTime: detail.prepTime,
                                cookTime: detail.cookTime, servings: detail.servings, imageUrl: detail.imageUrl, thumbUrl: detail.thumbUrl)
        let entry = try await MealPlanModel.add(recipe: brief, date: date, mealType: meal, session)
        if entry.id > 0, let day = Date.fromAPIDay(date) {
            // Re-read that week so the saved copy and the Tonight widget include it.
            let monday = MealPlanModel.monday(of: day)
            let sunday = MealPlanModel.calendar.date(byAdding: .day, value: 6, to: monday) ?? monday
            let _: PlanWeek? = try? await session.run { try await $0.get("/mealplan", query: ["from": monday.apiDay, "to": sunday.apiDay]) }
        }
        return entry.id < 0
    }

    /// Starts a kitchen timer on the app's `CookTimer` and says what happened.
    static func startTimer(minutes: Int, name: String, timer: CookTimer = AppServices.timer) async -> String {
        guard (1...600).contains(minutes) else { return "Timers can run from 1 minute to 10 hours." }
        guard timer.canAddMore else { return "You already have \(CookTimer.maxTimers) timers running. Stop one in Spoonmate first." }
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = await timer.start(seconds: minutes * 60, name: label, recipeTitle: "") else { return "Couldn't start the timer." }
        if timer.permissionDenied {
            timer.cancel(id)
            return "Spoonmate isn't allowed to ring. Open Spoonmate and start a timer there once, or turn on Alarms or Notifications for it in Settings."
        }
        return label.isEmpty ? "Started a timer for \(duration(minutes))." : "Started \(label) for \(duration(minutes))."
    }

    /// "1 minute", "10 minutes", "1 hour", "2 hours", "90 minutes".
    nonisolated static func duration(_ minutes: Int) -> String {
        if minutes >= 60, minutes % 60 == 0 { return minutes == 60 ? "1 hour" : "\(minutes / 60) hours" }
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}
