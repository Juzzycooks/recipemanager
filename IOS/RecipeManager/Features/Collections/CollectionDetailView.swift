import SwiftUI

struct CollectionDetailView: View {
    @Environment(Session.self) private var session
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let id: Int
    @State private var collection: CollectionDetail?
    @State private var error: String?
    @State private var showingAdd = false
    @State private var showingEdit = false
    @State private var confirmDelete = false

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: Spacing.s, alignment: .top)]

    var body: some View {
        ScrollView {
            if let collection {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    if !collection.description.isEmpty {
                        Text(collection.description).font(AppTypography.reading).foregroundStyle(AppColors.textSecondary).screenPadding()
                    }
                    if collection.recipes.isEmpty {
                        EmptyStateView(title: "Empty collection", systemImage: "book.closed", message: "Add recipes to start building it.",
                                       actionTitle: "Add Recipes") { showingAdd = true }.padding(.top, Spacing.xl)
                    } else {
                        LazyVGrid(columns: columns, spacing: Spacing.s) {
                            ForEach(collection.recipes) { recipe in
                                NavigationLink(value: AppRoute.recipe(recipe.id)) {
                                    RecipeCard(recipe: recipe) { Task { await toggleFavorite(recipe) } }
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if collection.manualRecipeIds.contains(recipe.id) {
                                        Button("Remove from collection", systemImage: "minus.circle", role: .destructive) { Task { await remove(recipe) } }
                                    }
                                }
                            }
                        }
                        .screenPadding()
                    }
                }
                .padding(.bottom, Spacing.xl)
            } else if error == nil {
                ProgressView().padding(.top, 80)
            }
        }
        .background(AppColors.background)
        .navigationTitle(collection?.name ?? "")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if let collection {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add recipes", systemImage: "plus") { showingAdd = true }
                        Button("Rename", systemImage: "pencil") { showingEdit = true }
                        Button(collection.shareUrl == nil ? "Create share link" : "Stop sharing", systemImage: "link") { Task { await toggleShare() } }
                        if let link = collection.shareUrl, let url = URL(string: link) {
                            ShareLink(item: url) { Label("Share link", systemImage: "square.and.arrow.up") }
                        }
                        Button("Delete collection", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: { Image(systemName: "ellipsis") }.accessibilityLabel("More")
                }
            }
        }
        .task(id: session.dataVersion) { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showingAdd) {
            RecipePickerSheet(title: "Add to Collection", excluding: Set(collection?.recipes.map(\.id) ?? [])) { recipe in
                await add(recipe); return true
            }
        }
        .sheet(isPresented: $showingEdit) { CollectionEditorSheet(collection: collection) { collection = $0; session.recipesChanged() } }
        .confirmationDialog("Delete this collection?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        } message: { Text("The recipes themselves aren't deleted.") }
        .errorAlert($error)
    }

    private func load() async {
        do { collection = try await session.run { [id] in try await $0.get("/collections/\(id)") }; error = nil }
        catch is CancellationError {}
        catch let e as URLError where e.code == .cancelled {}
        catch { self.error = error.localizedDescription }
    }

    private func add(_ recipe: RecipeSummary) async {
        struct Body: Encodable, Sendable { let recipeId: Int }
        do {
            collection = try await session.run { [id] in try await $0.send("POST", "/collections/\(id)/recipes", body: Body(recipeId: recipe.id)) }
            app.say("Added “\(recipe.title)”.")
        } catch { self.error = error.localizedDescription }
    }

    private func remove(_ recipe: RecipeSummary) async {
        do {
            try await session.run { [id] in try await $0.send("DELETE", "/collections/\(id)/recipes/\(recipe.id)") }
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func toggleFavorite(_ recipe: RecipeSummary) async {
        guard let i = collection?.recipes.firstIndex(where: { $0.id == recipe.id }) else { return }
        let wanted = !recipe.isFavorite
        collection?.recipes[i].isFavorite = wanted
        do { _ = try await session.runOrQueue(.favorite(recipeID: recipe.id, wanted: wanted)) { try await $0.send(wanted ? "PUT" : "DELETE", "/recipes/\(recipe.id)/favorite") } }
        catch { collection?.recipes[i].isFavorite = !wanted; self.error = error.localizedDescription }
    }

    private func toggleShare() async {
        struct Result: Decodable, Sendable { let shareUrl: String }
        let sharing = collection?.shareUrl != nil
        do {
            if sharing {
                try await session.run { [id] in try await $0.send("DELETE", "/collections/\(id)/share") }
                collection?.shareUrl = nil; app.say("Stopped sharing.")
            } else {
                let result: Result = try await session.run { [id] in try await $0.send("POST", "/collections/\(id)/share") }
                collection?.shareUrl = result.shareUrl; app.say("Share link created.")
            }
            session.recipesChanged()
        } catch { self.error = error.localizedDescription }
    }

    private func delete() async {
        do {
            try await session.run { [id] in try await $0.send("DELETE", "/collections/\(id)") }
            session.recipesChanged(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
