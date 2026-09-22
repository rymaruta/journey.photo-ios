import Foundation

/// 撮影地の突き合わせ。**Web と同じ規則・同じ向き**。
///
/// 🔴 **向きが要る。** アプリは対称に見ていた
/// （`location.contains(needle) || needle.contains(location)`）が、
/// Web は 2026 年に**その対称版を名指しで捨てている**
/// （`lib/utils/related.ts` の `photoIsInLocation`）:
///
///     ページ「フィンランド」            ← 写真「ヘルシンキ, フィンランド」  ○
///     ページ「ヘルシンキ, フィンランド」← 写真「フィンランド」              ✗
///
/// 対称のままだと**広い場所の写真が狭いページに載る**。Web の実測では
/// `/location/ロヴァニエミ,-フィンランド` が7枚を並べていた（実際に
/// ロヴァニエミで撮ったのは1枚）。
///
/// アプリでも run 55 の実機の絵に出ていた:
///
///  - 「フランス ヴェルサイユ」のスポットが **3枚**（実際は2枚＋
///    撮影地が「フランス」の1枚）
///  - その「フランス」が **1km 以内の近くのスポット**として並んでいた
///  - 「探す」の札は **2枚**、開いた先は **3枚**（数が食い違う）
///
/// **集めるときは向きを見る**（`photoIsIn`）。写真ページの回遊のような
/// 「近くの写真を出す」用途だけが対称でよい（`same`）——Web の
/// `sameLocation` と同じ住み分け。
enum LocationMatch {

    /// Web の `normalizeLocation`: 前後を落とし・小文字にし・**空白を全部抜く**
    static func normalized(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    /// **その写真は、この見出しのページに載るか。**
    /// 条件は「写真の撮影地が、見出しと同じか**より細かい**」。
    ///
    /// 1文字は通さない（Web と同じ）——`「都」`のような欠片が
    /// 全部の地名に当たってしまう。
    static func photoIsIn(_ photoLocation: String?, _ pageLabel: String?) -> Bool {
        let photo = normalized(photoLocation)
        let page = normalized(pageLabel)
        guard photo.count >= 2, page.count >= 2 else { return false }
        return photo.contains(page)
    }

    /// **同じ場所とみなせるか**（向きを見ない）。回遊の導線用。
    /// 集約には使わない——`photoIsIn` を使う
    static func same(_ a: String?, _ b: String?) -> Bool {
        let na = normalized(a)
        let nb = normalized(b)
        guard na.count >= 2, nb.count >= 2 else { return false }
        return na == nb || na.contains(nb) || nb.contains(na)
    }
}
