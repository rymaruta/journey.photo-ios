import Foundation

/// 取り消せない操作の前に打たせる語。
///
/// **その人の言葉で打たせる。** 日本語に固定していたので、英語の端末には
/// `Type “削除” to confirm` と出ていた——日本語入力を持たない人は
/// **アプリから退会できない**（審査 5.1.1(v) を見るのはたいてい英語の審査官）。
///
/// **`@MainActor` の型に置かない**（`TagInput` と同じ理由。4回目）。
enum ConfirmWord {

    /// 退会の確認語。
    static var delete: String { L("削除", "DELETE") }

    /// **大小と全角半角を区別しない。** 入力欄は自動大文字化を切ってあるので
    /// `delete` と打つ人が出る——灰色のまま理由も出ない画面にしない。
    static func matches(_ typed: String, word: String) -> Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare(word, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame
    }
}
