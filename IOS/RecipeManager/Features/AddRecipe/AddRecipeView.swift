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
                    ActionCard(symbol: "link", title: "Import from a URL", subtitle: "Paste a link from any recipe site") { path.append(.url) }
                    ActionCard(symbol: "camera", title: "Scan from a photo", subtitle: "Snap a picture of a recipe") { path.append(.photo) }
                    ActionCard(symbol: "square.and.pencil", title: "Add manually", subtitle: "Enter the details yourself") { path.append(.manual) }
                }
                .screenPadding().padding(.top, Spacing.xl)
            }
            .background(AppColors.background)
            .navigationTitle("Add recipe").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
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
        RecipeEditorView(mode: mode, pushed: true, onClose: { dismiss() }) { saved in
            app.say("Saved “\(saved.title)”.")
            app.open(recipe: saved.id)
        }
    }
}

/// One way in: the accent icon on the accent wash (one accent, not a hue per option), on card stock.
struct ActionCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.m) {
                Image(systemName: symbol).font(.title3).foregroundStyle(AppColors.primary)
                    .frame(width: iconSize, height: iconSize).background(AppColors.accentWash, in: RoundedRectangle(cornerRadius: Radius.control))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(AppColors.textPrimary)
                    Text(subtitle).font(.subheadline).foregroundStyle(AppColors.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(AppColors.textSecondary)
            }
            .padding(Spacing.m).frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(AppColors.card, in: RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(AppColors.separator, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 48
}

// MARK: Import from a link or pasted text

struct ImportURLView: View {
    @Environment(Session.self) private var session
    let onPreview: (ImportPreview) -> Void
    @State private var url = ""
    @State private var pasted = ""
    @State private var showPaste = false
    @State private var working: Source?
    @State private var problem: ImportProblem?
    @FocusState private var focused: Bool

    private enum Source { case link, text }
    private var isWorking: Bool { working != nil }

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
                if let problem { ImportProblemView(problem: problem) }
                PrimaryButton(title: working == .link ? "Reading the page…" : "Import recipe", isLoading: working == .link, action: importLink)
                    .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty || isWorking).opacity(url.isEmpty ? 0.5 : 1)

                DisclosureGroup("Or paste the recipe text", isExpanded: $showPaste) {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("Works for Instagram and TikTok captions, or any copied recipe.").font(.footnote).foregroundStyle(AppColors.textSecondary)
                        TextEditor(text: $pasted).frame(minHeight: 160).scrollContentBackground(.hidden).padding(Spacing.xs)
                            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: Radius.field))
                        SecondaryButton(title: working == .text ? "Reading the text…" : "Read this text") { importText() }
                            .disabled(pasted.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
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
        run(.link) { client in try await client.send("POST", "/import/url", body: ["url": link]) }
    }

    private func importText() {
        let text = pasted
        guard !isWorking else { return }
        run(.text) { client in try await client.send("POST", "/import/caption", body: ["caption": text]) }
    }

    private func run(_ source: Source, _ request: @escaping @Sendable (APIClient) async throws -> ImportPreview) {
        working = source; problem = nil
        let retry = source == .link ? importLink : importText
        Task {
            defer { working = nil }
            do { onPreview(try await session.run(request)) }
            catch let APIError.server(_, code, message) where code == "no_caption" {
                problem = ImportProblem(title: "There's no recipe text in that post", detail: message,
                                        next: "Copy the caption and paste it below instead.", retry: nil)
                showPaste = true
            } catch let e as APIError where e.isOffline {
                problem = ImportProblem(title: "You're offline", detail: nil,
                                        next: "Importing needs your server. Connect to the internet, then try again.", retry: retry)
            } catch {
                problem = source == .link
                    ? ImportProblem(title: "Couldn't read that page", detail: error.localizedDescription,
                                    next: "Check the link opens in Safari, or paste the recipe text below.", retry: retry)
                    : ImportProblem(title: "Couldn't read that text", detail: error.localizedDescription,
                                    next: "Make sure it includes the ingredients and the method, then try again.", retry: retry)
            }
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
    @State private var problem: ImportProblem?

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
                    Label(hasImages ? "Change photos" : "Choose photos", systemImage: "photo.on.rectangle")
                        
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
                if let problem { ImportProblemView(problem: problem) }
                PrimaryButton(title: isWorking ? (images.count == 1 ? "Reading the photo…" : "Reading the photos…") : "Scan recipe",
                              systemImage: "text.viewfinder", isLoading: isWorking, action: scan)
                    .disabled(images.isEmpty || ocrAvailable == false).opacity(images.isEmpty || ocrAvailable == false ? 0.5 : 1)
                if isWorking {
                    Text("This can take up to a minute for several pages.").font(.footnote).foregroundStyle(AppColors.textSecondary)
                }
            }
            .screenPadding().padding(.top, Spacing.m)
        }
        .background(AppColors.background)
        .navigationTitle("Scan from a photo").navigationBarTitleDisplayMode(.inline)
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
        guard !isWorking, !files.isEmpty else { return }
        isWorking = true; problem = nil
        Task {
            defer { isWorking = false }
            do {
                let preview: ImportPreview = try await session.run {
                    try await $0.upload("POST", "/import/photo", field: "photos", files: files, fields: cover ? ["use_as_cover": "1"] : [:])
                }
                onPreview(preview)
            } catch let e as APIError where e.isOffline {
                problem = ImportProblem(title: "You're offline", detail: nil,
                                        next: "Scanning happens on your server. Connect to the internet, then try again.", retry: scan)
            } catch {
                problem = ImportProblem(title: images.count == 1 ? "Couldn't read the photo" : "Couldn't read the photos",
                                        detail: error.localizedDescription,
                                        next: "Try a sharper, well-lit picture with the text straight on, one page per photo.", retry: scan)
            }
        }
    }
}

// MARK: When an import doesn't work

/// What went wrong with an import, what to try next, and (when it could help) a way to try again.
struct ImportProblem {
    let title: String
    /// The server's or the system's own words, kept as the detail.
    let detail: String?
    let next: String
    let retry: (() -> Void)?
}

struct ImportProblemView: View {
    let problem: ImportProblem

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label(problem.title, systemImage: "exclamationmark.triangle").font(.subheadline.weight(.semibold)).foregroundStyle(AppColors.danger)
            if let detail = problem.detail, !detail.isEmpty {
                Text(detail).font(.subheadline).foregroundStyle(AppColors.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
            Text(problem.next).font(.subheadline).foregroundStyle(AppColors.textSecondary).fixedSize(horizontal: false, vertical: true)
            if let retry = problem.retry {
                Button("Try again", systemImage: "arrow.clockwise", action: retry)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(AppColors.primary).frame(minHeight: Size.tap)
            }
        }
        .padding(Spacing.m).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.card, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(AppColors.separator, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .onAppear { UIAccessibility.post(notification: .announcement, argument: problem.title) }
    }
}
