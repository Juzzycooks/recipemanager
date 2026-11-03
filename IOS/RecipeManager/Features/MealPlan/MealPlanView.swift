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
    private var shareUrl: String?

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
            entries = week.entries; shareUrl = week.shareUrl
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch { self.error = "Couldn't load this week's plan. \(error.localizedDescription)" }
    }

    /// Removes at once (queued when offline) and offers Undo, which puts the entry back.
    func remove(_ entry: PlanEntry, _ session: Session, _ app: AppState) async {
        withAnimation(.listChange) { entries.removeAll { $0.id == entry.id } }
        let offer = await app.offerUndo("Removed “\(entry.recipe.title)”") { await self.undoRemove(entry, session) }
        if entry.id < 0 {   // added offline, not sent yet
            Outbox.shared.cancelPlanAdd(localID: entry.id)
            await persist(session)
            return
        }
        do {
            _ = try await session.runOrQueue(.deletePlanEntry(entryID: entry.id)) { try await $0.send("DELETE", "/mealplan/\(entry.id)") }
            await persist(session)
        } catch {
            app.undo.withdraw(offer)
            self.error = "Couldn't remove “\(entry.recipe.title)” from the plan. \(error.localizedDescription)"
            await load(session)
        }
    }

    func undoRemove(_ entry: PlanEntry, _ session: Session) async {
        if entry.id > 0, Outbox.shared.cancelPlanDelete(entryID: entry.id) {   // the removal never left this phone
            withAnimation(.listChange) { entries.append(entry) }
            await persist(session)
            return
        }
        do {
            _ = try await Self.add(recipe: entry.recipe, date: entry.date, mealType: entry.mealType, session)
            await load(session)
        } catch { self.error = "Couldn't put “\(entry.recipe.title)” back. \(error.localizedDescription)" }
    }

    /// Moves an entry to another day of this week or another meal (queued when offline).
    func move(_ entry: PlanEntry, to day: String, mealType: MealType, _ session: Session) async {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        struct Body: Encodable, Sendable { let date: String; let mealType: String }
        withAnimation(.listChange) { entries[i] = PlanEntry(id: entry.id, date: day, mealType: mealType, recipe: entry.recipe) }
        if entry.id < 0 {
            Outbox.shared.movePlanAdd(localID: entry.id, date: day, mealType: mealType.rawValue)
            await persist(session)
            return
        }
        let body = Body(date: day, mealType: mealType.rawValue)
        do {
            _ = try await session.runOrQueue(.movePlanEntry(entryID: entry.id, date: day, mealType: mealType.rawValue)) {
                try await $0.send("PATCH", "/mealplan/\(entry.id)", body: body)
            }
            await persist(session)
        } catch { self.error = "Couldn't move “\(entry.recipe.title)”, so it's back where it was. \(error.localizedDescription)"; await load(session) }
    }

    /// Saves this week as it is now, so it shows your latest changes offline and after a relaunch.
    private func persist(_ session: Session) async {
        await Self.save(SavedWeek(from: weekStart.apiDay, to: lastDay.apiDay, entries: entries, shareUrl: shareUrl), session)
    }

    /// The shape of `GET /mealplan`, for writing the saved copy (`PlanWeek` only decodes).
    private struct SavedWeek: Encodable, Sendable { let from: String; let to: String; var entries: [PlanEntry]; let shareUrl: String? }

    private static func save(_ week: SavedWeek, _ session: Session) async {
        guard let client = session.client, let url = client.url("/mealplan", query: ["from": week.from, "to": week.to]),
              let data = try? APIClient.encoder.encode(week) else { return }
        await OfflineStore.shared.store(data, for: url)
    }

    /// Plans a recipe. Offline, it goes on this phone's copy of that week now (a temporary negative id) and is sent later.
    static func add(recipe: RecipeBrief, date: String, mealType: MealType, _ session: Session) async throws -> PlanEntry {
        struct Body: Encodable, Sendable { let recipeId: Int; let date: String; let mealType: String }
        let body = Body(recipeId: recipe.id, date: date, mealType: mealType.rawValue)
        do {
            let entry: PlanEntry = try await session.run { try await $0.send("POST", "/mealplan", body: body) }
            session.recipesChanged()
            return entry
        } catch let e as APIError where e.isOffline {
            let local = PlanEntry(id: -Int.random(in: 1...Int.max / 2), date: date, mealType: mealType, recipe: recipe)
            Outbox.shared.enqueue(.addPlanEntry(localID: local.id, recipeID: recipe.id, date: date, mealType: mealType.rawValue))
            if let client = session.client, let day = Date.dayFormatter.date(from: date) {
                let monday = monday(of: day)
                let sunday = calendar.date(byAdding: .day, value: 6, to: monday) ?? monday
                var saved: PlanWeek?
                if let url = client.url("/mealplan", query: ["from": monday.apiDay, "to": sunday.apiDay]),
                   let data = await OfflineStore.shared.cached(for: url) { saved = try? client.decode(data) }
                await save(SavedWeek(from: monday.apiDay, to: sunday.apiDay, entries: (saved?.entries ?? []) + [local], shareUrl: saved?.shareUrl), session)
            }
            session.recipesChanged()
            return local
        }
    }

    func addWeekToShopping(_ session: Session, _ app: AppState) async {
        struct Body: Encodable, Sendable { let from: String; let to: String }
        let body = Body(from: weekStart.apiDay, to: lastDay.apiDay)
        do {
            let counts: AddedCounts = try await session.run { try await $0.send("POST", "/mealplan/shopping", body: body) }
            app.say(counts.added == 0 ? "Nothing new to add." : "Added \(counts.added) ingredient\(counts.added == 1 ? "" : "s") to your list.")
        } catch { self.error = "Couldn't add this week's ingredients to your list. \(error.localizedDescription)" }
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
        catch { self.error = "Couldn't fill the empty dinners. \(error.localizedDescription)" }
    }
}

