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
        // **文はクリップボードにも置く。** 共有の画面から文を受け取らないアプリがある
        // （Instagram・Facebook は写真だけ入る）。そのときも貼り付ければ同じ文が載る。
        // **この端末だけ・10分で消える**（ほかの端末へ同期させない・ずっと残さない）。
        // コピーしたことは呼び手の画面の説明（「文はコピーされます」）で伝えている
        if !text.isEmpty {
            UIPasteboard.general.setItems([["public.utf8-plain-text": text]],
                                          options: [.localOnly: true,
                                                    .expirationDate: Date().addingTimeInterval(600)])
        }
        let controller = UIActivityViewController(
            activityItems: images.compactMap { UIImage(data: $0) } + [text], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in dismiss() }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
