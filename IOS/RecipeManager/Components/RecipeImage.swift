import SwiftUI

/// Every picture in the app goes through here: server image when there is one,
/// otherwise a tinted letter tile (never a grey "no image" box). Swap the loader here to add caching later.
struct RecipeImage: View {
    @Environment(Session.self) private var session
    let path: String
    let title: String
    let id: Int

    var body: some View {
        // Color.clear takes whatever size the parent offers; the picture is only painted into it and clipped.
        // (A scaledToFill photo sizing itself made very wide or tall pictures blow the card layout apart.)
        Color.clear
            .overlay { content }
            .clipped()
    }

    @ViewBuilder private var content: some View {
        if let url = session.imageURL(path) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                case .failure: tile
                default: AppColors.surface.overlay(ProgressView())
                }
            }
        } else {
            tile
        }
    }

    private var tile: some View {
        let tint = AppColors.tiles[abs(id) % AppColors.tiles.count]
        return tint.wash.overlay(
            Text(String(title.trimmingCharacters(in: .whitespaces).first ?? "?").uppercased())
                .font(.system(size: 44, weight: .semibold, design: .serif))
                .foregroundStyle(tint.ink))
    }
}
