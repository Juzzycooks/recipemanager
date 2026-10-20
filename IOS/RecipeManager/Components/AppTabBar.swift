import SwiftUI

// The app uses the system TabView and tab bar (RootView). What's left here is the pinned bottom action bar
// for screens with one real bottom action: recipe detail's Start cooking, the shopping list, the meal plan.

extension View {
    /// Pins the screen's main action to the bottom, above the system tab bar. On iOS 26 it's a safe-area bar, so
    /// content scrolling under it gets the system edge effect; earlier, a flour bar that stops at the tab bar.
    func bottomActionBar<Action: View>(@ViewBuilder action: () -> Action) -> some View {
        modifier(BottomActionBar(action: action()))
    }
}

private struct BottomActionBar<Action: View>: ViewModifier {
    let action: Action

    func body(content: Content) -> some View {
        let bar = HStack(spacing: Spacing.s) { action }
            .screenPadding().padding(.vertical, Spacing.s)
        if #available(iOS 26, *) {
            content.safeAreaBar(edge: .bottom, spacing: 0) { bar }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                // No ignoresSafeArea: the flour must not run on behind the system tab bar.
                bar.background(AppColors.background.shadow(color: .black.opacity(0.06), radius: 6, y: -1))
            }
        }
    }
}