struct MealPlanView: View {
    @Environment(Session.self) private var session
    @Environment(AppState.self) private var app
    @State private var model = MealPlanModel()
    @State private var picking: PlanTarget?
    @ScaledMetric(relativeTo: .subheadline) private var dayColumn: CGFloat = 54
    @ScaledMetric(relativeTo: .body) private var thumbSize: CGFloat = 48

    struct PlanTarget: Identifiable { let day: Date; var id: TimeInterval { day.timeIntervalSinceReferenceDate } }

    var body: some View {
        // A plain List (styled as before) so entries get system swipe actions.
        List {
            weekSelector
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Spacing.xs, trailing: 0))
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            ForEach(model.days, id: \.self) { day in dayRows(day) }
        }
        .listStyle(.plain)
        .contentMargins(.bottom, Spacing.xl, for: .scrollContent)
        .appBackground()
        .navigationTitle("Meal plan")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Jump to this week", systemImage: "calendar") { model.goToThisWeek() }.disabled(model.isCurrentWeek)
                    Button("Add week to shopping list", systemImage: "cart.badge.plus") { Task { await model.addWeekToShopping(session, app) } }
                    Button("Fill empty dinners", systemImage: "wand.and.stars") { Task { await model.fillDinners(session, app) } }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Meal plan options")
            }
        }
        .bottomActionBar { PrimaryButton(title: "Plan a meal") { picking = PlanTarget(day: model.suggestedDay) } }
        .task(id: "\(model.weekStart.apiDay)#\(session.dataVersion)") { await model.load(session) }
        .refreshable { await model.load(session) }
        .sheet(item: $picking) { target in PlanRecipeSheet(initialDate: target.day) { await model.load(session) } }
        .errorAlert($model.error)
    }

    private var weekSelector: some View {
        HStack {
            Button { withAnimation(.listChange) { model.shift(-1) } } label: { Image(systemName: "chevron.left").frame(width: Size.tap, height: Size.tap) }
                .accessibilityLabel("Previous week")
            Spacer()
            Text(model.rangeTitle).font(.headline).foregroundStyle(AppColors.textPrimary).contentTransition(.numericText())
            Spacer()
            Button { withAnimation(.listChange) { model.shift(1) } } label: { Image(systemName: "chevron.right").frame(width: Size.tap, height: Size.tap) }
                .accessibilityLabel("Next week")
        }
        .foregroundStyle(AppColors.textPrimary).screenPadding()
    }

    /// One list row per planned meal; the day's name sits beside the first, and an empty day offers "Plan a meal".
    @ViewBuilder private func dayRows(_ day: Date) -> some View {
        let entries = model.entries(on: day)
        if entries.isEmpty {
            HStack(alignment: .top, spacing: Spacing.s) {
                dayLabel(day)
                Button { picking = PlanTarget(day: day) } label: {
                    HStack { Image(systemName: "plus"); Text("Plan a meal"); Spacer() }
                        .font(.subheadline).foregroundStyle(AppColors.textSecondary)
                        .padding(Spacing.s).frame(maxWidth: .infinity, minHeight: 56)
                        .background(AppColors.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.card))
                        .contentShape(RoundedRectangle(cornerRadius: Radius.card))
                }
                .buttonStyle(.plain).accessibilityLabel("Plan a meal for \(day.formatted(.dateTime.weekday(.wide)))")
            }
            .planRow(first: true)
        } else {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                HStack(alignment: .top, spacing: Spacing.s) {
                    if index == 0 { dayLabel(day) } else { Color.clear.frame(width: dayColumn, height: 1).accessibilityHidden(true) }
                    entryRow(entry)
                }
                .planRow(first: index == 0)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Remove", systemImage: "trash", role: .destructive) { Task { await model.remove(entry, session, app) } }
                }
            }
        }
    }

    private func dayLabel(_ day: Date) -> some View {
        let isToday = MealPlanModel.calendar.isDateInToday(day)
        return VStack(alignment: .leading, spacing: 0) {
            Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.subheadline.weight(.semibold))
                .foregroundStyle(isToday ? AppColors.primary : AppColors.textPrimary)
            Text(day.formatted(.dateTime.month(.abbreviated).day())).font(.caption).foregroundStyle(AppColors.textSecondary)
        }
        .frame(width: dayColumn, alignment: .leading).padding(.top, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()) + (isToday ? ", today" : ""))
    }

    private func entryRow(_ entry: PlanEntry) -> some View {
        // The link sits behind the card so the List doesn't add its own disclosure chevron.
        HStack(spacing: Spacing.s) {
            RecipeImage(path: entry.recipe.thumbUrl, title: entry.recipe.title, id: entry.recipe.id)
                .frame(width: thumbSize, height: thumbSize).clipShape(RoundedRectangle(cornerRadius: Radius.control)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.recipe.title).font(AppTypography.cardTitle).foregroundStyle(AppColors.textPrimary).lineLimit(2).multilineTextAlignment(.leading)
                Text(entry.mealType.title).font(.caption).foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.xs).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(AppColors.card, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(AppColors.separator, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Radius.card))
        .background { NavigationLink(value: AppRoute.recipe(entry.recipe.id)) { EmptyView() }.opacity(0) }
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
        .contextMenu {
            Menu("Move to another day", systemImage: "calendar") {
                ForEach(model.days.filter { $0.apiDay != entry.date }, id: \.self) { day in
                    Button(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) {
                        Task { await model.move(entry, to: day.apiDay, mealType: entry.mealType, session) }
                    }
                }
            }
            Menu("Change meal", systemImage: "fork.knife") {
                ForEach(MealType.allCases.filter { $0 != entry.mealType }) { meal in
                    Button(meal.title) { Task { await model.move(entry, to: entry.date, mealType: meal, session) } }
                }
            }
            Divider()
            Button("Remove from plan", systemImage: "trash", role: .destructive) { Task { await model.remove(entry, session, app) } }
        }
        .accessibilityAction(named: "Remove from plan") { Task { await model.remove(entry, session, app) } }
    }
}

