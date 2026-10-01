import SwiftUI
import PhotosUI

/// The Add sheet: three ways in, all ending in the editor so you can review before saving.
struct AddRecipeView: View {
    private enum Step: Hashable { case url, photo, manual, review(ReviewBox) }
    /// `ImportPreview` isn't Hashable; boxing it by identity lets it ride in the navigation path.
    struct ReviewBox: Hashable {
        let id = UUID(); let preview: ImportPreview
        static func == (l: Self, r: Self) -> Bool { l.id == r.id }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @State private var path: [Step] = []

    var body: some View {
        NavigationStack(path: $path) {
            VerticalScroll {
                VStack(spacing: Spacing.m) {
                    ActionCard(symbol: "link", tint: AppColors.secondary, title: "Import from a URL", subtitle: "Paste a link from any recipe site") { path.append(.url) }
                    ActionCard(symbol: "camera", tint: AppColors.favorite, title: "Scan from a Photo", subtitle: "Snap a picture of a recipe") { path.append(.photo) }
                    ActionCard(symbol: "square.and.pencil", tint: AppColors.star, title: "Add Manually", subtitle: "Enter the details yourself") { path.append(.manual) }
                }
                .screenPadding().padding(.top, Spacing.xl)
            }
            .background(AppColors.background)
            .navigationTitle("Add Recipe").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {}.disabled(true) }
            }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .url: ImportURLView { path.append(.review(ReviewBox(preview: $0))) }
                case .photo: PhotoImportView { path.append(.review(ReviewBox(preview: $0))) }
                case .manual: editor(.create)
                case .review(let box): editor(.imported(box.preview))
                }
            }
        }
    }

    private func editor(_ mode: EditorMode) -> some View {
        RecipeEditorView(mode: mode, onClose: { dismiss() }) { saved in
            app.say("Saved “\(saved.title)”.")
            app.open(recipe: saved.id)
        }
    }
}

struct ActionCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.m) {
                Image(systemName: symbol).font(.title3).foregroundStyle(.white)
                    .frame(width: 48, height: 48).background(tint, in: RoundedRectangle(cornerRadius: Radius.field))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(AppColors.textPrimary)
                    Text(subtitle).font(.subheadline).foregroundStyle(AppColors.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(AppColors.textSecondary)
            }
            .padding(Spacing.m).frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(AppColors.card, in: RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(AppColors.separator, lineWidth: 0.5))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: Import from a link or pasted text

struct ImportURLView: View {
    @Environment(Session.self) private var session
    let onPreview: (ImportPreview) -> Void
    @State private var url = ""
    @State private var pasted = ""
    @State private var showPaste = false
    @State private var isWorking = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VerticalScroll {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("Paste a link to a recipe. We'll read the ingredients and method, and you can check them before saving.")
                    .foregroundStyle(AppColors.textSecondary)
                HStack {
                    TextField("https://…", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focused).submitLabel(.go).onSubmit { importLink() }
                    Button("Paste", systemImage: "doc.on.clipboard") { if let s = UIPasteboard.general.string { url = s } }.labelStyle(.iconOnly)
                        .frame(width: Size.tap, height: Size.tap).accessibilityLabel("Paste from clipboard")
                }
                .padding(.horizontal, Spacing.m).frame(minHeight: 52)
                .background(AppColors.surface, in: RoundedRectangle(cornerRadius: Radius.field))
                if let error { Text(error).font(.subheadline).foregroundStyle(AppColors.danger) }
                PrimaryButton(title: "Import Recipe", isLoading: isWorking, action: importLink)
                    .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty).opacity(url.isEmpty ? 0.5 : 1)

