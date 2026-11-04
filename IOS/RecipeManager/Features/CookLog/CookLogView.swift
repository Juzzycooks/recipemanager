import SwiftUI
import Observation

/// Your cook history: every cook (from Profile), or one recipe's (from its "Made N times"). Newest first.
@MainActor @Observable
final class CookLogModel {
    /// Nil for the whole timeline (`GET /cook-log`), a recipe id for that recipe's (`GET /recipes/{id}/cook-history`).
    let recipeID: Int?
    var entries: [CookEntry] = []
    var loaded = false
    var loadingMore = false
    var unsupported = false
    var error: String?
    /// Which entry a photo is being added to or replaced on (the camera and library report back without one).
    var photoTarget: Int?
    /// Entries with a request on the way (shows a spinner over their photo).
    var working: Set<Int> = []
    private var nextBefore: Int?
    /// Deleted here and waiting for the Undo offer to end: kept out of a reload in the meantime.
    private var pendingDeletes: Set<Int> = []

    static let pageSize = 30

    init(recipeID: Int?) { self.recipeID = recipeID }

    var canLoadMore: Bool { recipeID == nil && nextBefore != nil }

    func load(_ session: Session) async {
        do {
            if let recipeID {
                let result: ItemList<CookEntry> = try await session.run { try await $0.get("/recipes/\(recipeID)/cook-history") }
                entries = result.items.filter { !pendingDeletes.contains($0.id) }
                nextBefore = nil
            } else {
                let page: CookLogPage = try await session.run { try await $0.get("/cook-log", query: ["limit": "\(Self.pageSize)"]) }
                entries = page.entries.filter { !pendingDeletes.contains($0.id) }
                nextBefore = page.nextBefore
            }
            unsupported = false
        } catch is CancellationError {
        } catch let APIError.server(status, _, _) where status == 404 || status == 405 {
            unsupported = true
        } catch {
            if entries.isEmpty { self.error = error.localizedDescription }
        }
        loaded = true
    }

    /// The next page (`before` = the last page's `next_before`).
    func loadMore(_ session: Session) async {
        guard let before = nextBefore, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page: CookLogPage = try await session.run {
                try await $0.get("/cook-log", query: ["limit": "\(Self.pageSize)", "before": "\(before)"])
            }
            let known = Set(entries.map(\.id)).union(pendingDeletes)
            entries += page.entries.filter { !known.contains($0.id) }
            nextBefore = page.nextBefore
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }

    func saveNote(_ entry: CookEntry, _ note: String, _ session: Session) async {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        await update(entry.id, session) { try await CookLog.setNote($0, entryID: entry.id, note: text) }
    }

    func setPhoto(_ jpeg: Data, on id: Int, _ session: Session) async {
        await update(id, session) { try await CookLog.setPhoto($0, entryID: id, photo: jpeg) }
    }

    func removePhoto(_ entry: CookEntry, _ session: Session) async {
        await update(entry.id, session) { try await CookLog.removePhoto($0, entryID: entry.id) }
    }

    private func update(_ id: Int, _ session: Session, _ request: @escaping @Sendable (APIClient) async throws -> CookEntry) async {
        working.insert(id)
        defer { working.remove(id) }
        do {
            let fresh = try await session.run(request)
            replace(fresh)
            session.recipesChanged()   // the recipe page's photo strip
        } catch let APIError.server(status, _, message) where CookLog.isPhotoRejection(status) {
            self.error = message.isEmpty ? "The server couldn't use that photo." : message
        } catch { self.error = error.localizedDescription }
    }

    private func replace(_ fresh: CookEntry) {
        guard let i = entries.firstIndex(where: { $0.id == fresh.id }) else { return }
        var merged = fresh
        if merged.recipe == nil { merged.recipe = entries[i].recipe }
        entries[i] = merged
    }

    /// Takes the entry off at once and offers Undo; the server delete waits until the offer ends.
    func delete(_ entry: CookEntry, _ session: Session, _ app: AppState) async {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries.remove(at: index)
        pendingDeletes.insert(entry.id)
        await app.offerUndo("Cook deleted", commit: { [weak self] in
            defer { self?.pendingDeletes.remove(entry.id) }
            do {
                try await session.run { try await CookLog.delete($0, entryID: entry.id) }
                session.recipesChanged()
            } catch let APIError.server(status, _, _) where status == 404 {
                session.recipesChanged()   // already gone
            } catch {
                self?.putBack(entry, at: index)
                self?.error = error.localizedDescription
            }
        }, undo: { [weak self] in
            self?.pendingDeletes.remove(entry.id)
            self?.putBack(entry, at: index)
        })
    }

    private func putBack(_ entry: CookEntry, at index: Int) {
        guard !entries.contains(where: { $0.id == entry.id }) else { return }
        entries.insert(entry, at: min(index, entries.count))
    }
}

struct CookLogView: View {
    @Environment(Session.self) private var session
    @Environment(AppState.self) private var app
    @State private var model: CookLogModel
    @State private var editing: CookEntry?
    @State private var viewing: CookEntry?
    @State private var deleting: CookEntry?
    @State private var showingCamera = false
    @State private var showingLibrary = false

    init(recipeID: Int?) { _model = State(initialValue: CookLogModel(recipeID: recipeID)) }

