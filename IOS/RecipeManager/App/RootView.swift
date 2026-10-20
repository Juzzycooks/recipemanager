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

/// The system tab bar: Recipes, Plan, Shop, Collections and Search. Add is a toolbar action on Recipes, and Profile
/// opens from the avatar there. Each tab owns a NavigationStack whose path lives in `AppState`, so re-tapping the
/// tab that's showing pops it to its root.
struct MainView: View {
    @Environment(Session.self) private var session
    @Environment(AppState.self) private var app
    @Environment(OfflineSync.self) private var sync
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app
        TabView(selection: app.selection) {
            Tab(AppTab.recipes.title, systemImage: AppTab.recipes.symbol, value: AppTab.recipes) { TabStack(tab: .recipes) { HomeView() } }
            Tab(AppTab.plan.title, systemImage: AppTab.plan.symbol, value: AppTab.plan) { TabStack(tab: .plan) { MealPlanView() } }
            Tab(AppTab.shop.title, systemImage: AppTab.shop.symbol, value: AppTab.shop) { TabStack(tab: .shop) { ShoppingListView() } }
            Tab(AppTab.collections.title, systemImage: AppTab.collections.symbol, value: AppTab.collections) {
                TabStack(tab: .collections) { CollectionsView() }
            }
            Tab(value: AppTab.search, role: .search) { TabStack(tab: .search) { SearchView() } }
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
        .sheet(isPresented: $app.showingAdd) { AddRecipeView() }
    }
}

/// One tab's navigation stack, with the status pills in a bottom inset: inside the tab, the safe area already ends
/// at the system tab bar, so the pills sit just above it, and a pushed screen's own bottom bar sits above them.
private struct TabStack<Root: View>: View {
    @Environment(AppState.self) private var app
    let tab: AppTab
    @ViewBuilder let root: Root

    var body: some View {
        NavigationStack(path: app.path(tab)) { root.appDestinations() }
            .safeAreaInset(edge: .bottom, spacing: 0) { StatusStack() }
    }
}

/// Offline/sync, the running timer, toasts and the undo banner, stacked above whatever ends the screen.
struct StatusStack: View {
    @Environment(Session.self) private var session
    @Environment(AppState.self) private var app
    @Environment(CookTimer.self) private var timer
    @Environment(OfflineSync.self) private var sync
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSyncing: Bool { if case .syncing = sync.state { true } else { false } }
    private var hasContent: Bool {
        Connectivity.shared.isOffline || Outbox.shared.isReplaying || isSyncing
            || timer.isActive || app.notice != nil || session.deleted != nil
    }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            if hasContent {
                OfflineBanner()
                if timer.isActive { TimerPill().transition(.bannerSlide(reduceMotion)) }
                if let notice = app.notice { Toast(text: notice) }
                UndoBanner()
            }
        }
        .padding(.vertical, hasContent ? Spacing.xs : 0)
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: app.notice)
        .animation(.snappy, value: timer.isActive)
        .animation(.snappy, value: session.deleted?.token)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .transition(.bannerSlide(reduceMotion))
            .accessibilityAddTraits(.updatesFrequently)
    }
}

struct Toast: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium)).foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.s)
            .background(AppColors.card, in: Capsule())
            .overlay(Capsule().stroke(AppColors.separator))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            .transition(.bannerSlide(reduceMotion))
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// "Deleted “X”. Undo": the server keeps the recipe for 24 hours; the banner stays for a few seconds.
struct UndoBanner: View {
    @Environment(Session.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .transition(.bannerSlide(reduceMotion))
            .task(id: deleted.token) {
                try? await Task.sleep(for: .seconds(8))
                session.dismissDeleted(deleted.token)
            }
        }
    }
}

extension AnyTransition {
    /// Status pills and toasts rise from the bottom; with Reduce Motion they only fade.
    static func bannerSlide(_ reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }
}
