import Foundation

/// 撮影地を自動で入れてよいか。
///
/// **`@MainActor` の型に置かない**（`TagInput` と同じ理由——テストから呼べなくなる）。
enum PlaceFill {

    /// 入れる値。`nil` は「触らない」。
    ///
    /// **打ってあるものは奪わない。** 本人が入れた固有名詞（高屋神社）の方が、
    /// 座標から引ける市区町村（観音寺市）より検索で効く。引いている最中に
    /// 打ち始めた人からも奪わないよう、**入れる直前にもう一度ここを通す**。
    static func value(current: String, found: String?) -> String? {
        guard current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let found else { return nil }
        let trimmed = found.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 写真を選び直したときに残す撮影地。
    ///
    /// **自動で入れたものだけ消す。** 京都の写真で自動補完 → 札幌の写真に
    /// 差し替え、で「撮影地 京都・座標 札幌」の投稿ができてしまう。
    /// 手で打ったものは、写真を替えても本人のものなので残す。
    static func keptForNewPhoto(current: String, autoFilled: String?) -> String {
        guard let autoFilled, current == autoFilled else { return current }
        return ""
    }
}
