import SwiftUI

/// Bottom navigation: Home, Search, [Add], Collections, Profile. Add is an action, not a tab.
struct AppTabBar: View {
    @Binding var selection: AppTab
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            item(.home)
            item(.search)
            addButton
            item(.collections)
            item(.profile)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.top, Spacing.xs)
        .background(alignment: .top) {
            // Behind the buttons, so the hairline can never cross the raised Add button.
            ZStack(alignment: .top) {
                AppColors.background.shadow(color: .black.opacity(0.06), radius: 6, y: -1)
                Rectangle().fill(AppColors.separator).frame(height: 0.5)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func item(_ tab: AppTab) -> some View {
        let selected = selection == tab
        return Button {
            withAnimation(.snappy) { selection = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: selected ? tab.selectedSymbol : tab.symbol).font(.system(size: 21)).frame(height: 26)
                Text(tab.title).font(.caption2.weight(selected ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? AppColors.primary : AppColors.textSecondary)
            .frame(maxWidth: .infinity, minHeight: Size.tap + 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus").font(.system(size: 24, weight: .semibold)).foregroundStyle(AppColors.onPrimary)
                .frame(width: Size.addButton, height: Size.addButton)
                .background(AppColors.primary, in: Circle())
                .shadow(color: AppColors.primary.opacity(0.3), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .offset(y: -14)
        .frame(maxWidth: .infinity, minHeight: Size.tap + 6)
        .accessibilityLabel("Add recipe")
    }
}

extension View {
    /// Puts the tab bar at the bottom of a tab's root screen. It belongs to the screen (not to the shell around the
    /// stack), so pushing a recipe slides it away together with the screen instead of resizing everything underneath.
    func withAppTabBar() -> some View { modifier(AppTabBarInset()) }
}

private struct AppTabBarInset: ViewModifier {
    @Environment(AppState.self) private var app
    @State private var keyboardVisible = false

    func body(content: Content) -> some View {
        @Bindable var app = app
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !keyboardVisible { AppTabBar(selection: $app.tab) { app.showingAdd = true } }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
    }
}

/// Round Home button for pushed screens: jumps straight back to the Home tab from anywhere.
struct HomeButton: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Button { app.goHome() } label: {
            Image(systemName: "house.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(AppColors.primary)
                .frame(width: 52, height: 52)
                .background(AppColors.card, in: Circle())
                .overlay(Circle().stroke(AppColors.separator, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 1)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Home")
    }
}

extension View {
    /// Home button alone in the bottom-left, for pushed screens with no bottom action.
    func homeBar() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            HStack { HomeButton(); Spacer() }.screenPadding().padding(.vertical, Spacing.s)
        }
    }

    /// Home button beside the screen's bottom action, on the usual bar.
    func homeBar<Action: View>(@ViewBuilder action: () -> Action) -> some View {
        let action = action()
        return safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: Spacing.s) { HomeButton(); action }
                .screenPadding().padding(.vertical, Spacing.s)
                .barBackground()
        }
    }
}
