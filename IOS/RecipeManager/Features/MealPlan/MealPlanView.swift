import SwiftUI

@MainActor @Observable
final class MealPlanModel {
    static let calendar: Calendar = { var c = Calendar(identifier: .iso8601); c.timeZone = .current; return c }()

    static func monday(of date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
    }

    var weekStart = MealPlanModel.monday(of: .now)
    var entries: [PlanEntry] = []
    var error: String?

    var days: [Date] { (0..<7).compactMap { Self.calendar.date(byAdding: .day, value: $0, to: weekStart) } }
    var lastDay: Date { Self.calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart }
    var isCurrentWeek: Bool { Self.calendar.isDate(weekStart, inSameDayAs: Self.monday(of: .now)) }

    var rangeTitle: String {
        let start = weekStart.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(lastDay.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    func entries(on day: Date) -> [PlanEntry] {
        let key = day.apiDay, order = MealType.allCases
        return entries.filter { $0.date == key }.sorted { (order.firstIndex(of: $0.mealType) ?? 0) < (order.firstIndex(of: $1.mealType) ?? 0) }
    }

    /// Today if it's free this week, otherwise the first empty day, otherwise today.
    var suggestedDay: Date {
        let free = days.first { entries(on: $0).isEmpty && $0 >= Self.calendar.startOfDay(for: .now) }
        return free ?? (days.contains { Self.calendar.isDateInToday($0) } ? .now : weekStart)
    }

    func shift(_ weeks: Int) { weekStart = Self.calendar.date(byAdding: .weekOfYear, value: weeks, to: weekStart) ?? weekStart }
    func goToThisWeek() { weekStart = Self.monday(of: .now) }

    func load(_ session: Session) async {
        let from = weekStart.apiDay, to = lastDay.apiDay
        do {
            let week: PlanWeek = try await session.run { try await $0.get("/mealplan", query: ["from": from, "to": to]) }
            entries = week.entries
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch { self.error = error.localizedDescription }
    }

    func remove(_ entry: PlanEntry, _ session: Session) async {
        entries.removeAll { $0.id == entry.id }
        do { try await session.run { try await $0.send("DELETE", "/mealplan/\(entry.id)") } }
        catch { self.error = error.localizedDescription; await load(session) }
    }

    func addWeekToShopping(_ session: Session, _ app: AppState) async {
        struct Body: Encodable, Sendable { let from: String; let to: String }
        let body = Body(from: weekStart.apiDay, to: lastDay.apiDay)
        do {
            let counts: AddedCounts = try await session.run { try await $0.send("POST", "/mealplan/shopping", body: body) }
            app.say(counts.added == 0 ? "Nothing new to add." : "Added \(counts.added) ingredient\(counts.added == 1 ? "" : "s") to your list.")
        } catch { self.error = error.localizedDescription }
    }

    func fillDinners(_ session: Session, _ app: AppState) async {
        struct Body: Encodable, Sendable { let week: Int; let mealTypes: [String] }
        struct Result: Decodable, Sendable { let added: Int }
        let offset = Self.calendar.dateComponents([.weekOfYear], from: Self.monday(of: .now), to: weekStart).weekOfYear ?? 0
        do {
            let result: Result = try await session.run { try await $0.send("POST", "/mealplan/auto-generate", body: Body(week: offset, mealTypes: ["dinner"])) }
            app.say(result.added == 0 ? "Every dinner is already planned." : "Planned \(result.added) dinner\(result.added == 1 ? "" : "s").")
            await load(session)
        } catch let APIError.server(_, code, message) where code == "no_recipes" { app.say(message) }
        catch { self.error = error.localizedDescription }
    }
}

struct MealPlanView: View {
    @Environment(Session.self) private var session
    @Environment(AppState.self) private var app
    @State private var model = MealPlanModel()
    @State private var picking: PlanTarget?

    struct PlanTarget: Identifiable { let day: Date; var id: TimeInterval { day.timeIntervalSinceReferenceDate } }

    var body: some View {
        VerticalScroll {
            VStack(spacing: Spacing.m) {
                weekSelector
                VStack(spacing: Spacing.s) {
                    ForEach(model.days, id: \.self) { day in dayRow(day) }
                }
                .screenPadding()
            }
            .padding(.bottom, Spacing.xl)
        }
        .background(AppColors.background)
        .navigationTitle("Meal Plan")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Jump to this week", systemImage: "calendar") { model.goToThisWeek() }.disabled(model.isCurrentWeek)
                    Button("Add week to shopping list", systemImage: "cart.badge.plus") { Task { await model.addWeekToShopping(session, app) } }
                    Button("Fill empty dinners", systemImage: "wand.and.stars") { Task { await model.fillDinners(session, app) } }
                } label: { Image(systemName: "calendar") }.accessibilityLabel("Meal plan options")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PrimaryButton(title: "Plan a Meal") { picking = PlanTarget(day: model.suggestedDay) }
                .screenPadding().padding(.vertical, Spacing.s)
                .barBackground()
        }
        .hidesAppTabBar()
        .task(id: "\(model.weekStart.apiDay)#\(session.dataVersion)") { await model.load(session) }
        .refreshable { await model.load(session) }
        .sheet(item: $picking) { target in PlanRecipeSheet(initialDate: target.day) { await model.load(session) } }
        .errorAlert($model.error)
    }

    private var weekSelector: some View {
        HStack {
            Button { withAnimation { model.shift(-1) } } label: { Image(systemName: "chevron.left").frame(width: Size.tap, height: Size.tap) }
                .accessibilityLabel("Previous week")
            Spacer()
            Text(model.rangeTitle).font(.headline).foregroundStyle(AppColors.textPrimary).contentTransition(.numericText())
            Spacer()
            Button { withAnimation { model.shift(1) } } label: { Image(systemName: "chevron.right").frame(width: Size.tap, height: Size.tap) }
                .accessibilityLabel("Next week")
        }
        .foregroundStyle(AppColors.textPrimary).screenPadding()
    }

    private func dayRow(_ day: Date) -> some View {
        let entries = model.entries(on: day)
        let isToday = MealPlanModel.calendar.isDateInToday(day)
        return HStack(alignment: .top, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 0) {
                Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.subheadline.weight(.semibold))
                    .foregroundStyle(isToday ? AppColors.primary : AppColors.textPrimary)
                Text(day.formatted(.dateTime.month(.abbreviated).day())).font(.caption).foregroundStyle(AppColors.textSecondary)
            }
            .frame(width: 54, alignment: .leading).padding(.top, Spacing.xs)
            .accessibilityElement(children: .combine)
            VStack(spacing: Spacing.xs) {
                ForEach(entries) { entry in entryRow(entry) }
                if entries.isEmpty {
                    Button { picking = PlanTarget(day: day) } label: {
                        HStack { Image(systemName: "plus"); Text("Plan a meal"); Spacer() }
                            .font(.subheadline).foregroundStyle(AppColors.textSecondary)
                            .padding(Spacing.s).frame(maxWidth: .infinity, minHeight: 56)
                            .background(AppColors.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.field))
                    }
                    .buttonStyle(.plain).accessibilityLabel("Plan a meal for \(day.formatted(.dateTime.weekday(.wide)))")
                }
            }
        }
    }

    private func entryRow(_ entry: PlanEntry) -> some View {
        NavigationLink(value: AppRoute.recipe(entry.recipe.id)) {
            HStack(spacing: Spacing.s) {
                RecipeImage(path: entry.recipe.thumbUrl, title: entry.recipe.title, id: entry.recipe.id)
                    .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: Radius.small)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.recipe.title).font(AppTypography.cardTitle).foregroundStyle(AppColors.textPrimary).lineLimit(2).multilineTextAlignment(.leading)
                    Text(entry.mealType.title).font(.caption).foregroundStyle(AppColors.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.xs).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(AppColors.card, in: RoundedRectangle(cornerRadius: Radius.field))
            .overlay(RoundedRectangle(cornerRadius: Radius.field).stroke(AppColors.separator, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .contextMenu { Button("Remove from plan", systemImage: "trash", role: .destructive) { Task { await model.remove(entry, session) } } }
        .accessibilityAction(named: "Remove from plan") { Task { await model.remove(entry, session) } }
    }
}

/// Pick a day, a meal and a recipe.
struct PlanRecipeSheet: View {
    @Environment(Session.self) private var session
    let initialDate: Date
    let onAdded: () async -> Void
    @State private var date: Date
    @State private var mealType = MealType.dinner

    init(initialDate: Date, onAdded: @escaping () async -> Void) {
        self.initialDate = initialDate; self.onAdded = onAdded
        _date = State(initialValue: initialDate)
    }

    var body: some View {
        RecipePickerSheet(title: "Plan a Meal", header: {
            VStack(spacing: Spacing.s) {
                DatePicker("Day", selection: $date, displayedComponents: .date).padding(.horizontal, Spacing.m)
                Picker("Meal", selection: $mealType) { ForEach(MealType.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented).padding(.horizontal, Spacing.m)
            }
            .padding(.vertical, Spacing.xs)
        }, onPick: { recipe in
            struct Body: Encodable, Sendable { let recipeId: Int; let date: String; let mealType: String }
            let body = Body(recipeId: recipe.id, date: date.apiDay, mealType: mealType.rawValue)
            do {
                let _: PlanEntry = try await session.run { try await $0.send("POST", "/mealplan", body: body) }
                session.recipesChanged()
                await onAdded()
                return true
            } catch { return false }
        })
    }
}

/// Add one recipe to the plan from its own page.
struct AddToPlanSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let recipeId: Int
    let title: String
    let onAdded: () -> Void

    @State private var date = Date.now
    @State private var mealType = MealType.dinner
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Day", selection: $date, displayedComponents: .date).datePickerStyle(.graphical)
                Picker("Meal", selection: $mealType) { ForEach(MealType.allCases) { Text($0.title).tag($0) } }
            }
            .appBackground()
            .navigationTitle("Plan “\(title)”").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { Task { await add() } } }
            }
            .errorAlert($error)
        }
        .presentationDetents([.large])
    }

    private func add() async {
        struct Body: Encodable, Sendable { let recipeId: Int; let date: String; let mealType: String }
        let body = Body(recipeId: recipeId, date: date.apiDay, mealType: mealType.rawValue)
        do {
            let _: PlanEntry = try await session.run { try await $0.send("POST", "/mealplan", body: body) }
            session.recipesChanged(); onAdded(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
