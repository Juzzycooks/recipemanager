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
        .barBackground()
        .overlay(alignment: .top) { Rectangle().fill(AppColors.separator).frame(height: 0.5) }
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
