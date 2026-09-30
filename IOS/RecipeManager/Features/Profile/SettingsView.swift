import SwiftUI

/// App preferences (stored on this device) plus the server admin tools for admins.
struct SettingsView: View {
    @Environment(Session.self) private var session
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @AppStorage("keepAwake") private var keepAwake = true
    @AppStorage("showStoreLinks") private var showStoreLinks = true
    @AppStorage("recentSearches") private var recentSearches = Data()
    @AppStorage(OfflineSync.enabledKey) private var offlineEnabled = true
    @AppStorage(OfflineSync.imagesKey) private var offlineImages = true
    @Environment(OfflineSync.self) private var sync
    @State private var siteName = ""
    @State private var storageUsed = ""
    @State private var confirmClear = false

    var body: some View {
        List {
            appearanceSection
            offlineSection
            Section("Cooking") {
                Toggle("Keep screen awake while cooking", isOn: $keepAwake)
            }
            Section("Shopping list") {
                Toggle("Show store search links", isOn: $showStoreLinks)
            }
            Section {
                Button("Clear recent searches", role: .destructive) { recentSearches = Data() }
                    .disabled(recentSearches.isEmpty)
            } header: { Text("Privacy") } footer: { Text("Recent searches are kept on this device only.") }
            if session.user?.isAdmin == true { adminSection }
            Section("About") {
                LabeledContent("Server", value: session.baseURL?.host() ?? "")
                if !siteName.isEmpty { LabeledContent("Site name", value: siteName) }
                LabeledContent("App version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            }
        }
        .appBackground()
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .confirmationDialog("Remove the offline copy?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Remove offline data", role: .destructive) { Task { await sync.clear(); await refreshStorage() } }
        } message: { Text("Recipes and pictures are downloaded again next time you're online.") }
        .task(id: sync.lastSync) { await sync.refreshCount(); await refreshStorage() }
        .task {
            let info: SiteInfo? = try? await session.run { try await $0.get("/site") }
            siteName = info?.name ?? ""
        }
    }

    // MARK: Offline

    private var offlineSection: some View {
        Section {
            Toggle("Keep recipes available offline", isOn: $offlineEnabled)
            Toggle("Download pictures too", isOn: $offlineImages).disabled(!offlineEnabled)
            LabeledContent("On this phone", value: "\(sync.recipeCount) recipe\(sync.recipeCount == 1 ? "" : "s")" + (storageUsed.isEmpty ? "" : " · \(storageUsed)"))
            LabeledContent("Last updated", value: sync.lastSync.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
            if Outbox.shared.count > 0 {
                LabeledContent("Waiting to send", value: "\(Outbox.shared.count) change\(Outbox.shared.count == 1 ? "" : "s")")
            }
            Button {
                Task { await sync.sync(session); await refreshStorage() }
            } label: {
                if case .syncing(let message) = sync.state { HStack { ProgressView(); Text(message).font(.subheadline) } } else { Text("Update now") }
            }
            .disabled(sync.isSyncing || Connectivity.shared.isOffline)
            if case .failed(let message) = sync.state { Text(message).font(.footnote).foregroundStyle(AppColors.danger) }
            Button("Remove offline data", role: .destructive) { confirmClear = true }.disabled(sync.recipeCount == 0)
        } header: { Text("Offline") } footer: {
            Text("Recipes, collections, your shopping list and a few weeks of meal plan are kept on this phone so you can cook without a connection. Favourites, ratings and shopping list changes you make offline are sent when you're back online.")
        }
    }

    private func refreshStorage() async {
        let bytes = await OfflineStore.shared.byteCount() + URLCache.shared.currentDiskUsage
        storageUsed = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Mode").font(.subheadline).foregroundStyle(AppColors.textSecondary)
                HStack(spacing: Spacing.xs) {
                    ForEach(Appearance.allCases) { mode in
                        FilterChip(title: mode.title, isSelected: appearance == mode.rawValue) { appearance = mode.rawValue }
                    }
                }
            }
            .padding(.vertical, Spacing.xxs)
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Colour theme").font(.subheadline).foregroundStyle(AppColors.textSecondary)
                HStack(spacing: Spacing.m) {
                    ForEach(AppTheme.allCases) { theme in swatch(theme) }
                }
            }
            .padding(.vertical, Spacing.xxs)
        } header: { Text("Appearance") }
    }

    private func swatch(_ theme: AppTheme) -> some View {
        let selected = ThemeStore.shared.theme == theme
        return Button { withAnimation(.snappy) { ThemeStore.shared.theme = theme } } label: {
            VStack(spacing: Spacing.xxs) {
                Circle().fill(theme.tint).frame(width: 40, height: 40)
                    .overlay { if selected { Image(systemName: "checkmark").font(.subheadline.weight(.bold)).foregroundStyle(.white) } }
                    .overlay(Circle().stroke(AppColors.textPrimary.opacity(selected ? 0.9 : 0), lineWidth: 2).padding(-4))
                Text(theme.title).font(.caption2).foregroundStyle(AppColors.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: Size.tap)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.title) theme")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Admin

    private var adminSection: some View {
        Section {
            NavigationLink(value: AppRoute.adminSettings) { Label("Site settings", systemImage: "slider.horizontal.3") }
            NavigationLink(value: AppRoute.adminUsers) { Label("Users", systemImage: "person.2") }
            NavigationLink(value: AppRoute.adminCategories) { Label("Categories", systemImage: "tag") }
        } header: { Text("Server admin") } footer: { Text("These change the server for everyone who uses it.") }
    }
}