                DisclosureGroup("Or paste the recipe text", isExpanded: $showPaste) {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("Works for Instagram and TikTok captions, or any copied recipe.").font(.footnote).foregroundStyle(AppColors.textSecondary)
                        TextEditor(text: $pasted).frame(minHeight: 160).scrollContentBackground(.hidden).padding(Spacing.xs)
                            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: Radius.field))
                        SecondaryButton(title: "Read this text") { importText() }.disabled(pasted.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.top, Spacing.xs)
                }
                .tint(AppColors.textPrimary).foregroundStyle(AppColors.textPrimary)
            }
            .screenPadding().padding(.top, Spacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColors.background)
        .navigationTitle("Import from a URL").navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
    }

    private func importLink() {
        let link = url.trimmingCharacters(in: .whitespaces)
        guard !link.isEmpty, !isWorking else { return }
        run { client in try await client.send("POST", "/import/url", body: ["url": link]) }
    }

    private func importText() {
        let text = pasted
        run { client in try await client.send("POST", "/import/caption", body: ["caption": text]) }
    }

    private func run(_ request: @escaping @Sendable (APIClient) async throws -> ImportPreview) {
        isWorking = true; error = nil
        Task {
            defer { isWorking = false }
            do { onPreview(try await session.run(request)) }
            catch let APIError.server(_, code, message) where code == "no_caption" { error = message; showPaste = true }
            catch { self.error = error.localizedDescription }
        }
    }
}

// MARK: Scan from photos

struct PhotoImportView: View {
    @Environment(Session.self) private var session
    let onPreview: (ImportPreview) -> Void
    @State private var items: [PhotosPickerItem] = []
    @State private var images: [Data] = []
    @State private var useAsCover = true
    @State private var ocrAvailable: Bool?
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        VerticalScroll {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("Choose photos or screenshots of a recipe, in order. We'll read the text on them.").foregroundStyle(AppColors.textSecondary)
                if ocrAvailable == false {
                    Label("Photo scanning isn't set up on your server yet (it needs Tesseract).", systemImage: "exclamationmark.triangle")
                        .font(.subheadline).foregroundStyle(AppColors.danger)
                }
                let hasImages = !images.isEmpty
                let tint = AppColors.primary
                PhotosPicker(selection: $items, maxSelectionCount: 6, matching: .images) {
                    Label(hasImages ? "Change Photos" : "Choose Photos", systemImage: "photo.on.rectangle")
                        
                        .fontWeight(.semibold).foregroundStyle(tint)
                        .frame(maxWidth: .infinity, minHeight: 52).background(AppColors.surface, in: RoundedRectangle(cornerRadius: Radius.field))
                }
                if !images.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.xs) {
                            ForEach(Array(images.enumerated()), id: \.offset) { _, data in
                                if let ui = UIImage(data: data) {
                                    Image(uiImage: ui).resizable().scaledToFill().frame(width: 96, height: 128)
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.small)).accessibilityLabel("Selected photo")
                                }
                            }
                        }
                    }
                    Toggle("Use the first photo as the cover", isOn: $useAsCover).tint(AppColors.primary)
                }
                if let error { Text(error).font(.subheadline).foregroundStyle(AppColors.danger) }
                PrimaryButton(title: "Scan Recipe", systemImage: "text.viewfinder", isLoading: isWorking, action: scan)
                    .disabled(images.isEmpty || ocrAvailable == false).opacity(images.isEmpty || ocrAvailable == false ? 0.5 : 1)
            }
            .screenPadding().padding(.top, Spacing.m)
        }
        .background(AppColors.background)
        .navigationTitle("Scan from a Photo").navigationBarTitleDisplayMode(.inline)
        .task { ocrAvailable = (try? await session.run { try await $0.get("/site") as SiteInfo })?.ocrAvailable }
        .onChange(of: items) { Task { await load() } }
    }

    private func load() async {
        var loaded: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let jpeg = ImagePrep.jpeg(from: data) { loaded.append(jpeg) }
        }
        images = loaded
    }

    private func scan() {
        let files = images.enumerated().map { APIClient.UploadFile(filename: "page\($0.offset + 1).jpg", mime: "image/jpeg", data: $0.element) }
        let cover = useAsCover
        isWorking = true; error = nil
        Task {
            defer { isWorking = false }
            do {
                let preview: ImportPreview = try await session.run {
                    try await $0.upload("POST", "/import/photo", field: "photos", files: files, fields: cover ? ["use_as_cover": "1"] : [:])
                }
                onPreview(preview)
            } catch { self.error = error.localizedDescription }
        }
    }
}
