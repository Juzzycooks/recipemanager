import SwiftUI
import PhotosUI

enum EditorMode {
    case create
    case edit(RecipeDetail)
    case imported(ImportPreview)
}

/// One editable line of ingredients or steps (its own row so it can be added, deleted and reordered).
struct LineRow: Identifiable, Hashable {
    let id = UUID()
    var text: String

    static func rows(from text: String) -> [LineRow] {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map { LineRow(text: $0) }
    }
    static func text(from rows: [LineRow]) -> String {
        rows.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

/// Create, edit or review-and-save (after an import) a recipe. Lives inside a NavigationStack owned by the presenter.
struct RecipeEditorView: View {
    @Environment(Session.self) private var session
    @Environment(AppState.self) private var app
    let mode: EditorMode
    let onClose: () -> Void
    let onSaved: (RecipeDetail) -> Void

    @State private var title = ""
    @State private var summary = ""
    @State private var servings = ""
    @State private var prepTime = ""
    @State private var cookTime = ""
    @State private var ingredients: [LineRow] = []
    @State private var steps: [LineRow] = []
    @State private var categoryIds: Set<Int> = []
    @State private var notes = ""
    @State private var sourceUrl = ""
    @State private var categories: [Category] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var existingImage = ""
    @State private var importImageName = ""
    @State private var warning = ""
    @State private var isSaving = false
    @State private var error: String?
    @State private var didLoad = false

    private var editingID: Int? { if case .edit(let r) = mode { r.id } else { nil } }
    private var heading: String { if case .edit = mode { "Edit Recipe" } else { "New Recipe" } }
    private var canSave: Bool { !isSaving && !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        List {
            if !warning.isEmpty {
                Section { Label(warning, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(AppColors.danger) }
                    .listRowBackground(AppColors.card)
            }
            photoSection
            detailsSection
            linesSection("Ingredients", prompt: "Add an ingredient", rows: $ingredients, footer: "Start a line with # for a section heading, like “# For the sauce”.")
            linesSection("Instructions", prompt: "Add a step", rows: $steps, footer: nil)
            if !categories.isEmpty { tagsSection }
            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...8)
                TextField("Source link", text: $sourceUrl).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .listRowBackground(AppColors.card)
        }
        .appBackground()
        .listStyle(.insetGrouped)
        .navigationTitle(heading).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onClose) }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving { ProgressView() } else { Button("Save") { Task { await save() } }.disabled(!canSave) }
            }
        }
        .task { await load() }
        .onChange(of: photoItem) { Task { await loadPhoto() } }
        .errorAlert($error)
        .interactiveDismissDisabled(isSaving)
    }

    // MARK: Sections

    private var photoSection: some View {
        Section {
            ZStack(alignment: .bottom) {
                Group {
                    if let photoData, let image = UIImage(data: photoData) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        RecipeImage(path: existingImage.isEmpty ? importImageName : existingImage, title: title.isEmpty ? "Recipe" : title, id: editingID ?? 0)
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 190).clipped()
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Change Photo", systemImage: "camera").font(.subheadline.weight(.medium)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: Size.tap).background(.black.opacity(0.45))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Title", text: $title)
            TextField("Description", text: $summary, axis: .vertical).lineLimit(1...4)
            LabeledContent("Servings") { TextField("4", text: $servings).multilineTextAlignment(.trailing) }
            LabeledContent("Prep time") { TextField("15 min", text: $prepTime).multilineTextAlignment(.trailing) }
            LabeledContent("Cook time") { TextField("30 min", text: $cookTime).multilineTextAlignment(.trailing) }
        }
        .listRowBackground(AppColors.card)
    }

    private func linesSection(_ title: String, prompt: String, rows: Binding<[LineRow]>, footer: String?) -> some View {
        Section {
            ForEach(rows) { $row in
                TextField(prompt, text: $row.text, axis: .vertical)
                    .font(row.text.hasPrefix("# ") ? .body.weight(.semibold) : .body)
            }
            .onMove { rows.wrappedValue.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { rows.wrappedValue.remove(atOffsets: $0) }
            .environment(\.editMode, .constant(.active))
            Button { withAnimation(.snappy) { rows.wrappedValue.append(LineRow(text: "")) } } label: { Label(prompt, systemImage: "plus.circle.fill") }
        } header: { Text(title) } footer: { if let footer { Text(footer) } }
        .listRowBackground(AppColors.card)
    }

    private var tagsSection: some View {
        Section("Tags") {
            FlowChips(items: categories.map { ($0.id, $0.name) }, selected: $categoryIds)
                .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.m, bottom: Spacing.xs, trailing: Spacing.m))
        }
        .listRowBackground(AppColors.card)
    }

    // MARK: Loading and saving

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        switch mode {
        case .create: break
        case .edit(let r):
            title = r.title; summary = r.description; servings = r.servings; prepTime = r.prepTime; cookTime = r.cookTime
            ingredients = LineRow.rows(from: r.ingredients); steps = LineRow.rows(from: r.instructions)
            categoryIds = Set(r.categories.map(\.id)); notes = r.notes; sourceUrl = r.sourceUrl; existingImage = r.imageUrl
        case .imported(let p):
            let d = p.draft
            title = d.title; summary = d.description; servings = d.servings; prepTime = d.prepTime; cookTime = d.cookTime
            ingredients = LineRow.rows(from: d.ingredients); steps = LineRow.rows(from: d.instructions)
            notes = d.notes; sourceUrl = p.sourceUrl; importImageName = p.imageName; existingImage = p.imageUrl; warning = p.warning
        }
        let cats: ItemList<Category>? = try? await session.run { try await $0.get("/categories") }
        categories = cats?.items ?? []
    }

    private func loadPhoto() async {
        guard let photoItem, let data = try? await photoItem.loadTransferable(type: Data.self) else { return }
        photoData = ImagePrep.jpeg(from: data)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let draft = RecipeDraft(title: title.trimmingCharacters(in: .whitespaces), description: summary, ingredients: LineRow.text(from: ingredients),
                                instructions: LineRow.text(from: steps), prepTime: prepTime, cookTime: cookTime, servings: servings,
                                sourceUrl: sourceUrl, notes: notes, categoryIds: Array(categoryIds).sorted())
        let imageName = importImageName, photo = photoData, mode = mode
        do {
            var saved: RecipeDetail = try await session.run { client in
                switch mode {
                case .edit(let r): return try await client.send("PATCH", "/recipes/\(r.id)", body: draft)
                case .create: return try await client.send("POST", "/recipes", body: draft)
                case .imported:
                    let body = ImportSaveBody(draft: draft, imageName: imageName, useImage: photo == nil)
                    var created: RecipeDetail = try await client.send("POST", "/import/save", body: body)
                    if !draft.categoryIds.isEmpty {
                        struct Cats: Encodable, Sendable { let categoryIds: [Int] }
                        created = try await client.send("PATCH", "/recipes/\(created.id)", body: Cats(categoryIds: draft.categoryIds))
                    }
                    return created
                }
            }
            if let photo {
                struct Uploaded: Decodable, Sendable { let imageUrl: String }
                let id = saved.id
                let _: Uploaded = try await session.run { try await $0.upload("PUT", "/recipes/\(id)/image", field: "image_file",
                                                                             files: [.init(filename: "photo.jpg", mime: "image/jpeg", data: photo)]) }
                saved = try await session.run { try await $0.get("/recipes/\(id)") }
            }
            session.recipesChanged()
            onSaved(saved)
            onClose()
        } catch { self.error = error.localizedDescription }
    }
}

