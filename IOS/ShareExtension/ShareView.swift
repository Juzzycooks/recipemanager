import SwiftUI

/// "Save to Spoonmate": a short sheet that shows what was found and saves it.
struct ShareView: View {
    @Bindable var model: ShareModel
    let finish: () -> Void
    let cancel: () -> Void

    private let green = Color(red: 0.153, green: 0.306, blue: 0.231)

    var body: some View {
        NavigationStack {
            content
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Save to Spoonmate").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) } }
        }
        .tint(green)
        .task { await model.start() }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .reading, .importing:
            status("Reading the recipe…", showsProgress: true)
        case .saving:
            status("Saving…", showsProgress: true)
        case .needsSignIn:
            message("Sign in first", symbol: "person.crop.circle.badge.exclamationmark",
                    detail: "Open Spoonmate and sign in, then share this page again.")
        case .nothingToImport:
            message("Nothing to save", symbol: "link.badge.plus",
                    detail: "Share a page that has a recipe on it, or select the recipe text and share that.")
        case .failed(let text):
            VStack(spacing: 16) {
                message("Couldn't save that", symbol: "exclamationmark.triangle", detail: text)
                Button("Try again") { Task { await model.retry() } }.buttonStyle(.borderedProminent)
            }
        case .saved(let title):
            message("Saved", symbol: "checkmark.circle.fill", detail: "“\(title)” is in your recipes.")
                .task { try? await Task.sleep(for: .seconds(1.3)); finish() }
        case .review(let preview):
            review(preview)
        }
    }

    private func review(_ preview: ImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !preview.imageUrl.isEmpty, let url = model.client?.resolve(preview.imageUrl) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { Color(.secondarySystemFill) }
                }
                .frame(height: 150).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            }
            TextField("Title", text: $model.title)
                .font(.title3.weight(.semibold)).padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            Text(summary(of: preview.draft)).font(.subheadline).foregroundStyle(.secondary)
            if !preview.warning.isEmpty {
                Label(preview.warning, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            }
            Button { Task { await model.save(preview) } } label: {
                Text("Save Recipe").fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(model.title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func summary(of draft: ImportDraft) -> String {
        func count(_ text: String) -> Int { text.split(separator: "\n").filter { !$0.hasPrefix("# ") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count }
        let i = count(draft.ingredients), s = count(draft.instructions)
        return "\(i) ingredient\(i == 1 ? "" : "s") · \(s) step\(s == 1 ? "" : "s")"
    }

    private func status(_ text: String, showsProgress: Bool) -> some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text(text).foregroundStyle(.secondary)
        }
        .padding(.top, 60)
    }

    private func message(_ title: String, symbol: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(green)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 50)
    }
}
