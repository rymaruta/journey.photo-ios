import SwiftUI

/// シートの「閉じる」。**シートの一番上の画面の `toolbar` の左上（`cancellationAction`）に置く。**
///
/// 置き忘れると、閉じる手段が「下へ払う」だけになる。払えることに
/// 気づかない人には「開いたら閉じられない」画面に見える（2026-09-25 に
/// owner がお知らせとストーリーで踏んだ）:
///
///     .toolbar {
///         ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
///     }
///
/// 🔴 **閉じるは左上・右上は決める操作だけ（2026-11-13 owner 承認・#187）。** 前は右上のガラスの「閉じる」・
/// 左上の ×・右上の ×・真鍮や白の字だけの「閉じる」が画面ごとにばらばらだった。右上は「保存」「投稿する」など
/// 決める操作だけに空ける。上のバーが無いシート（見出しを中身に置く札・トランクの舞台）は、見出しの行の
/// **左端**に `SheetCloseButton(onContent: true)` を置く——バーの「閉じる」と同じ字・同じガラス（板の
/// 「ガラス」= 黒 55%＋ぼかし＋白 10% の縁・`jpGlass`）。固定は `SheetClosePlacementTests`。
///
/// `ViewModifier` にしないのは `Shims/` の模型が持っていないため
/// （`WebTheme.webScreen` と同じ理由）。
struct SheetCloseButton: View {

    /// 上のバーの外（中身の見出しの行）に置くとき true。バーの中は系統がガラスにするので、外だけ自分で付ける
    var onContent: Bool = false
    /// 閉じ方が `dismiss` でない札（親の状態を空けて閉じる・行った県の札）だけ渡す
    var action: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if onContent {
            Button(action: close) {
                Text(Labels.Common.close)
                    .font(.body)
                    .foregroundStyle(WebTheme.foreground)
                    .padding(.horizontal, JPSpace.s)
                    .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                    .jpGlass(in: Capsule())
                    // 見出しの行の左端＝シートの左上の角。当たりは角の側へ 60pt 四方まで（`CornerTapArea`・2026-11-14）
                    .cornerTapArea(.topLeading)
            }
            .buttonStyle(.plain)
        } else {
            // バーの中は系統の形のまま（iOS 26 はガラス）。当たりは 44pt（板の決まり）——
            // 近くの写真の「閉じる」が前からこの形でバーに置き、UI テストで 44pt を確かめていた
            Button(action: close) {
                Text(Labels.Common.close)
                    .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
            }
        }
    }

    private func close() {
        if let action { action() } else { dismiss() }
    }
}
