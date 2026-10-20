import SwiftUI

struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if isLoading { ProgressView().tint(AppColors.onPrimary) }
                else if let systemImage { Image(systemName: systemImage) }
                Text(title).fontWeight(.semibold)
            }
            .foregroundStyle(AppColors.onPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(AppColors.primaryFill, in: RoundedRectangle(cornerRadius: Radius.control))
        }
        .buttonStyle(PressableStyle())
        .disabled(isLoading)
    }
}

/// Card stock with a hairline edge and ink text, as on the web, so the primary button stays the one accent fill.
struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).fontWeight(.semibold)
            }
            .foregroundStyle(AppColors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(AppColors.card, in: RoundedRectangle(cornerRadius: Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).stroke(AppColors.separator, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Pressable(label: configuration.label, isPressed: configuration.isPressed)
    }

    /// With Reduce Motion the press is only a dim, no scale.
    private struct Pressable<Label: View>: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let label: Label
        let isPressed: Bool

        var body: some View {
            label.opacity(isPressed ? 0.85 : 1).scaleEffect(isPressed && !reduceMotion ? 0.99 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isPressed)
        }
    }
}