    var body: some View {
        content
            .appBackground()
            .navigationTitle(model.recipeID == nil ? "Cook history" : (model.entries.first?.recipe?.title ?? "Cook history"))
            .navigationBarTitleDisplayMode(.inline)
            .task(id: session.dataVersion) { await model.load(session) }
            .refreshable { await model.load(session) }
            .sheet(item: $editing) { entry in
                CookNoteSheet(entry: entry) { note in Task { await model.saveNote(entry, note, session) } }
            }
            .fullScreenCover(item: $viewing) { CookPhotoViewer(entry: $0) }
            .confirmationDialog("Delete this cook?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible, presenting: deleting) { entry in
                Button("Delete", role: .destructive) { Task { await model.delete(entry, session, app) } }
            } message: { _ in Text("Its note and photo go too. You can undo for a few seconds afterwards.") }
            .photoCapture(camera: $showingCamera, library: $showingLibrary) { jpeg in
                guard let id = model.photoTarget else { return }
                model.photoTarget = nil
                Task { await model.setPhoto(jpeg, on: id, session) }
            }
            .errorAlert($model.error)
    }

    @ViewBuilder private var content: some View {
        if model.unsupported {
            EmptyStateView(title: "Not on this server", systemImage: "fork.knife",
                           message: "Update the server to keep notes and photos of what you cook.")
        } else if !model.loaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.entries.isEmpty {
            EmptyStateView(title: "Nothing cooked yet", systemImage: "fork.knife",
                           message: "Finish a recipe in cook mode, or tap I made this on a recipe, and it shows up here.")
        } else {
            VerticalScroll {
                LazyVStack(alignment: .leading, spacing: Spacing.m) {
                    ForEach(model.entries) { entry in
                        card(entry)
                            .onAppear { if entry.id == model.entries.last?.id { Task { await model.loadMore(session) } } }
                    }
                    if model.loadingMore { ProgressView().frame(maxWidth: .infinity).padding(.vertical, Spacing.s) }
                }
                .screenPadding().padding(.vertical, Spacing.m)
            }
        }
    }

    private func card(_ entry: CookEntry) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.cookedAt?.formatted(date: .complete, time: .omitted) ?? "Some time ago")
                        .font(.footnote.weight(.semibold)).foregroundStyle(AppColors.textSecondary)
                    if let recipe = entry.recipe, model.recipeID == nil {
                        NavigationLink(value: AppRoute.recipe(recipe.id)) {
                            Text(recipe.title.isEmpty ? "Recipe" : recipe.title)
                                .font(AppTypography.cardTitle).foregroundStyle(AppColors.textPrimary)
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the recipe")
                    }
                }
                Spacer(minLength: 0)
                menu(entry)
            }
            if let photo = entry.photoUrl {
                Button { viewing = entry } label: {
                    RecipeImage(path: photo, title: entry.recipe?.title ?? "", id: entry.id)
                        .frame(maxWidth: .infinity).frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.control))
                        .overlay { if model.working.contains(entry.id) { ProgressView().tint(.white) } }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Photo. Opens full size")
            } else if model.working.contains(entry.id) {
                ProgressView().frame(maxWidth: .infinity)
            }
            if !entry.note.isEmpty {
                Text(entry.note).font(AppTypography.note).foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Spacing.m)
        .background(AppColors.card, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(AppColors.separator, lineWidth: 1))
    }

    private func menu(_ entry: CookEntry) -> some View {
        Menu {
            Button(entry.note.isEmpty ? "Add note" : "Edit note", systemImage: "square.and.pencil") { editing = entry }
            if PhotoCapture.hasCamera {
                Button(entry.hasPhoto ? "Retake photo" : "Take photo", systemImage: "camera") {
                    model.photoTarget = entry.id; showingCamera = true
                }
            }
            Button(entry.hasPhoto ? "Replace photo" : "Choose photo", systemImage: "photo.on.rectangle") {
                model.photoTarget = entry.id; showingLibrary = true
            }
            if entry.hasPhoto {
                Button("Remove photo", systemImage: "photo.badge.minus", role: .destructive) {
                    Task { await model.removePhoto(entry, session) }
                }
            }
            Divider()
            Button("Delete cook", systemImage: "trash", role: .destructive) { deleting = entry }
        } label: {
            Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(AppColors.textSecondary)
                .frame(width: Size.tap, height: Size.tap)
        }
        .accessibilityLabel("Options")
        .disabled(model.working.contains(entry.id))
    }
}

/// Edits one cook's note.
private struct CookNoteSheet: View {
    let entry: CookEntry
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @FocusState private var focused: Bool

    init(entry: CookEntry, onSave: @escaping (String) -> Void) {
        self.entry = entry; self.onSave = onSave
        _note = State(initialValue: entry.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("How did it go? What would you change?", text: $note, axis: .vertical)
                        .lineLimit(4...12).focused($focused)
                } footer: {
                    if let date = entry.cookedAt { Text("Cooked \(date.formatted(date: .abbreviated, time: .shortened))") }
                }
            }
            .appBackground()
            .navigationTitle("Note").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(note); dismiss() }.disabled(note == entry.note)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A cook photo full size, on black, with its date and note.
struct CookPhotoViewer: View {
    let entry: CookEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RecipeImage(path: entry.photoUrl ?? "", title: entry.recipe?.title ?? "", id: entry.id, fit: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Cook photo")
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: Size.tap, height: Size.tap)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .accessibilityLabel("Close")
            .padding(Spacing.m)
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                if let date = entry.cookedAt {
                    Text(date.formatted(date: .long, time: .omitted)).font(.footnote.weight(.semibold))
                }
                if !entry.note.isEmpty { Text(entry.note).font(AppTypography.note) }
            }
            .foregroundStyle(.white)
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
        }
        .statusBarHidden()
    }
}
