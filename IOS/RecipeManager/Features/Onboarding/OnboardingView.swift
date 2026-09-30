import SwiftUI

struct OnboardingView: View {
    @State private var showingSignIn = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: Spacing.xl)
                BotanicalIllustration().frame(width: 190, height: 190)
                    .padding(.bottom, Spacing.xl)
                Text("Your Recipes,\nYour Way")
                    .font(.system(.largeTitle, design: .serif, weight: .regular)).multilineTextAlignment(.center)
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.bottom, Spacing.s)
                Text("Save, organize, and cook\nthe meals you love.")
                    .font(.body).multilineTextAlignment(.center).foregroundStyle(AppColors.textSecondary)
                Spacer(minLength: Spacing.xl)
                VStack(spacing: Spacing.s) {
                    PrimaryButton(title: "Get Started") { showingSignIn = true }
                    Button("Sign In") { showingSignIn = true }
                        .font(.body.weight(.medium)).foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: Size.tap)
                }
                .padding(.bottom, Spacing.m)
            }
            .screenPadding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.background.ignoresSafeArea())
            .navigationDestination(isPresented: $showingSignIn) { SignInView() }
        }
    }
}
