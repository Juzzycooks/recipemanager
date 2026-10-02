import SwiftUI

@MainActor @Observable
final class ShoppingModel {
    var list: ShoppingList?
    var error: String?

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
        catch { self.error = error.localizedDescription }
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
            withAnimation(.snappy) { list?.items.insert(local, at: 0) }
            Outbox.shared.enqueue(.addShoppingItem(name: trimmed, checked: false))
            await persist(session)
        } catch { self.error = error.localizedDescription }
    }

    func toggle(_ item: ShoppingItem, _ session: Session) async {
        guard let i = list?.items.firstIndex(where: { $0.id == item.id }) else { return }
        struct Body: Encodable, Sendable { let checked: Bool }
        let wanted = !item.checked
        withAnimation(.snappy) { list?.items[i].checked = wanted }
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
        } catch { self.error = error.localizedDescription; await load(session) }
    }

    func remove(_ item: ShoppingItem, _ session: Session) async {
        withAnimation(.snappy) { list?.items.removeAll { $0.id == item.id } }
        if item.id < 0 {
            Outbox.shared.cancelAdd(name: item.name)
            await persist(session)
            return
        }
        do {
            _ = try await session.runOrQueue(.deleteShoppingItem(itemID: item.id)) { try await $0.send("DELETE", "/shopping/items/\(item.id)") }
            await persist(session)
        } catch { self.error = error.localizedDescription; await load(session) }
    }

    func clear(checkedOnly: Bool, _ session: Session) async {
        do {
            try await session.run { try await $0.send("DELETE", "/shopping/items", query: checkedOnly ? ["checked": "1"] : [:]) }
            await load(session)
            await persist(session)
        } catch { self.error = error.localizedDescription }
    }
}

struct ShoppingListView: View {
    private enum Grouping: String, CaseIterable, Identifiable { case all = "All Items", recipe = "By Recipe"; var id: String { rawValue } }

    @Environment(Session.self) private var session
    @AppStorage("showStoreLinks") private var showStoreLinks = true
    @State private var model = ShoppingModel()
    @State private var grouping = Grouping.all
    @State private var showingAdd = false
    @State private var newItem = ""
    @State private var confirmClear = false

    var body: some View {
        List {
            Section {
                Picker("Group", selection: $grouping.animation(.snappy)) { ForEach(Grouping.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Spacing.xxs, trailing: 0))
            }
            if let list = model.list, list.items.isEmpty {
                EmptyStateView(title: "Your list is empty", systemImage: "cart", message: "Add items below, or from a recipe's ingredients.")
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
        .navigationTitle("Shopping List")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Add item", systemImage: "plus") { showingAdd = true }
                Menu {
                    Button("Clear completed", systemImage: "checkmark.circle") { Task { await model.clear(checkedOnly: true, session) } }.disabled(model.done.isEmpty)
                    Button("Clear everything", systemImage: "trash", role: .destructive) { confirmClear = true }.disabled(model.list?.items.isEmpty ?? true)
                } label: { Image(systemName: "ellipsis") }.accessibilityLabel("More")
            }
        }
        .homeBar { SecondaryButton(title: "Add Item", systemImage: "plus") { showingAdd = true } }
        .hidesAppTabBar()
        .task { await model.load(session) }
        .refreshable { await model.load(session) }
        .alert("Add item", isPresented: $showingAdd) {
            TextField("e.g. 2 onions", text: $newItem).textInputAutocapitalization(.sentences)
            Button("Add") { let name = newItem; newItem = ""; Task { await model.add(name, session) } }
            Button("Cancel", role: .cancel) { newItem = "" }
        }
        .confirmationDialog("Clear the whole list?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear everything", role: .destructive) { Task { await model.clear(checkedOnly: false, session) } }
        }
        .errorAlert($model.error)
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
