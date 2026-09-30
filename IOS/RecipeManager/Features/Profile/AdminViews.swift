import SwiftUI

// MARK: Site settings

struct AdminSettingsView: View {
    @Environment(Session.self) private var session
    @Environment(AppState.self) private var app
    @State private var settings = AdminSettings()
    @State private var loaded = false
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Site") {
                TextField("Site name", text: $settings.siteName)
                Toggle("Show author on public pages", isOn: $settings.publicShowAuthor)
            }
            Section {
                TextField("Store name", text: $settings.storeName)
                TextField("Search link", text: $settings.storeSearchUrl).keyboardType(.URL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: { Text("Shopping list store") } footer: {
                Text("The link needs http:// or https:// and {q} where the item name goes, for example https://store.example/search?q={q}. Leave it empty to hide the search links.")
            }
        }
        .appBackground()
        .navigationTitle("Site settings").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving { ProgressView() } else { Button("Save") { Task { await save() } }.disabled(!loaded) }
            }
        }
        .task {
            do {
                settings = try await session.run { try await $0.get("/admin/settings") }
                loaded = true
            } catch { self.error = error.localizedDescription }
        }
        .errorAlert($error)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let body = settings
        do {
            settings = try await session.run { try await $0.send("PATCH", "/admin/settings", body: body) }
            app.say("Settings saved.")
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: Users

struct AdminUsersView: View {
    @Environment(Session.self) private var session
    @State private var users: [User] = []
    @State private var editing: User?
    @State private var showingAdd = false
    @State private var pendingDelete: User?
    @State private var error: String?

    var body: some View {
        List {
            ForEach(users) { user in
                Button { editing = user } label: {
                    HStack {
                        AvatarView(name: user.username, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(user.username).foregroundStyle(AppColors.textPrimary)
                            if let email = user.email, !email.isEmpty { Text(email).font(.caption).foregroundStyle(AppColors.textSecondary) }
                        }
                        Spacer()
                        if user.isAdmin == true { Text("Admin").font(.caption.weight(.semibold)).foregroundStyle(AppColors.secondary) }
                    }
                    .frame(minHeight: Size.tap)
                }
                .listRowBackground(AppColors.card)
                .swipeActions {
                    if user.id != session.user?.id {
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = user }
                    }
                }
            }
        }
        .appBackground()
        .navigationTitle("Users")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Add user", systemImage: "plus") { showingAdd = true } } }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showingAdd) { AddUserSheet { await load() } }
        .sheet(item: $editing) { user in EditUserSheet(user: user, isSelf: user.id == session.user?.id) { await load() } }
        .confirmationDialog("Delete \(pendingDelete?.username ?? "this user")?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete user and their recipes", role: .destructive) { if let u = pendingDelete { Task { await delete(u) } } }
        } message: { Text("Their recipes, ratings, comments and collections are deleted too. This can't be undone.") }
        .errorAlert($error)
    }

    private func load() async {
        do { let result: ItemList<User> = try await session.run { try await $0.get("/admin/users") }; users = result.items }
        catch { self.error = error.localizedDescription }
    }

    private func delete(_ user: User) async {
        do {
            try await session.run { try await $0.send("DELETE", "/admin/users/\(user.id)") }
            session.recipesChanged()
            await load()
        } catch { self.error = error.localizedDescription }
    }
}

