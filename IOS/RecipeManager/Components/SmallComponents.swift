import SwiftUI

struct FilterChip: View {
    let title: String
    var isSelected = false
    var showsChevron = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(AppTypography.label)
                if showsChevron { Image(systemName: "chevron.down").font(.caption2.weight(.bold)) }
            }
            .foregroundStyle(isSelected ? AppColors.onPrimary : AppColors.textPrimary)
            .padding(.horizontal, Spacing.m).frame(minHeight: 36)
            .background(isSelected ? AppColors.primary : AppColors.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String? = "See All"
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(AppTypography.title3).foregroundStyle(AppColors.textPrimary).accessibilityAddTraits(.isHeader)
            Spacer()
            if let action, let actionTitle {
                Button(actionTitle, action: action).font(.subheadline).foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(.horizontal, Spacing.screen)
    }
}

struct SearchBar: View {
    @Binding var text: String
    var prompt = "Search recipes, ingredients, or tags..."
    var focus: FocusState<Bool>.Binding?
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppColors.textSecondary)
            field
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(AppColors.textSecondary) }
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Spacing.s).frame(minHeight: 46)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: Radius.field))
    }

    @ViewBuilder private var field: some View {
        let base = TextField(prompt, text: $text).submitLabel(.search).onSubmit(onSubmit)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
        if let focus { base.focused(focus) } else { base }
    }
}

/// A search field that is really a button (Home): tapping opens the Search tab.
struct SearchBarButton: View {
    var prompt = "Search recipes, ingredients, or tags..."
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "magnifyingglass")
                Text(prompt).lineLimit(1)
                Spacer()
            }
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, Spacing.s).frame(minHeight: 46)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: Radius.field))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search recipes")
    }
}

struct RatingView: View {
    let rating: Double?
    var count: Int = 0
    /// Set to make the stars tappable (your own rating).
    var onRate: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in starView(index: star) }
            if let rating {
                Text(String(format: "%.1f", rating) + (count > 0 ? " (\(count))" : ""))
                    .font(.footnote).foregroundStyle(AppColors.textSecondary).padding(.leading, Spacing.xxs)
            } else if onRate == nil {
                Text("Not rated").font(.footnote).foregroundStyle(AppColors.textSecondary)
            }
        }
        .accessibilityElement(children: onRate == nil ? .ignore : .contain)
        .accessibilityLabel(rating.map { "Rated \(String(format: "%.1f", $0)) out of 5" } ?? "Not rated")
    }

    private func symbol(for index: Int) -> String {
        let value = rating ?? 0
        if value >= Double(index) - 0.25 { return "star.fill" }
        if value >= Double(index) - 0.75 { return "star.leadinghalf.filled" }
        return "star"
    }

    @ViewBuilder private func starView(index: Int) -> some View {
        let name = symbol(for: index)
        let image = Image(systemName: name).font(.subheadline)
            .foregroundStyle(name == "star" ? AppColors.textSecondary.opacity(0.6) : AppColors.star)
        if let onRate {
            Button { onRate(index) } label: { image.frame(minWidth: 32, minHeight: Size.tap) }
                .buttonStyle(.plain).accessibilityLabel("\(index) star\(index == 1 ? "" : "s")")
        } else {
            image
        }
    }
}

struct MetaItem: View {
    let systemImage: String
    let text: String
    var body: some View {
        Label(text, systemImage: systemImage).font(.subheadline).foregroundStyle(AppColors.textSecondary).lineLimit(1)
    }
}

struct FavoriteButton: View {
    let isFavorite: Bool
    var size: CGFloat = 20
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? "heart.fill" : "heart").font(.system(size: size))
                .foregroundStyle(isFavorite ? AppColors.favorite : AppColors.textSecondary)
                .symbolEffect(.bounce, value: isFavorite)
                .frame(minWidth: Size.tap, minHeight: Size.tap).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage).foregroundStyle(AppColors.textPrimary)
        } description: {
            if let message { Text(message) }
        } actions: {
            if let action, let actionTitle { Button(actionTitle, action: action).buttonStyle(.borderedProminent) }
        }
    }
}

struct IngredientRow: View {
    let text: String
    let isChecked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square").font(.title3)
                    .foregroundStyle(isChecked ? AppColors.primary : AppColors.textSecondary)
                Text(text).font(AppTypography.reading).foregroundStyle(AppColors.textPrimary).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, Spacing.xs).frame(minHeight: Size.tap).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(isChecked ? [.isButton, .isSelected] : .isButton)
    }
}

extension View {
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert("Something went wrong", isPresented: Binding(get: { message.wrappedValue != nil },
                                                           set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message.wrappedValue ?? "") }
    }

    /// Cream ground behind lists and forms.
    func appBackground() -> some View {
        scrollContentBackground(.hidden).background(AppColors.background)
    }

    /// Cream bar with a hairline shadow, for pinned bottom actions and the tab bar.
    func barBackground() -> some View {
        background {
            AppColors.background.shadow(color: .black.opacity(0.06), radius: 6, y: -1).ignoresSafeArea(edges: .bottom)
        }
    }

    /// The shared side margin.
    func screenPadding() -> some View { padding(.horizontal, Spacing.screen) }
}
