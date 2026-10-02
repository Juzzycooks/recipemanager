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
    @Environment(OfflineSync.self) private var sync
    @Environment(\.scenePhase) private var scenePhase

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
        }
        .task {
            // Reconnect: send what was changed offline, refresh what's on screen, and top up the offline copy.
            Connectivity.shared.onRegained = { Task { await catchUp() } }
            await catchUp()
        }
        .onChange(of: scenePhase) {
            // Coming back to the app: something may have been added elsewhere (the Safari extension, another device).
            if scenePhase == .active { session.recipesChanged(); Task { await catchUp() } }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: Spacing.xs) {
                OfflineBanner()
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

extension MainView {
    /// Replays queued changes, then keeps the offline copy current (skipped while offline).
    @MainActor fileprivate func catchUp() async {
        guard !Connectivity.shared.isOffline else { return }
        if Outbox.shared.count > 0 { await Outbox.shared.replay(session) }
        await sync.syncIfNeeded(session)
    }
}

/// Top-of-screen status: offline (with how many changes are waiting), or syncing.
struct OfflineBanner: View {
    @Environment(OfflineSync.self) private var sync

    var body: some View {
        let offline = Connectivity.shared.isOffline
        let waiting = Outbox.shared.count
        if offline {
            pill("wifi.slash", "Offline · showing saved recipes" + (waiting > 0 ? " · \(waiting) change\(waiting == 1 ? "" : "s") waiting" : ""))
        } else if Outbox.shared.isReplaying {
            pill("arrow.triangle.2.circlepath", "Syncing your changes…")
        } else if case .syncing(let message) = sync.state {
            pill("arrow.down.circle", message)
        }
    }

    private func pill(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium)).foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, Spacing.s).frame(minHeight: 28)
            .background(AppColors.card, in: Capsule())
            .overlay(Capsule().stroke(AppColors.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityAddTraits(.updatesFrequently)
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
