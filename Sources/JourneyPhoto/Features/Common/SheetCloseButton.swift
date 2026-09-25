import SwiftUI

/// シートの「閉じる」。**シートの一番上の画面の `toolbar` に置く。**
///
/// 置き忘れると、閉じる手段が「下へ払う」だけになる。払えることに
/// 気づかない人には「開いたら閉じられない」画面に見える（2026-09-25 に
/// owner がお知らせとストーリーで踏んだ）。置き場所はほかのシート
/// （写真の編集・曲の選択）と同じ `cancellationAction`:
///
///     .toolbar {
///         ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
///     }
///
/// `ViewModifier` にしないのは `Shims/` の模型が持っていないため
/// （`WebTheme.webScreen` と同じ理由）。
struct SheetCloseButton: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(Labels.Common.close) { dismiss() }
    }
}
