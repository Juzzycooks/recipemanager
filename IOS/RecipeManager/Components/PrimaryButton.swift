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
            .background(AppColors.primary, in: RoundedRectangle(cornerRadius: Radius.field))
        }
        .buttonStyle(PressableStyle())
        .disabled(isLoading)
    }
}

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
            .foregroundStyle(AppColors.primary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: Radius.field))
        }
        .buttonStyle(PressableStyle())
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.85 : 1).scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
