import SwiftUI

@MainActor @Observable
final class ShoppingModel {
    var list: ShoppingList?
    var error: String?
    /// Ticked items taken off by "Clear completed" but not yet deleted, so Undo can put them back as they were.
    private(set) var cleared: [ShoppingItem] = []

    var open: [ShoppingItem] { list?.items.filter { !$0.checked } ?? [] }
    var done: [ShoppingItem] { list?.items.filter(\.checked) ?? [] }

    var byAisle: [(title: String, items: [ShoppingItem])] {
        let grouped = Dictionary(grouping: open, by: \.aisle)
        return (list?.aisleOrder ?? []).compactMap { a in grouped[a].map { (a, $0) } }
    }

    var byRecipe: [(title: String, items: [ShoppingItem])] {
        let grouped = Dictionary(grouping: open) { $0.recipeTitle ?? "" }
        let named = grouped.filter { !$0.key.isEmpty }.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        var out = named.map { (title: $0.key, items: $0.value) }
        if let loose = grouped[""] { out.append((title: "Other items", items: loose)) }
        return out
    }

    func load(_ session: Session) async {
        do { list = try await session.run { try await $0.get("/shopping") } }
        catch is CancellationError {}
        catch let e as URLError where e.code == .cancelled {}
        catch { self.error = "Couldn't load your shopping list. \(error.localizedDescription)" }
    }

    /// Saves the list as it is now, so a relaunch without a connection shows your latest edits.
    private func persist(_ session: Session) async {
        guard let client = session.client, let list, let url = client.url("/shopping"),
              let data = try? APIClient.encoder.encode(list) else { return }
        await OfflineStore.shared.store(data, for: url)
    }

    func add(_ name: String, _ session: Session) async {
        struct Body: Encodable, Sendable { let name: String }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            try await session.run { try await $0.send("POST", "/shopping/items", body: Body(name: trimmed)) }
            await load(session)
            await persist(session)
        } catch let e as APIError where e.isOffline {
            // Add it on this phone now (a temporary negative id) and send it later.
            let local = ShoppingItem(id: -Int.random(in: 1...Int.max / 2), name: trimmed, checked: false, recipeId: nil, recipeTitle: nil, aisle: "Other", storeUrl: nil)
            withAnimation(.listChange) { list?.items.insert(local, at: 0) }
            Outbox.shared.enqueue(.addShoppingItem(name: trimmed, checked: false))
            await persist(session)
        } catch { self.error = "Couldn't add “\(trimmed)”. \(error.localizedDescription)" }
    }

    func toggle(_ item: ShoppingItem, _ session: Session) async {
        guard let i = list?.items.firstIndex(where: { $0.id == item.id }) else { return }
        struct Body: Encodable, Sendable { let checked: Bool }
        let wanted = !item.checked
        withAnimation(.listChange) { list?.items[i].checked = wanted }
        if item.id < 0 {   // added offline, not sent yet
            Outbox.shared.setAddChecked(name: item.name, checked: wanted)
            await persist(session)
            return
        }
        do {
            let _: ShoppingItem? = try await session.runOrQueue(.setShoppingChecked(itemID: item.id, checked: wanted)) {
                try await $0.send("PATCH", "/shopping/items/\(item.id)", body: Body(checked: wanted))
            }
            await persist(session)
        } catch { self.error = "Couldn't update “\(item.name)”. \(error.localizedDescription)"; await load(session) }
    }

    func remove(_ item: ShoppingItem, _ session: Session) async {
        withAnimation(.listChange) { list?.items.removeAll { $0.id == item.id } }
        if item.id < 0 {
            Outbox.shared.cancelAdd(name: item.name)
            await persist(session)
            return
        }
        do {
            _ = try await session.runOrQueue(.deleteShoppingItem(itemID: item.id)) { try await $0.send("DELETE", "/shopping/items/\(item.id)") }
            await persist(session)
        } catch { self.error = "Couldn't delete “\(item.name)”. \(error.localizedDescription)"; await load(session) }
    }

    func clearEverything(_ session: Session) async {
        await commitClear(session)
        do {
            try await session.run { try await $0.send("DELETE", "/shopping/items") }
            await load(session)
            await persist(session)
        } catch { self.error = "Couldn't clear the list. \(error.localizedDescription)" }
    }

    /// Takes the ticked items off now; they're deleted for real when the Undo offer ends (or the screen closes).
    func clearCompleted(_ session: Session) async {
        await commitClear(session)
        let ticked = done
        guard !ticked.isEmpty else { return }
        withAnimation(.listChange) { list?.items.removeAll(where: \.checked) }
        cleared = ticked
    }

    func undoClear() {
        guard !cleared.isEmpty else { return }
        withAnimation(.listChange) { list?.items.append(contentsOf: cleared) }
        cleared = []
    }

    /// Deletes what "Clear completed" took off (queued when offline).
    func commitClear(_ session: Session) async {
        let items = cleared
        guard !items.isEmpty else { return }
        cleared = []
        for item in items where item.id < 0 { Outbox.shared.cancelAdd(name: item.name) }
        let sent = items.filter { $0.id > 0 }
        do {
            if done.isEmpty && Outbox.shared.count == 0 {
                // Nothing else is ticked here or waiting to be sent, so one request clears exactly these.
                try await session.run { try await $0.send("DELETE", "/shopping/items", query: ["checked": "1"]) }
            } else {
                for item in sent { try await session.run { try await $0.send("DELETE", "/shopping/items/\(item.id)") } }
            }
        } catch let e as APIError where e.isOffline {
            for item in sent { Outbox.shared.enqueue(.deleteShoppingItem(itemID: item.id)) }
        } catch {
            self.error = "Couldn't clear the ticked items. \(error.localizedDescription)"
            await load(session)
            return
        }
        await persist(session)
    }
}

