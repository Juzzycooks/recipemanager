import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

/// Lock Screen and Dynamic Island presentation of a kitchen timer (AlarmKit renders timers as Live Activities).
/// Each running timer is its own activity, so several timers stack on the Lock Screen and the system picks
/// which one the Dynamic Island shows. The metadata's `detail` is the timer's name ("Pasta"), `recipeTitle` the recipe.
@available(iOS 26.1, *)
struct KitchenTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<TimerMetadata>.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "timer").font(.title2).foregroundStyle(context.attributes.tintColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name(context.attributes.metadata)).font(.headline).lineLimit(1)
                    if let recipe = recipe(context.attributes.metadata) {
                        Text(recipe).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                countdownText(context.state).font(.title.monospacedDigit().weight(.semibold)).foregroundStyle(context.attributes.tintColor)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(name(context.attributes.metadata), systemImage: "timer").lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdownText(context.state).font(.title2.monospacedDigit().weight(.semibold)).foregroundStyle(context.attributes.tintColor)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let recipe = recipe(context.attributes.metadata) {
                        Text(recipe).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                countdownText(context.state).monospacedDigit().frame(maxWidth: 52).foregroundStyle(context.attributes.tintColor)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(context.attributes.tintColor)
            }
            .keylineTint(context.attributes.tintColor)
        }
    }

    /// The timer's own name, falling back to the recipe for timers scheduled before timers had names.
    private func name(_ metadata: TimerMetadata?) -> String {
        if let detail = metadata?.detail, !detail.isEmpty, detail.count <= 40 { return detail }
        return metadata?.recipeTitle ?? "Kitchen timer"
    }

    private func recipe(_ metadata: TimerMetadata?) -> String? {
        guard let title = metadata?.recipeTitle, !title.isEmpty, title != name(metadata) else { return nil }
        return title
    }

    @ViewBuilder private func countdownText(_ state: AlarmPresentationState) -> some View {
        if case .countdown(let countdown) = state.mode {
            Text(timerInterval: countdown.startDate...countdown.fireDate, countsDown: true)
        } else {
            Text("Time's up")
        }
    }
}
