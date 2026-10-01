import SwiftUI

@MainActor @Observable
final class CollectionsModel {
    var collections: [CollectionSummary] = []
    var hasLoaded = false
    var error: String?

    func load(_ session: Session) async {
        do {
            let result: ItemList<CollectionSummary> = try await session.run { try await $0.get("/collections") }
            collections = result.items; error = nil
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch { self.error = error.localizedDescription }
        hasLoaded = true
    }
}

struct CollectionsView: View {
    private enum Segment: String, CaseIterable, Identifiable { case mine = "My Collections", shared = "Shared"; var id: String { rawValue } }

    @Environment(Session.self) private var session
    @State private var model = CollectionsModel()
    @State private var segment = Segment.mine
    @State private var showingNew = false
    @State private var path: [AppRoute] = []

    private var visible: [CollectionSummary] {
        segment == .mine ? model.collections : model.collections.filter { $0.shareUrl != nil }
    }
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Spacing.s, alignment: .top)]

    var body: some View {
        NavigationStack(path: $path) {
            VerticalScroll {
                VStack(spacing: Spacing.m) {
                    Picker("Show", selection: $segment) { ForEach(Segment.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).screenPadding()
                    if visible.isEmpty && model.hasLoaded {
                        EmptyStateView(title: segment == .mine ? "No collections yet" : "Nothing shared",
                                       systemImage: segment == .mine ? "books.vertical" : "link",
                                       message: segment == .mine ? "Group recipes into themed sets, like Weeknight Dinners." : "Collections you give a public link show up here.",
                                       actionTitle: segment == .mine ? "New Collection" : nil) { showingNew = true }
                            .padding(.top, Spacing.xl)
                    } else {
                        LazyVGrid(columns: columns, spacing: Spacing.s) {
                            ForEach(visible) { c in
                                NavigationLink(value: AppRoute.collection(c.id)) { CollectionCard(collection: c) }.buttonStyle(.plain)
                            }
                        }
                        .screenPadding()
                    }
                }
                .padding(.bottom, Spacing.xl)
            }
            .background(AppColors.background)
            .navigationTitle("Collections")
            .appDestinations()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("New collection", systemImage: "plus") { showingNew = true } }
            }
            .task(id: session.dataVersion) { await model.load(session) }
            .refreshable { await model.load(session) }
            .sheet(isPresented: $showingNew) {
                CollectionEditorSheet(collection: nil) { saved in
                    session.recipesChanged()
                    path.append(.collection(saved.id))
                }
            }
            .errorAlert($model.error)
        }
    }
}

/// Create or rename a collection.
struct CollectionEditorSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let collection: CollectionDetail?
    let onSaved: (CollectionDetail) -> Void

    private struct Payload: Encodable, Sendable { let name: String; let description: String }
    @State private var name = ""
    @State private var description = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Name", text: $name) }
                Section("Description") { TextField("Optional", text: $description, axis: .vertical).lineLimit(1...4) }
            }
            .appBackground()
            .navigationTitle(collection == nil ? "New Collection" : "Edit Collection").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { if let collection { name = collection.name; description = collection.description } }
            .errorAlert($error)
        }
        .presentationDetents([.medium])
    }

    private func save() {
        isSaving = true
        let body = Payload(name: name.trimmingCharacters(in: .whitespaces), description: description), id = collection?.id
        Task {
            defer { isSaving = false }
            do {
                let saved: CollectionDetail = try await session.run { client in
                    if let id { return try await client.send("PATCH", "/collections/\(id)", body: body) }
                    return try await client.send("POST", "/collections", body: body)
                }
                dismiss(); onSaved(saved)
            } catch { self.error = error.localizedDescription }
        }
    }
}
