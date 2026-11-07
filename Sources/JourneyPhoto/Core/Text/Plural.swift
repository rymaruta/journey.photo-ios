import Foundation

/// 英語の単複(2026-11-07)。件数が 1 のとき「1 medals」「1 tickets」と出ないようにする。
/// 日本語は数え方が変わらないので使わない(`L("…", Plural.count(n, "medal"))` の英語の側だけ)。
/// `DraftsText`・`PassHomeSlot.countParts` が個別に書いていた `n == 1 ? … : …` と同じ分け方を1か所に集めたもの
enum Plural {

    /// 「3 medals」「1 medal」。`plural` を省くと語尾に s を足す(不規則な語は渡す: `person` → `people`)
    nonisolated static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(n) \(word(n, singular, plural))"
    }

    /// 数を付けない語だけ
    nonisolated static func word(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        n == 1 ? singular : (plural ?? singular + "s")
    }
}
