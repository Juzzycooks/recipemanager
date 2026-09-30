import Foundation
import Observation
import UniformTypeIdentifiers

/// Reads the shared item, asks the server to parse it, and saves the recipe. No UI in here.
@MainActor @Observable
final class ShareModel {
    enum Phase {
        case reading
        case needsSignIn
        case nothingToImport
        case importing
        case review(ImportPreview)
        case saving
        case saved(String)
        case failed(String)
    }

    private(set) var phase = Phase.reading
    var title = ""
    private(set) var client: APIClient?
    private var source: SharedSource?
    private let items: [NSExtensionItem]

    init(items: [NSExtensionItem]) { self.items = items }

    func start() async {
        guard let saved = CredentialStore.read(), let server = URL(string: saved.server) else { phase = .needsSignIn; return }
        client = APIClient(baseURL: server, token: saved.token)
        guard let found = await Self.findSource(in: items) else { phase = .nothingToImport; return }
        source = found
        await parse()
    }

    func retry() async { await parse() }

    private func parse() async {
        guard let client, let source else { return }
        phase = .importing
        do {
            let preview: ImportPreview
            switch source {
            case .link(let url): preview = try await client.send("POST", "/import/url", body: ["url": url.absoluteString])
            case .text(let text): preview = try await client.send("POST", "/import/caption", body: ["caption": text])
            }
            title = preview.draft.title
            phase = .review(preview)
        } catch APIError.unauthorized {
            phase = .needsSignIn
        } catch let APIError.server(_, code, message) where code == "no_caption" {
            phase = .failed(message)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func save(_ preview: ImportPreview) async {
        guard let client else { return }
        phase = .saving
        var body = SaveBody(draft: preview.draft, sourceUrl: preview.sourceUrl, imageName: preview.imageName)
        body.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? preview.draft.title : title
        do {
            let saved: SavedRecipe = try await client.send("POST", "/import/save", body: body)
            phase = .saved(saved.title)
        } catch APIError.unauthorized {
            phase = .needsSignIn
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: Reading the shared item

    /// A web link if there is one (Safari, most apps); otherwise a link inside shared text (Instagram shares a
    /// caption with a link); otherwise long shared text is treated as a pasted recipe.
    static func findSource(in items: [NSExtensionItem]) async -> SharedSource? {
        var texts: [String] = []
        for item in items {
            if let attributed = item.attributedContentText?.string, !attributed.isEmpty { texts.append(attributed) }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let value = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) {
                    if let url = value as? URL, url.scheme?.hasPrefix("http") == true { return .link(url) }
                    if let text = value as? String, let url = SharedContent.firstWebLink(in: text) { return .link(url) }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let value = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    texts.append(value)
                }
            }
        }
        return SharedContent.source(fromText: texts)
    }
}

struct SavedRecipe: Decodable, Sendable { let id: Int; let title: String }

/// Same fields the app sends to /import/save.
struct SaveBody: Encodable, Sendable {
    var title: String
    let description: String, ingredients: String, instructions: String, notes: String
    let servings: String, prepTime: String, cookTime: String
    let sourceUrl: String, imageName: String, useImage: Bool

    init(draft: ImportDraft, sourceUrl: String, imageName: String) {
        title = draft.title; description = draft.description; ingredients = draft.ingredients
        instructions = draft.instructions; notes = draft.notes; servings = draft.servings
        prepTime = draft.prepTime; cookTime = draft.cookTime
        self.sourceUrl = sourceUrl; self.imageName = imageName; useImage = !imageName.isEmpty
    }
}
