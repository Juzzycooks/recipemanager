import SwiftUI
import WidgetKit

/// "This week": today and the next six days, each with its dinner (or its first meal when no dinner is planned).
/// Today is highlighted. Tapping a day opens its recipe; an empty day opens the meal plan. Medium and large.
struct WeekPlanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.week, provider: WeekPlanProvider()) { entry in
            WeekPlanView(entry: entry)
        }
        .configurationDisplayName("This Week")
        .description("Dinner for today and the next six days.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct WeekPlanEntry: TimelineEntry, Sendable {
    let date: Date
    /// Nil when signed out.
    let days: [WidgetDay]?
}

struct WeekPlanProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekPlanEntry {
        WeekPlanEntry(date: .now, days: Self.sampleDays(from: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (WeekPlanEntry) -> Void) {
        if context.isPreview && SnapshotStore.shared.plan == nil { completion(placeholder(in: context)); return }
        completion(Self.entry(at: .now, plan: SnapshotStore.shared.plan))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<WeekPlanEntry>) -> Void) {
        Task {
            let now = Date.now
            let plan = WidgetLoader.isSignedIn ? await WidgetLoader.plan(now: now) : nil
            // Move on a day at midnight; otherwise check the server every hour or so.
            let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? now
            completion(Timeline(entries: [Self.entry(at: now, plan: plan)],
                                policy: .after(min(midnight.addingTimeInterval(60), now.addingTimeInterval(3600)))))
        }
    }

    static func entry(at now: Date, plan: PlanSnapshot?) -> WeekPlanEntry {
        guard WidgetLoader.isSignedIn else { return WeekPlanEntry(date: now, days: nil) }
        return WeekPlanEntry(date: now, days: (plan ?? PlanSnapshot(meals: [])).week(from: now))
    }

    static func sampleDays(from now: Date) -> [WidgetDay] {
        let titles = ["Lemon and herb roast chicken", nil, "Spinach and ricotta lasagne", "Chickpea curry", nil, "Fish tacos", "Mushroom risotto"]
        let meals = titles.enumerated().compactMap { i, title in
            title.map { WidgetMeal(id: i + 1, recipeID: i + 1, title: $0, date: PlanDay.key(daysFrom: now, i), mealType: "dinner",
                                   time: i == 0 ? "Cook 1 hr" : "", imageURL: nil) }
        }
        return PlanSnapshot(meals: meals).week(from: now)
    }
}

struct WeekPlanView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeekPlanEntry

    private var large: Bool { family == .systemLarge }

    var body: some View {
        Group {
            if let days = entry.days { content(days) } else { SignInPrompt() }
        }
        .containerBackground(for: .widget) { WidgetColors.background }
        .widgetURL(entry.days == nil ? nil : DeepLink.plan.url)
    }

    private func content(_ days: [WidgetDay]) -> some View {
        VStack(alignment: .leading, spacing: large ? 4 : 0) {
            if large {
                HStack(alignment: .firstTextBaseline) {
                    Text("This week").font(WidgetFonts.title(20)).foregroundStyle(WidgetColors.ink)
                    Spacer()
                    let planned = days.filter { $0.meal != nil }.count
                    Text("\(planned) of 7 planned").font(.caption.weight(.medium)).foregroundStyle(WidgetColors.accent).widgetAccentable()
                }
                .accessibilityElement(children: .combine)
                .padding(.bottom, 2)
            }
            ForEach(days) { day in
                Link(destination: day.meal.map { DeepLink.recipe($0.recipeID).url } ?? DeepLink.plan.url) { row(day) }
                if large && day.id != days.last?.id { Divider().overlay(WidgetColors.hairline) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Seven rows only just fit the medium widget; the largest text sizes would push days off the bottom.
        .dynamicTypeSize(...(large ? DynamicTypeSize.xxLarge : .large))
    }

    private func row(_ day: WidgetDay) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(weekday(day)).font((large ? Font.subheadline : .caption).weight(.semibold))
                .foregroundStyle(day.isToday ? WidgetColors.accent : WidgetColors.secondary)
                .widgetAccentable(day.isToday)
                .frame(width: large ? 44 : 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                if let meal = day.meal {
                    Text(meal.title).font(large ? WidgetFonts.title(16) : .caption.weight(day.isToday ? .semibold : .regular))
                        .foregroundStyle(WidgetColors.ink).lineLimit(1)
                    if large {
                        Text(detail(meal, others: day.others)).font(.caption2).foregroundStyle(WidgetColors.tertiary).lineLimit(1)
                    }
                } else {
                    Text("Nothing planned").font(large ? .subheadline : .caption).foregroundStyle(WidgetColors.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if !large && day.others > 0 {
                Text("+\(day.others)").font(.caption2).foregroundStyle(WidgetColors.tertiary)
            }
        }
        .padding(.vertical, large ? 3 : 0).padding(.horizontal, 6)
        .background {
            if day.isToday { RoundedRectangle(cornerRadius: 6).fill(WidgetColors.card) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(day))
    }

    /// "Today", "Thu"; the large widget adds the date: "Thu 6".
    private func weekday(_ day: WidgetDay) -> String {
        if day.isToday { return "Today" }
        guard let date = Self.date(day.date) else { return "" }
        return large ? date.formatted(.dateTime.weekday(.abbreviated).day()) : date.formatted(.dateTime.weekday(.abbreviated))
    }

    private func detail(_ meal: WidgetMeal, others: Int) -> String {
        let parts = [meal.mealTitle, meal.time.isEmpty ? nil : meal.time, others > 0 ? "+\(others) more" : nil]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private func accessibilityText(_ day: WidgetDay) -> String {
        let name = day.isToday ? "Today" : Self.date(day.date)?.formatted(.dateTime.weekday(.wide)) ?? day.date
        guard let meal = day.meal else { return "\(name): nothing planned" }
        return "\(name): \(meal.mealTitle), \(meal.title)" + (day.others > 0 ? ", and \(day.others) more" : "")
    }

    private static func date(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

#Preview("Medium", as: .systemMedium) {
    WeekPlanWidget()
} timeline: {
    WeekPlanEntry(date: .now, days: WeekPlanProvider.sampleDays(from: .now))
    WeekPlanEntry(date: .now, days: PlanSnapshot(meals: []).week(from: .now))
    WeekPlanEntry(date: .now, days: nil)
}

#Preview("Large", as: .systemLarge) {
    WeekPlanWidget()
} timeline: {
    WeekPlanEntry(date: .now, days: WeekPlanProvider.sampleDays(from: .now))
}
