import SwiftUI

/// Pill chip: card stock with a hairline edge, or the accent fill when selected. The pill is 38pt tall,
/// its tappable area the full 44pt.
struct FilterChip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            .foregroundStyle(isSelected ? AppColors.onPrimary : AppColors.textSecondary)
            .padding(.horizontal, Spacing.m).frame(minHeight: 38)
            .background(isSelected ? AppColors.primaryFill : AppColors.card, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.clear : AppColors.separator, lineWidth: 1))
            .padding(.vertical, (Size.tap - 38) / 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String? = "See all"
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
        .accessibilityHint(onRate == nil ? "" : "Choose a star to give your own rating.")
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
            Button { onRate(index) } label: { image.frame(minWidth: Size.tap, minHeight: Size.tap).contentShape(Rectangle()) }
                .buttonStyle(.plain).accessibilityLabel("\(index) star\(index == 1 ? "" : "s")")
                .accessibilityHint("Sets your rating")
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isFavorite: Bool
    var size: CGFloat = 20
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? "heart.fill" : "heart").font(.system(size: size))
                .foregroundStyle(isFavorite ? AppColors.favorite : AppColors.textSecondary)
                .symbolEffect(.bounce, value: isFavorite)
                .symbolEffectsRemoved(reduceMotion)
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

/// One line of a ruled ingredient list: a short terracotta dash, the text in Alegreya, a rule-blue line beneath.
/// Ticking means "I already have it": the dash becomes a terracotta tick and the line quietens.
struct IngredientRow: View {
    let text: String
    let isChecked: Bool
    let toggle: () -> Void
    /// Lifts the dash to the middle of the lower-case letters.
    @ScaledMetric(relativeTo: .body) private var dashLift: CGFloat = 5.5
    @ScaledMetric(relativeTo: .body) private var markWidth: CGFloat = 16

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                ZStack(alignment: .leading) {
                    if isChecked {
                        Image(systemName: "checkmark").font(.footnote.weight(.bold))
                    } else {
                        Capsule().frame(width: 9, height: 2)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + dashLift }
                    }
                }
                .foregroundStyle(AppColors.primary)
                .frame(width: markWidth, alignment: .leading)
                Text(text).font(AppTypography.reading)
                    .foregroundStyle(isChecked ? AppColors.textSecondary : AppColors.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, Spacing.xs).frame(minHeight: Size.tap).contentShape(Rectangle())
            .overlay(alignment: .bottom) { RuledLine() }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityValue(isChecked ? "Have it" : "")
        .accessibilityHint(isChecked ? "Double-tap if you still need it" : "Double-tap if you already have it")
        .accessibilityAddTraits(.isButton)
    }
}

/// The 1pt pale-blue rule between rows of a ruled list.
struct RuledLine: View {
    var body: some View { Rectangle().fill(AppColors.rule).frame(height: 1).accessibilityHidden(true) }
}

extension View {
    /// The title names what kind of failure it was (from `APIError`'s wording); the message keeps the detail.
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(errorAlertTitle(for: message.wrappedValue), isPresented: Binding(get: { message.wrappedValue != nil },
                                                           set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message.wrappedValue ?? "") }
    }

    /// Flour ground behind lists and forms.
    func appBackground() -> some View {
        scrollContentBackground(.hidden).background(AppColors.background)
    }

    /// The shared side margin.
    func screenPadding() -> some View { padding(.horizontal, Spacing.screen) }
}

/// Alert title for an error message: offline, unreachable, signed out, a garbled reply, or anything else.
private func errorAlertTitle(for message: String?) -> String {
    guard let message else { return "That didn't work" }
    if message.hasPrefix("You're offline") { return "You're offline" }
    if message.hasPrefix("Couldn't reach the server") { return "Can't reach the server" }
    if message.hasPrefix("You've been signed out") { return "Signed out" }
    if message.hasPrefix("The server sent something") { return "The server's reply didn't make sense" }
    return "That didn't work"
}

/// A vertical ScrollView whose content is exactly as wide as the screen and which never bounces sideways,
/// so a page can't be dragged aside to show blank space even if one child is too wide.
struct VerticalScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            content().containerRelativeFrame(.horizontal)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}