private struct AddUserSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let onAdded: () async -> Void
    @State private var username = ""
    @State private var email = ""
    @State private var isAdmin = false
    @State private var result: NewUserResult?
    @State private var isSaving = false
    @State private var error: String?

    private struct Payload: Encodable, Sendable { let username: String; let email: String; let isAdmin: Bool }

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    Section {
                        Text("Created “\(result.user.username)”.").font(.headline)
                        if result.emailed {
                            Text("Their sign-in details were emailed to them.")
                        } else if let password = result.tempPassword {
                            LabeledContent("Temporary password") { Text(password).font(.body.monospaced()).textSelection(.enabled) }
                            Button("Copy password", systemImage: "doc.on.doc") { UIPasteboard.general.string = password }
                        }
                    } footer: { if !result.emailed { Text("Shown once. Share it with them and ask them to change it from Profile → Account.") } }
                } else {
                    Section {
                        TextField("Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Email (optional)", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                        Toggle("Admin", isOn: $isAdmin)
                    } footer: { Text("A password is generated for them. With an email address, the server emails it (if mail is set up).") }
                }
            }
            .appBackground()
            .navigationTitle("Add User").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(result == nil ? "Cancel" : "Done") { dismiss() } }
                if result == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { Task { await create() } }.disabled(isSaving || username.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .errorAlert($error)
        }
        .presentationDetents([.medium, .large])
    }

    private func create() async {
        isSaving = true
        defer { isSaving = false }
        let body = Payload(username: username.trimmingCharacters(in: .whitespaces), email: email.trimmingCharacters(in: .whitespaces), isAdmin: isAdmin)
        do {
            result = try await session.run { try await $0.send("POST", "/admin/users", body: body) }
            await onAdded()
        } catch { self.error = error.localizedDescription }
    }
}

private struct EditUserSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let user: User
    let isSelf: Bool
    let onSaved: () async -> Void
    @State private var username = ""
    @State private var email = ""
    @State private var isAdmin = false
    @State private var newPassword = ""
    @State private var isSaving = false
    @State private var error: String?

    private struct Payload: Encodable, Sendable {
        let username: String; let email: String; let isAdmin: Bool; let newPassword: String?
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Email", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    Toggle("Admin", isOn: $isAdmin).disabled(isSelf)
                } footer: { if isSelf { Text("You can't remove your own admin access.") } }
                Section {
                    SecureField("New password (optional)", text: $newPassword)
                } header: { Text("Reset password") } footer: { Text("At least 8 characters with letters and numbers. They'll be signed out of their other devices.") }
            }
            .appBackground()
            .navigationTitle("Edit User").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(isSaving || username.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { username = user.username; email = user.email ?? ""; isAdmin = user.isAdmin == true }
            .errorAlert($error)
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let body = Payload(username: username.trimmingCharacters(in: .whitespaces), email: email.trimmingCharacters(in: .whitespaces),
                           isAdmin: isAdmin, newPassword: newPassword.isEmpty ? nil : newPassword)
        let id = user.id
        do {
            let _: User = try await session.run { try await $0.send("PATCH", "/admin/users/\(id)", body: body) }
            await session.refreshUser()
            await onSaved()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: Categories

struct AdminCategoriesView: View {
    @Environment(Session.self) private var session
    @State private var categories: [Category] = []
    @State private var showingAdd = false
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        List {
            ForEach(categories) { cat in
                Text(cat.name).foregroundStyle(AppColors.textPrimary).frame(minHeight: Size.tap)
                    .listRowBackground(AppColors.card)
                    .swipeActions { Button("Delete", systemImage: "trash", role: .destructive) { Task { await delete(cat) } } }
            }
            if categories.isEmpty { Text("No categories yet.").foregroundStyle(AppColors.textSecondary).listRowBackground(Color.clear) }
        }
        .appBackground()
        .navigationTitle("Categories")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Add category", systemImage: "plus") { showingAdd = true } } }
        .task { await load() }
        .refreshable { await load() }
        .alert("New category", isPresented: $showingAdd) {
            TextField("Name", text: $name)
            Button("Add") { let n = name; name = ""; Task { await add(n) } }
            Button("Cancel", role: .cancel) { name = "" }
        }
        .errorAlert($error)
    }

    private func load() async {
        do { let result: ItemList<Category> = try await session.run { try await $0.get("/categories") }; categories = result.items }
        catch { self.error = error.localizedDescription }
    }

    private func add(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            let _: Category = try await session.run { try await $0.send("POST", "/categories", body: ["name": trimmed]) }
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func delete(_ cat: Category) async {
        do {
            try await session.run { try await $0.send("DELETE", "/categories/\(cat.id)") }
            session.recipesChanged()
            await load()
        } catch { self.error = error.localizedDescription }
    }
}
