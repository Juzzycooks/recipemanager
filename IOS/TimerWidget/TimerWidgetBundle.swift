import SwiftUI
import WidgetKit

@main
struct TimerWidgetBundle: WidgetBundle {
    var body: some Widget {
        TonightDinnerWidget()
        ShoppingListWidget()
        if #available(iOS 26.1, *) {
            KitchenTimerLiveActivity()
        }
    }
}
