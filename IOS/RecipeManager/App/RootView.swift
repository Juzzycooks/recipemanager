import SwiftUI

struct RootView: View {
    @Environment(Session.self) private var session

    var body: some View {
        Group {
            if session.isSignedIn {
                MainView()
            } else if session.isRestoring {
                ProgressView("Signing in…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(AppColors.background)
            } else if session.offlineRestore {
                ContentUnavailableView {
                    Label("Can't reach the server", systemImage: "wifi.slash")
                } description: {
                    Text("You're still signed in. Check your connection and try again.")
                } actions: {
                    Button("Try again") { Task { await session.retryRestore() } }.buttonStyle(.borderedProminent)
                }
                .background(AppColors.background)
            } else {
                OnboardingView()
            }
        }
        .animation(.default, value: session.isSignedIn)
    }
}

/// The five-slot layout from the design: four tabs around a raised Add button.
struct MainView: View {
    @Environment(Session.self) private var session
    @Environment(AppState.self) private var app
    @Environment(CookTimer.self) private var timer
    @State private var keyboardVisible = false

    var body: some View {
        @Bindable var app = app
        // The bar sits below the content in a stack (not as a safe-area inset), so every screen's scroll
        // view ends above it and its last row can always be reached.
        VStack(spacing: 0) {
            TabView(selection: $app.tab) {
                Tab(AppTab.home.title, systemImage: AppTab.home.symbol, value: AppTab.home) { HomeView() }
                Tab(AppTab.search.title, systemImage: AppTab.search.symbol, value: AppTab.search) { SearchView() }
                Tab(AppTab.collections.title, systemImage: AppTab.collections.symbol, value: AppTab.collections) { CollectionsView() }
                Tab(AppTab.profile.title, systemImage: AppTab.profile.symbol, value: AppTab.profile) { ProfileView() }
            }
            .toolbarVisibility(.hidden, for: .tabBar)
            if !app.tabBarHidden && !keyboardVisible {
                AppTabBar(selection: $app.tab) { app.showingAdd = true }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.snappy, value: app.tabBarHidden)
        .animation(.snappy, value: keyboardVisible)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .overlay(alignment: .bottom) {
            VStack(spacing: Spacing.xs) {
                if timer.isActive { TimerPill().transition(.move(edge: .bottom).combined(with: .opacity)) }
                if let notice = app.notice { Toast(text: notice) }
                UndoBanner()
            }
            .padding(.bottom, app.tabBarHidden ? 88 : 96)
            .animation(.snappy, value: app.notice)
            .animation(.snappy, value: timer.isActive)
        }
        .sheet(isPresented: $app.showingAdd) { AddRecipeView() }
    }
}

struct Toast: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium)).foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.s)
            .background(AppColors.card, in: Capsule())
            .overlay(Capsule().stroke(AppColors.separator))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// "Deleted “X”. Undo": the server keeps the recipe for 24 hours; the banner stays for a few seconds.
struct UndoBanner: View {
    @Environment(Session.self) private var session

    var body: some View {
        if let deleted = session.deleted {
            HStack(spacing: Spacing.s) {
                Text("Deleted “\(deleted.title)”").lineLimit(1).foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: Spacing.xs)
                Button("Undo") { Task { await session.undoDelete() } }.fontWeight(.semibold)
            }
            .font(.subheadline)
            .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.s)
            .background(AppColors.card, in: Capsule())
            .overlay(Capsule().stroke(AppColors.separator))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            .padding(.horizontal, Spacing.screen)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: deleted.token) {
                try? await Task.sleep(for: .seconds(8))
                session.dismissDeleted(deleted.token)
            }
        }
    }
}
