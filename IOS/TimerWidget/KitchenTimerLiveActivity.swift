import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

/// Lock Screen and Dynamic Island presentation of a kitchen timer (AlarmKit renders timers as Live Activities).
@available(iOS 26.1, *)
struct KitchenTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<TimerMetadata>.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "timer").font(.title2).foregroundStyle(context.attributes.tintColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.metadata?.recipeTitle ?? "Kitchen timer").font(.headline).lineLimit(1)
                    if let detail = context.attributes.metadata?.detail, !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                countdownText(context.state).font(.title.monospacedDigit().weight(.semibold)).foregroundStyle(context.attributes.tintColor)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.metadata?.recipeTitle ?? "Timer", systemImage: "timer").lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdownText(context.state).font(.title2.monospacedDigit().weight(.semibold)).foregroundStyle(context.attributes.tintColor)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let detail = context.attributes.metadata?.detail, !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
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

    @ViewBuilder private func countdownText(_ state: AlarmPresentationState) -> some View {
        if case .countdown(let countdown) = state.mode {
            Text(timerInterval: countdown.startDate...countdown.fireDate, countsDown: true)
        } else {
            Text("Time's up")
        }
    }
}
