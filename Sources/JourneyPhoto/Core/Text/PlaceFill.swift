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
}
