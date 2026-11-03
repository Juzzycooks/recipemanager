import SwiftUI
import WidgetKit

/// "Tonight's dinner": today's planned dinner (photo, title, time). Tapping it opens the recipe; with nothing planned
/// it opens the Plan tab. Home Screen small and medium, and a Lock Screen rectangle.
struct TonightDinnerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.tonight, provider: TonightProvider()) { entry in
            TonightView(entry: entry)
        }
        .configurationDisplayName("Tonight's Dinner")
        .description("Today's planned dinner from your meal plan.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct TonightEntry: TimelineEntry, Sendable {
    enum Content: Sendable {
        case signedOut
        case nothingPlanned(others: [WidgetMeal])
        case dinner(WidgetMeal, picture: Data?, others: [WidgetMeal])
    }
    let date: Date
    let content: Content
}

struct TonightProvider: TimelineProvider {
    func placeholder(in context: Context) -> TonightEntry {
        TonightEntry(date: .now, content: .dinner(WidgetMeal(id: 0, recipeID: 3, title: "Lemon and herb roast chicken", date: "", mealType: "dinner",
                                                             time: "Cook 1 hr", imageURL: nil), picture: nil, others: []))
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (TonightEntry) -> Void) {
        if context.isPreview && !WidgetLoader.isSignedIn { completion(placeholder(in: context)); return }
        Task { completion(await Self.entry(at: .now, refresh: false)) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<TonightEntry>) -> Void) {
        Task {
            let now = Date.now
            let entry = await Self.entry(at: now, refresh: true)
            // Redraw at midnight (tomorrow's dinner) and otherwise check the server every hour or so.
            let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? now
            completion(Timeline(entries: [entry], policy: .after(min(midnight.addingTimeInterval(60), now.addingTimeInterval(3600)))))
        }
    }

    static func entry(at now: Date, refresh: Bool) async -> TonightEntry {
        guard WidgetLoader.isSignedIn else { return TonightEntry(date: now, content: .signedOut) }
        let plan = refresh ? await WidgetLoader.plan(now: now) : SnapshotStore.shared.plan
        let today = plan?.meals(on: now) ?? []
        guard let dinner = plan?.dinner(on: now) else { return TonightEntry(date: now, content: .nothingPlanned(others: today)) }
        return TonightEntry(date: now, content: .dinner(dinner, picture: await WidgetLoader.picture(for: dinner),
                                                         others: today.filter { $0.id != dinner.id }))
    }
}

struct TonightView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TonightEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { family == .accessoryRectangular ? Color.clear : WidgetColors.background }
            .widgetURL(link)
    }

    private var link: URL? {
        switch entry.content {
        case .signedOut: nil
        case .nothingPlanned: DeepLink.plan.url
        case .dinner(let meal, _, _): DeepLink.recipe(meal.recipeID).url
        }
    }

    @ViewBuilder private var content: some View {
        switch (family, entry.content) {
        case (.accessoryRectangular, _): lockScreen
        case (_, .signedOut): SignInPrompt()
        case (_, .nothingPlanned(let others)): empty(others)
        case (.systemMedium, .dinner(let meal, let picture, let others)): medium(meal, picture, others)
        case (_, .dinner(let meal, let picture, _)): small(meal, picture)
        }
    }

    // MARK: Home Screen

    private func small(_ meal: WidgetMeal, _ picture: Data?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MealPicture(meal: meal, image: picture)
                .frame(maxWidth: .infinity).frame(height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            eyebrow
            Text(meal.title).font(WidgetFonts.title(16)).foregroundStyle(WidgetColors.ink).lineLimit(2).minimumScaleFactor(0.85)
            if !meal.time.isEmpty { Text(meal.time).font(.caption2).foregroundStyle(WidgetColors.secondary).lineLimit(1) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(meal))
    }

    private func medium(_ meal: WidgetMeal, _ picture: Data?, _ others: [WidgetMeal]) -> some View {
        HStack(spacing: 14) {
            MealPicture(meal: meal, image: picture)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                eyebrow
                Text(meal.title).font(WidgetFonts.title(20, relativeTo: .title3)).foregroundStyle(WidgetColors.ink).lineLimit(3).minimumScaleFactor(0.8)
                if !meal.time.isEmpty { Text(meal.time).font(.caption).foregroundStyle(WidgetColors.secondary) }
                Spacer(minLength: 0)
                ForEach(others.prefix(2)) { other in
                    Text("\(other.mealTitle) · \(other.title)").font(.caption2).foregroundStyle(WidgetColors.tertiary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([label(meal)] + others.prefix(2).map { "\($0.mealTitle): \($0.title)" }).joined(separator: ". "))
    }

    private func empty(_ others: [WidgetMeal]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            eyebrow
            Text("Nothing planned").font(WidgetFonts.title(family == .systemMedium ? 20 : 17)).foregroundStyle(WidgetColors.ink)
            Text("Tap to plan tonight's dinner.").font(.caption).foregroundStyle(WidgetColors.secondary)
            Spacer(minLength: 0)
            if family == .systemMedium {
                ForEach(others.prefix(2)) { other in
                    Text("\(other.mealTitle) · \(other.title)").font(.caption2).foregroundStyle(WidgetColors.tertiary).lineLimit(1)
                }
            }
            Image(systemName: "calendar.badge.plus").font(.title3).foregroundStyle(WidgetColors.accent).widgetAccentable()
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tonight's dinner: nothing planned.")
        .accessibilityHint("Opens the meal plan")
    }

    private var eyebrow: some View {
        Text("TONIGHT").font(WidgetFonts.eyebrow).tracking(0.8).foregroundStyle(WidgetColors.accent).widgetAccentable()
    }

    private func label(_ meal: WidgetMeal) -> String {
        "Tonight's dinner: \(meal.title)" + (meal.time.isEmpty ? "" : ", \(meal.time)")
    }

    // MARK: Lock Screen

    @ViewBuilder private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Tonight", systemImage: "fork.knife").font(.caption.weight(.semibold)).widgetAccentable()
            switch entry.content {
            case .signedOut:
                Text("Sign in to Spoonmate").font(.headline).lineLimit(2)
            case .nothingPlanned:
                Text("Nothing planned").font(.headline).lineLimit(1)
                Text("Tap to plan dinner").font(.caption).foregroundStyle(.secondary)
            case .dinner(let meal, _, _):
                Text(meal.title).font(.system(.headline, design: .serif)).lineLimit(2)
                if !meal.time.isEmpty { Text(meal.time).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
