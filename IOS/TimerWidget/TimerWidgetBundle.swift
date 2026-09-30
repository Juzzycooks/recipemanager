import SwiftUI
import WidgetKit

@main
struct TimerWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 26.1, *) {
            KitchenTimerLiveActivity()
        }
    }
}