extension Animation {
    /// The quick settle used when rows are added, removed or moved; none with Reduce Motion.
    @MainActor static var listChange: Animation? { UIAccessibility.isReduceMotionEnabled ? nil : .snappy }
}

private extension View {
    /// A meal-plan row: no separator or row background (the card draws itself), a little more space above a new day.
    func planRow(first: Bool) -> some View {
        listRowInsets(EdgeInsets(top: first ? Spacing.xs : Spacing.xxs, leading: Spacing.screen, bottom: Spacing.xxs, trailing: Spacing.screen))
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
    }
}

/// Pick a day, a meal and a recipe.
struct PlanRecipeSheet: View {
    @Environment(Session.self) private var session
    let initialDate: Date
    let onAdded: () async -> Void
    @State private var date: Date
    @State private var mealType = MealType.dinner
    @State private var error: String?

    init(initialDate: Date, onAdded: @escaping () async -> Void) {
        self.initialDate = initialDate; self.onAdded = onAdded
        _date = State(initialValue: initialDate)
    }

    var body: some View {
        RecipePickerSheet(title: "Plan a meal", header: {
            VStack(spacing: Spacing.s) {
                DatePicker("Day", selection: $date, displayedComponents: .date).padding(.horizontal, Spacing.m)
                Picker("Meal", selection: $mealType) { ForEach(MealType.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented).padding(.horizontal, Spacing.m)
            }
            .padding(.vertical, Spacing.xs)
        }, onPick: { recipe in
            let brief = RecipeBrief(id: recipe.id, title: recipe.title, description: recipe.description, prepTime: recipe.prepTime,
                                    cookTime: recipe.cookTime, servings: recipe.servings, imageUrl: recipe.imageUrl, thumbUrl: recipe.thumbUrl)
            do {
                _ = try await MealPlanModel.add(recipe: brief, date: date.apiDay, mealType: mealType, session)
                await onAdded()
                return true
            } catch {
                self.error = "Couldn't plan “\(recipe.title)”. \(error.localizedDescription)"
                return false
            }
        })
        .errorAlert($error)
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
        // The saved recipe gives the plan its picture and times (it answers offline too).
        let id = recipeId
        let detail: RecipeDetail? = try? await session.run { try await $0.get("/recipes/\(id)") }
        let recipe = RecipeBrief(id: recipeId, title: detail?.title ?? title, description: detail?.description ?? "",
                                 prepTime: detail?.prepTime ?? "", cookTime: detail?.cookTime ?? "", servings: detail?.servings ?? "",
                                 imageUrl: detail?.imageUrl ?? "", thumbUrl: detail?.thumbUrl ?? "")
        do {
            _ = try await MealPlanModel.add(recipe: recipe, date: date.apiDay, mealType: mealType, session)
            onAdded(); dismiss()
        } catch { self.error = "Couldn't add “\(title)” to your plan. \(error.localizedDescription)" }
    }
}
