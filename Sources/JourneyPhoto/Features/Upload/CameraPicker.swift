import SwiftUI
import UIKit

/// その場で撮る。
///
/// **ガイドライン 4.2 の要。** 「Web サイトを包んだだけ」と見なされないため、
/// ネイティブでしかできないことが要る。カメラからの投稿がその本命で、
/// ここで撮った画像は `ImagePreparer` を通って EXIF を落としてから上がる。
///
/// `PhotosPicker` と違い、カメラは `UIImagePickerController` が要る
/// （SwiftUI に相当品がない）。
struct CameraPicker: UIViewControllerRepresentable {

    /// 撮れた画像の JPEG データ。閉じただけなら呼ばれない
    let onCapture: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    /// 実機にカメラが無い（シミュレータ）ときは出さない
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

        private let onCapture: (Data) -> Void
        private let dismiss: () -> Void

        init(onCapture: @escaping (Data) -> Void, dismiss: @escaping () -> Void) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            defer { dismiss() }
            guard let image = info[.originalImage] as? UIImage else { return }
            // **ここでは品質を落とさない。** 縮小と再エンコードは
            // `ImagePreparer` の仕事で、二重に潰すと目に見えて汚くなる
            guard let data = image.jpegData(compressionQuality: 1.0) else { return }
            onCapture(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
