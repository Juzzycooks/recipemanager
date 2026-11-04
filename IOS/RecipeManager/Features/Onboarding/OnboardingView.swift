import SwiftUI

/// First launch: the mark, the name as the heading, and one way on. Accounts come from the cook's own server,
/// so there is nothing to "get started" with apart from signing in.
struct OnboardingView: View {
    @State private var showingSignIn = false
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The mark gives way to the text at the largest sizes.
    private var markSize: CGFloat { typeSize.isAccessibilitySize ? 120 : 220 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: Spacing.xl)
                SpoonmateMark().frame(width: markSize, height: markSize)
                    .padding(.bottom, Spacing.xl)
                Text("Spoonmate").font(AppTypography.largeTitle)
                    .foregroundStyle(AppColors.textPrimary).accessibilityAddTraits(.isHeader)
                    .padding(.bottom, Spacing.xs)
                Text("Your recipes, your way.").font(AppTypography.note).foregroundStyle(AppColors.primary)
                    .padding(.bottom, Spacing.s)
                Text("Save, organize and cook the meals you love, from a server you run yourself.")
                    .font(.body).multilineTextAlignment(.center).foregroundStyle(AppColors.textSecondary)
                Spacer(minLength: Spacing.xl)
                PrimaryButton(title: "Sign in") { showingSignIn = true }
                    .accessibilityIdentifier("onboarding.signIn")
                    .padding(.bottom, Spacing.m)
            }
            .multilineTextAlignment(.center)
            .screenPadding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.background.ignoresSafeArea())
            .navigationDestination(isPresented: $showingSignIn) { SignInView() }
        }
    }
}
