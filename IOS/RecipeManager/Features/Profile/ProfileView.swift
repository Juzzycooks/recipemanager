import SwiftUI

@MainActor @Observable
final class ProfileModel {
    var recipes = 0
    var favorites = 0
    var collections = 0
    var store: ShoppingList.Store?
    var siteName = ""

    func load(_ session: Session) async {
        async let all: Page<RecipeSummary>? = try? session.run { try await $0.get("/recipes", query: ["per_page": "1"]) }
        async let favs: Page<RecipeSummary>? = try? session.run { try await $0.get("/recipes", query: ["per_page": "1", "favorites": "1"]) }
        async let colls: ItemList<CollectionSummary>? = try? session.run { try await $0.get("/collections") }
        async let info: SiteInfo? = try? session.run { try await $0.get("/site") }
        let (a, f, c, i) = await (all, favs, colls, info)
        recipes = a?.total ?? recipes; favorites = f?.total ?? favorites; collections = c?.items.count ?? collections
        siteName = i?.name ?? siteName
    }
}

struct ProfileView: View {
    @Environment(Session.self) private var session
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @State private var model = ProfileModel()
    @State private var path: [AppRoute] = []
    @State private var showingAccount = false
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: Spacing.l) {
                    header
                    stats
                    settings
                    Button("Sign Out", role: .destructive) { confirmSignOut = true }
                        .frame(maxWidth: .infinity, minHeight: Size.tap)
                        .background(AppColors.card, in: RoundedRectangle(cornerRadius: Radius.card))
                        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(AppColors.separator, lineWidth: 0.5))
                        .foregroundStyle(AppColors.danger)
                }
                .screenPadding().padding(.bottom, Spacing.xl)
            }
            .background(AppColors.background)
            .navigationTitle("Profile")
            .appDestinations()
            .task(id: session.dataVersion) { await model.load(session) }
            .sheet(isPresented: $showingAccount) { AccountSheet() }
            .confirmationDialog("Sign out of this device?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { Task { await session.signOut() } }
            }
        }
    }

    private var header: some View {
        VStack(spacing: Spacing.xs) {
            AvatarView(name: session.user?.username ?? "", size: 84)
            Text(session.user?.username ?? "").font(AppTypography.title).foregroundStyle(AppColors.textPrimary)
            if let email = session.user?.email, !email.isEmpty { Text(email).font(.subheadline).foregroundStyle(AppColors.textSecondary) }
            if session.user?.isAdmin == true { Text("Admin").font(.caption.weight(.semibold)).foregroundStyle(AppColors.secondary) }
        }
        .padding(.top, Spacing.s)
    }

    private var stats: some View {
        HStack(spacing: 0) {
            stat(model.recipes, "Recipes")
            Divider().frame(height: 32)
            stat(model.favorites, "Favorites")
            Divider().frame(height: 32)
            stat(model.collections, "Collections")
        }
        .padding(.vertical, Spacing.m)
        .background(AppColors.card, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(AppColors.separator, lineWidth: 0.5))
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(AppTypography.title2).foregroundStyle(AppColors.textPrimary).contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity).accessibilityElement(children: .combine)
    }

    private var settings: some View {
        VStack(spacing: 0) {
            row("Appearance", symbol: "circle.lefthalf.filled") {
                Picker("Appearance", selection: $appearance) { ForEach(Appearance.allCases) { Text($0.title).tag($0.rawValue) } }.labelsHidden()
            }
            divider
            button("Meal Plan", symbol: "calendar") { path.append(.mealPlan) }
            divider
            button("Shopping List", symbol: "cart") { path.append(.shoppingList) }
            divider
            button("Account", symbol: "person.crop.circle") { showingAccount = true }
            divider
            button("Signed-in Devices", symbol: "iphone") { path.append(.devices) }
            divider
            row("Server", symbol: "server.rack") {
                Text(session.baseURL?.host() ?? "").font(.subheadline).foregroundStyle(AppColors.textSecondary).lineLimit(1)
            }
            divider
            row("Version", symbol: "info.circle") {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "").font(.subheadline).foregroundStyle(AppColors.textSecondary)
            }
        }
        .background(AppColors.card, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(AppColors.separator, lineWidth: 0.5))
    }

    private var divider: some View { Divider().padding(.leading, 52) }

    private func row<Trailing: View>(_ title: String, symbol: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: symbol).foregroundStyle(AppColors.primary).frame(width: 28)
            Text(title).foregroundStyle(AppColors.textPrimary)
            Spacer(minLength: Spacing.xs)
            trailing()
        }
        .padding(.horizontal, Spacing.m).frame(minHeight: 52)
    }

    private func button(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            row(title, symbol: symbol) { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(AppColors.textSecondary) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Account

struct AccountSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var current = ""
    @State private var new = ""
    @State private var message: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Email") {
                    TextField("Email", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save email") { Task { await saveEmail() } }
                }
                Section {
                    SecureField("Current password", text: $current)
                    SecureField("New password", text: $new)
                    Button("Change password") { Task { await changePassword() } }.disabled(current.isEmpty || new.isEmpty)
                } header: { Text("Password") } footer: { Text("At least 8 characters with letters and numbers. Other devices are signed out.") }
                if let message { Section { Text(message).foregroundStyle(AppColors.primary) } }
            }
            .appBackground()
            .navigationTitle("Account").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { email = session.user?.email ?? "" }
            .errorAlert($error)
        }
    }

    private func saveEmail() async {
        struct Body: Encodable, Sendable { let email: String }
        let value = email
        do {
            let _: User = try await session.run { try await $0.send("PATCH", "/me", body: Body(email: value)) }
            await session.refreshUser(); message = "Email saved."
        } catch { self.error = error.localizedDescription }
    }

    private func changePassword() async {
        struct Body: Encodable, Sendable { let currentPassword: String; let newPassword: String }
        let body = Body(currentPassword: current, newPassword: new)
        do {
            try await session.run { try await $0.send("POST", "/me/password", body: body) }
            current = ""; new = ""; message = "Password changed."
        } catch { self.error = error.localizedDescription }
    }
}

struct DevicesView: View {
    @Environment(Session.self) private var session
    @State private var devices: [DeviceToken] = []
    @State private var error: String?

    var body: some View {
        List {
            Section {
                ForEach(devices) { d in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(d.name.isEmpty ? "Unnamed device" : d.name).foregroundStyle(AppColors.textPrimary)
                            if d.current { Text("This device").font(.caption.weight(.semibold)).foregroundStyle(AppColors.primary) }
                        }
                        Text("Signed in \(d.createdAt?.formatted(date: .abbreviated, time: .omitted) ?? "")" + (d.lastUsedAt.map { " · last used \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""))
                            .font(.caption).foregroundStyle(AppColors.textSecondary)
                    }
                    .listRowBackground(AppColors.card)
                    .swipeActions { if !d.current { Button("Sign out", role: .destructive) { Task { await revoke(d) } } } }
                }
            } footer: { Text("Swipe a device to sign it out.") }
        }
        .appBackground()
        .navigationTitle("Devices")
        .task { await load() }
        .errorAlert($error)
    }

    private func load() async {
        do { let result: ItemList<DeviceToken> = try await session.run { try await $0.get("/auth/tokens") }; devices = result.items }
        catch { self.error = error.localizedDescription }
    }

    private func revoke(_ d: DeviceToken) async {
        do { try await session.run { try await $0.send("DELETE", "/auth/tokens/\(d.id)") }; devices.removeAll { $0.id == d.id } }
        catch { self.error = error.localizedDescription }
    }
}
