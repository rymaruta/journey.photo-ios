import SwiftUI
import UIKit
// 撮影情報の辞書の鍵（`CFString`）
import ImageIO

/// カメラで撮った1枚。**JPEG にするのは受け取った側が画面の処理の外で**（`jpegData()`）。
///
/// 🔴 撮った画像（約1200万画素）を `jpegData(compressionQuality: 1.0)` にすると数百ミリ秒かかる。
/// 以前は撮影の画面の知らせ（主スレッド）の上でしていて、閉じるまで画面が止まっていた
struct CameraCapture: @unchecked Sendable {
    /// カメラが付けた撮影情報（`{Exif}`・`{TIFF}`）。撮影日時・機種を読む（`ImagePreparer.applyingCaptureInfo`）
    let metadata: [CFString: Any]
    /// 撮った時刻（撮影情報に撮影日時が無いときの撮影日）
    let capturedAt: Date
    private let encode: () -> Data?

    init(image: UIImage, metadata: [CFString: Any], capturedAt: Date) {
        self.metadata = metadata
        self.capturedAt = capturedAt
        // **ここでは品質を落とさない。** 縮小と再エンコードは
        // `ImagePreparer` の仕事で、二重に潰すと目に見えて汚くなる
        self.encode = { image.jpegData(compressionQuality: 1.0) }
    }

    /// 試験用（模型の `UIImage` は JPEG にできない）
    init(metadata: [CFString: Any], capturedAt: Date, encode: @escaping () -> Data?) {
        self.metadata = metadata
        self.capturedAt = capturedAt
        self.encode = encode
    }

    /// JPEG にする。**重いので画面の処理の外で呼ぶ**
    func jpegData() -> Data? { encode() }

    /// カメラの撮影情報（文字列の鍵）を、`ImagePreparer` が読む形（CFString の鍵）にする。
    /// 入れ子の辞書（`{Exif}`・`{TIFF}`）も同じく移す
    static func metadata(from raw: [String: Any]) -> [CFString: Any] {
        var out: [CFString: Any] = [:]
        for (key, value) in raw {
            if let nested = value as? [String: Any] {
                out[key as CFString] = metadata(from: nested)
            } else {
                out[key as CFString] = value
            }
        }
        return out
    }
}

/// その場で撮る。
///
/// **ガイドライン 4.2 の要。** 「Web サイトを包んだだけ」と見なされないため、
/// ネイティブでしかできないことが要る。カメラからの投稿がその本命で、
/// ここで撮った画像は `ImagePreparer` を通って EXIF を落としてから上がる。
/// 撮った原本は端末の写真にも保存する（投稿しなくても残る）。
///
/// `PhotosPicker` と違い、カメラは `UIImagePickerController` が要る
/// （SwiftUI に相当品がない）。
struct CameraPicker: UIViewControllerRepresentable {

    /// 撮れた1枚。閉じただけなら呼ばれない。**JPEG にするのは受け取った側**（画面の処理の外で）
    let onCapture: (CameraCapture) -> Void

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

        private let onCapture: (CameraCapture) -> Void
        private let dismiss: () -> Void

        init(onCapture: @escaping (CameraCapture) -> Void, dismiss: @escaping () -> Void) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            defer { dismiss() }
            guard let image = info[.originalImage] as? UIImage else { return }
            // 🔴 **撮った写真は端末にも残す。** この画面のカメラは写真アプリに
            // 保存しないので、投稿せずに閉じる・投稿に失敗して諦めると、撮った
            // 写真がどこにも残らなかった（`NSPhotoLibraryAddUsageDescription` は
            // このために宣言してある）。断られていたら黙って何もしない。
            // **画面の処理の外で**（書き出しに画像の変換が入る。主スレッドの外から呼んでよいことは
            // 実機で確かめていない——落ちる・保存されないなら主スレッドに戻す）
            Task.detached(priority: .utility) {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
            // **`[String: Any]` で受ける**（`NSDictionary` から CFString の鍵の辞書へ直に変えると
            // 失敗しうる）。鍵は同じ文字列なので、読む側の形（CFString の鍵）へは1つずつ移す
            let raw = info[.mediaMetadata] as? [String: Any] ?? [:]
            onCapture(CameraCapture(image: image, metadata: CameraCapture.metadata(from: raw), capturedAt: Date()))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
