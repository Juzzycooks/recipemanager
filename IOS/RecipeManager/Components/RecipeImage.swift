import SwiftUI

/// Every picture in the app goes through here: server image when there is one,
/// otherwise a tinted letter tile (never a grey "no image" box). Pictures are saved on the phone the first time they load.
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
            StoredImage(url: url) { tile }
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

/// Shows a picture from the on-disk store, downloading it once if it isn't there yet.
private struct StoredImage<Fallback: View>: View {
    let url: URL
    @ViewBuilder let fallback: Fallback
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image = image ?? ImageStore.shared.cachedImage(url) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                fallback
            } else {
                AppColors.surface.overlay(ProgressView())
            }
        }
        .task(id: url) {
            failed = false
            if let loaded = await ImageStore.shared.image(url) { image = loaded } else { failed = true }
        }
    }
}
