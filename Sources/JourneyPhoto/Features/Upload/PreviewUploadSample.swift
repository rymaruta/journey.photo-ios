import UIKit

/// 画面写真の試験で投稿画面に入れる見本の1枚（`PreviewSession.opensUploadSample`・Debug のみ）。
///
/// **アプリに入っている画像を使う**（構図の見本の1枚・`Assets.xcassets`）。写真のライブラリにも
/// 通信にも頼らない。鍵の無いときは nil（ふだんの投稿画面は何も変わらない）
enum PreviewUploadSample {

    /// 見本に使う画像の名前（`Assets.xcassets` の構図の見本）
    static let assetName = "composition-ai-radial"

    static func capture() -> CameraCapture? {
        guard PreviewSession.opensUploadSample else { return nil }
        return CameraCapture(metadata: [:], capturedAt: Date(), encode: {
            UIImage(named: assetName)?.jpegData(compressionQuality: 0.9)
        })
    }
}
