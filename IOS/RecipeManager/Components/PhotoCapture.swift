import PhotosUI
import SwiftUI
import UIKit

/// Taking or choosing a photo (cook photos). Attach `.photoCapture(camera:library:onPicked:)` to a view and set either
/// binding to show the camera or the photo library; the picked picture arrives as a JPEG prepared like a recipe photo
/// (`ImagePrep`: at most 2000 px on the long edge).
enum PhotoCapture {
    /// False in the simulator and on devices without a camera (then only the library is offered).
    @MainActor static var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
}

extension View {
    func photoCapture(camera: Binding<Bool>, library: Binding<Bool>, onPicked: @escaping (Data) -> Void) -> some View {
        modifier(PhotoCaptureModifier(camera: camera, library: library, onPicked: onPicked))
    }
}

private struct PhotoCaptureModifier: ViewModifier {
    @Binding var camera: Bool
    @Binding var library: Bool
    let onPicked: (Data) -> Void
    @State private var item: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $library, selection: $item, matching: .images)
            .onChange(of: item) {
                guard let picked = item else { return }
                item = nil
                Task {
                    if let data = try? await picked.loadTransferable(type: Data.self), let jpeg = ImagePrep.jpeg(from: data) { onPicked(jpeg) }
                }
            }
            .fullScreenCover(isPresented: $camera) {
                CameraPicker { image in if let jpeg = ImagePrep.jpeg(from: image) { onPicked(jpeg) } }
                    .ignoresSafeArea()
            }
    }
}

/// The system camera (`UIImagePickerController`), which SwiftUI has no view for.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
