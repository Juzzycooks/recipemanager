import AppIntents
import SwiftUI
import WidgetKit

/// "Shopping list": unticked items grouped by aisle, each with a tick button (an App Intent, so it works without
/// opening the app). Medium and large.
struct ShoppingListWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.shopping, provider: ShoppingProvider()) { entry in
            ShoppingWidgetView(entry: entry)
        }
        .configurationDisplayName("Shopping List")
        .description("What's left to buy. Tick items off right here.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ShoppingEntry: TimelineEntry, Sendable {
    let date: Date
    /// Nil when signed out.
    let list: ShoppingSnapshot?
    let signedIn: Bool
}

struct ShoppingProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShoppingEntry {
        let items = [("Milk", "Dairy"), ("Lemons", "Produce"), ("Coriander", "Produce"), ("Chickpeas", "Pantry"), ("Feta", "Dairy")]
        return ShoppingEntry(date: .now, list: ShoppingSnapshot(aisleOrder: ["Produce", "Dairy", "Pantry"], items: items.enumerated().map {
            WidgetShoppingItem(id: $0.offset + 1, name: $0.element.0, aisle: $0.element.1, checked: false)
        }), signedIn: true)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (ShoppingEntry) -> Void) {
        let store = SnapshotStore.shared
        if context.isPreview && store.shopping == nil { completion(placeholder(in: context)); return }
        completion(ShoppingEntry(date: .now, list: store.shopping?.applying(store.pendingTicks), signedIn: WidgetLoader.isSignedIn))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<ShoppingEntry>) -> Void) {
        Task {
            let signedIn = WidgetLoader.isSignedIn
            let list = signedIn ? await WidgetLoader.shopping() : nil
            completion(Timeline(entries: [ShoppingEntry(date: .now, list: list, signedIn: signedIn)], policy: .after(.now.addingTimeInterval(30 * 60))))
        }
    }
}

struct ShoppingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ShoppingEntry

    private var large: Bool { family == .systemLarge }

    var body: some View {
        Group {
            if !entry.signedIn { SignInPrompt() } else { content }
        }
        .containerBackground(for: .widget) { WidgetColors.background }
        .widgetURL(entry.signedIn ? DeepLink.shopping.url : nil)
    }

    @ViewBuilder private var content: some View {
        let list = entry.list ?? ShoppingSnapshot(aisleOrder: [], items: [])
        VStack(alignment: .leading, spacing: large ? 6 : 4) {
            header(list)
            if list.openCount == 0 {
                Spacer(minLength: 0)
                Text(entry.list == nil ? "Open Spoonmate to load your list." : list.items.isEmpty ? "Your list is empty." : "All ticked off.")
                    .font(.subheadline).foregroundStyle(WidgetColors.secondary)
                Spacer(minLength: 0)
            } else {
                let layout = list.widgetRows(lines: large ? 13 : 6, headings: large)
                if large {
                    ForEach(layout.rows, id: \.self) { row(for: $0) }
                } else {
                    // Two columns of three on the medium widget, no aisle headings.
                    let items = layout.rows.compactMap { if case .item(let item) = $0 { item } else { nil } }
                    HStack(alignment: .top, spacing: 10) {
                        column(Array(items.prefix(3)))
                        column(Array(items.dropFirst(3)))
                    }
                }
                Spacer(minLength: 0)
                if layout.hidden > 0 {
                    Text("\(layout.hidden) more").font(.caption2).foregroundStyle(WidgetColors.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(_ list: ShoppingSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Shopping list").font(WidgetFonts.title(large ? 20 : 17)).foregroundStyle(WidgetColors.ink)
            Spacer()
            if list.openCount > 0 {
                Text("\(list.openCount) to buy").font(.caption.weight(.medium)).foregroundStyle(WidgetColors.accent).widgetAccentable()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func column(_ items: [WidgetShoppingItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) { ForEach(items) { itemRow($0) } }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func row(for row: ShoppingSnapshot.Row) -> some View {
        switch row {
        case .aisle(let name):
            Text(name.uppercased()).font(WidgetFonts.eyebrow).tracking(0.6).foregroundStyle(WidgetColors.secondary)
                .padding(.top, 2).accessibilityAddTraits(.isHeader)
        case .item(let item):
            itemRow(item)
        }
    }

    private func itemRow(_ item: WidgetShoppingItem) -> some View {
        Button(intent: TickShoppingItemIntent(itemID: item.id, name: item.name)) {
            HStack(spacing: 6) {
                Image(systemName: "circle").font(.body).foregroundStyle(WidgetColors.accent).widgetAccentable()
                Text(item.name).font(.subheadline).foregroundStyle(WidgetColors.ink).lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.name)
        .accessibilityHint("Ticks it off the shopping list")
    }
}