struct ShoppingListView: View {
    private enum Grouping: String, CaseIterable, Identifiable { case all = "All items", recipe = "By recipe"; var id: String { rawValue } }

    @Environment(Session.self) private var session
    @AppStorage("showStoreLinks") private var showStoreLinks = true
    @State private var model = ShoppingModel()
    @State private var grouping = Grouping.all
    @State private var newItem = ""
    @State private var confirmClear = false
    @FocusState private var addFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        List {
            Section {
                Picker("Group", selection: $grouping.animation(.listChange)) { ForEach(Grouping.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Spacing.xxs, trailing: 0))
            }
            Section { addField }
            if let list = model.list, list.items.isEmpty {
                EmptyStateView(title: "Your list is empty", systemImage: "cart", message: "Add items above, or from a recipe's ingredients.")
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            ForEach(grouping == .all ? model.byAisle : model.byRecipe, id: \.title) { group in
                Section(group.title) { ForEach(group.items) { row($0) } }
            }
            if !model.done.isEmpty {
                Section("Completed") { ForEach(model.done) { row($0) } }
            }
        }
        .appBackground()
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .bottom) {
            if !model.cleared.isEmpty {
                let count = model.cleared.count
                UndoToast(text: "Cleared \(count) ticked item\(count == 1 ? "" : "s")", id: model.cleared.map(\.id),
                          onUndo: { model.undoClear() },
                          onExpire: { Task { await model.commitClear(session) } })
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: model.cleared.isEmpty)
        .navigationTitle("Shopping list")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Clear completed", systemImage: "checkmark.circle") { Task { await model.clearCompleted(session) } }.disabled(model.done.isEmpty)
                    Button("Clear everything", systemImage: "trash", role: .destructive) { confirmClear = true }.disabled(model.list?.items.isEmpty ?? true)
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("List options")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { addFocused = false }
            }
        }
        .task { await model.load(session) }
        .refreshable { await model.load(session) }
        .onDisappear { Task { await model.commitClear(session) } }
        .confirmationDialog("Clear the whole list?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear everything", role: .destructive) { Task { await model.clearEverything(session) } }
        } message: { Text("This removes every item, ticked or not, and can't be undone.") }
        .errorAlert($model.error)
    }

    /// Type, press return, type the next one: the field keeps the keyboard up so a run of items goes in quickly.
    private var addField: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "plus").foregroundStyle(AppColors.primary).accessibilityHidden(true)
            TextField("Add an item, like 2 onions", text: $newItem)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.next).focused($addFocused).onSubmit(addItem)
                .accessibilityLabel("New item")
            if !newItem.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Add", action: addItem).fontWeight(.semibold).frame(minHeight: Size.tap)
            }
        }
        .frame(minHeight: Size.tap)
        .listRowBackground(AppColors.card)
    }

    private func addItem() {
        let name = newItem.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { addFocused = false; return }   // return on an empty field ends the run
        newItem = ""
        // Return ends editing first; asking for focus on the next turn keeps the keyboard up.
        Task { @MainActor in addFocused = true }
        Task { await model.add(name, session) }
    }

    private func row(_ item: ShoppingItem) -> some View {
        HStack(spacing: Spacing.s) {
            Button { Task { await model.toggle(item, session) } } label: {
                HStack(spacing: Spacing.s) {
                    Image(systemName: item.checked ? "checkmark.square.fill" : "square").font(.title3)
                        .foregroundStyle(item.checked ? AppColors.primary : AppColors.textSecondary)
                    Text(item.name).strikethrough(item.checked).foregroundStyle(item.checked ? AppColors.textSecondary : AppColors.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Size.tap).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(item.checked ? .isSelected : [])
            if showStoreLinks, let link = item.storeUrl, let url = URL(string: link), !item.checked {
                Link(destination: url) { Image(systemName: "magnifyingglass").foregroundStyle(AppColors.textSecondary).frame(minWidth: Size.tap, minHeight: Size.tap) }
                    .accessibilityLabel("Find \(item.name) at \(model.list?.store.name ?? "the store")")
            }
        }
        .listRowBackground(AppColors.card)
        .swipeActions { Button("Delete", systemImage: "trash", role: .destructive) { Task { await model.remove(item, session) } } }
    }
}
