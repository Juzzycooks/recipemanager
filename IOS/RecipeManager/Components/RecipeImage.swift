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

    /// The recipe's first letter as written (never uppercased), in Alegreya bold italic on one of the four tints.
    private var tile: some View {
        let tint = AppColors.tiles[abs(id) % AppColors.tiles.count]
        return tint.wash.overlay {
            GeometryReader { geo in
                Text(String(title.trimmingCharacters(in: .whitespaces).first ?? "?"))
                    .font(AppTypography.monogram(size: min(max(20, min(geo.size.width, geo.size.height) * 0.5), 120)))
                    .foregroundStyle(tint.ink)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
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
