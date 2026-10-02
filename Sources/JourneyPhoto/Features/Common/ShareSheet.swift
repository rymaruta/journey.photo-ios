import SwiftUI
import UIKit

/// 共有の画面（`UIActivityViewController`）。`ShareLink` はボタンでしか開けないので、
/// 投稿が終わった時点で自分から開くとき（`ThreadsShare`）に使う。閉じると呼び手の
/// `.sheet` が閉じる（共有した・やめた、のどちらでも）
struct ShareSheet: UIViewControllerRepresentable {

    /// 渡す画像（JPEG などのデータ）と、添える文
    let images: [Data]
    let text: String

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: images.compactMap { UIImage(data: $0) } + [text], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in dismiss() }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    /// **画素だけの JPEG に書き出し直す**（位置・撮影日時・機種などの付帯情報を落とす）。
    /// サーバーの原本（Web から上げたものは GPS 入り）を外へ渡す前に通す。読めなければ nil
    static func pixelsOnly(_ data: Data) -> Data? {
        UIImage(data: data)?.jpegData(compressionQuality: 0.9)
    }
}