private struct ImportSaveBody: Encodable, Sendable {
    let title: String, description: String, ingredients: String, instructions: String, notes: String
    let servings: String, prepTime: String, cookTime: String, sourceUrl: String, imageName: String, useImage: Bool

    init(draft: RecipeDraft, imageName: String, useImage: Bool) {
        title = draft.title; description = draft.description; ingredients = draft.ingredients; instructions = draft.instructions
        notes = draft.notes; servings = draft.servings; prepTime = draft.prepTime; cookTime = draft.cookTime
        sourceUrl = draft.sourceUrl; self.imageName = imageName; self.useImage = useImage && !imageName.isEmpty
    }
}

extension RecipeDraft {
    init(title: String, description: String, ingredients: String, instructions: String, prepTime: String, cookTime: String,
         servings: String, sourceUrl: String, notes: String, categoryIds: [Int]) {
        self.init()
        self.title = title; self.description = description; self.ingredients = ingredients; self.instructions = instructions
        self.prepTime = prepTime; self.cookTime = cookTime; self.servings = servings; self.sourceUrl = sourceUrl
        self.notes = notes; self.categoryIds = categoryIds
    }
}

enum ImagePrep {
    /// Downscale to 2000px on the long edge and re-encode as JPEG (phone photos are huge; the server resizes anyway).
    static func jpeg(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 2000 / longest)
        guard scale < 1 else { return image.jpegData(compressionQuality: 0.85) }
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.85) { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

/// Wrapping toggle chips (tags).
struct FlowChips: View {
    let items: [(id: Int, name: String)]
    @Binding var selected: Set<Int>

    var body: some View {
        WrapLayout(spacing: Spacing.xs) {
            ForEach(items, id: \.id) { item in
                FilterChip(title: item.name, isSelected: selected.contains(item.id)) {
                    if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                }
            }
        }
    }
}

struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(bounds.width, subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height); maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
