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
        return photo == page || contains(photoLocation, pageLabel)
    }

    /// **同じ場所とみなせるか**（向きを見ない）。回遊の導線用。
    /// 集約には使わない——`photoIsIn` を使う
    static func same(_ a: String?, _ b: String?) -> Bool {
        let na = normalized(a)
        let nb = normalized(b)
        guard na.count >= 2, nb.count >= 2 else { return false }
        return na == nb || contains(a, b) || contains(b, a)
    }

    // MARK: - 「名前として含む」（2026-09-30・Web の `locationContains` と同じ規則）
    //
    // 🔴 以前は字の包含（`photo.contains(page)`）だった。蔵王キツネ村の撮影地は
    // 「蔵王キツネ村, 南蔵王七ヶ宿線, **福岡**八宮, 白石市, 宮城県, …」で、
    // 宮城県白石市の大字「福岡八宮」の中の「福岡」に当たり、**「福岡」の撮影地に
    // 載っていた**。語（「,」「、」空白・括弧で区切った欠片）の中で、前後が
    // 語の端か行政区分の字（都道府県市区町村郡）のときだけ「名前として含む」とする:
    //
    //     「宮城県」の中の「宮城」   ○   「東京都 渋谷区」の中の「東京」 ○
    //     「福岡八宮」の中の「福岡」 ✗   「東京都」の中の「京都」       ✗

    private static let adminSuffix: Set<Character> = ["都", "道", "府", "県", "市", "区", "町", "村", "郡"]

    /// 撮影地を語に割る（「,」「、」空白・括弧で区切る。小文字にそろえる）
    private static func tokens(_ value: String?) -> [[Character]] {
        let separators = CharacterSet(charactersIn: ",、，()（）").union(.whitespacesAndNewlines)
        return (value ?? "").lowercased()
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
            .map(Array.init)
    }

    /// 語 `t` の中に名前 `l` が**名前として**入っているか
    private static func nameInToken(_ t: [Character], _ l: [Character]) -> Bool {
        guard !l.isEmpty, l.count <= t.count else { return false }
        for k in 0...(t.count - l.count) where Array(t[k..<(k + l.count)]) == l {
            let end = k + l.count
            let before = k == 0 || adminSuffix.contains(t[k - 1])
            let after = end == t.count || adminSuffix.contains(t[end]) || adminSuffix.contains(l[l.count - 1])
            if before && after { return true }
        }
        return false
    }

    /// 字 `text` の中に `name` が**名前として**入っているか（前後が端か行政区分の字）。
    /// 「東京都」の中の「京都」は ✗、「京都府」の中の「京都」は ○。
    /// `boundaries` は行政区分の字に加えて切れ目とみなす字（海外の「州」「地方」など）。
    /// 揃え方（小文字・空白など）は呼び手がそろえてから渡す
    static func nameIn(_ text: String, _ name: String, boundaries: [String] = []) -> Bool {
        guard !boundaries.isEmpty else { return nameInToken(Array(text), Array(name)) }
        let t = Array(text), l = Array(name)
        guard !l.isEmpty, l.count <= t.count else { return false }
        let marks = boundaries.map(Array.init)
        func endsWithMark(_ upTo: Int) -> Bool {
            marks.contains { m in m.count <= upTo && Array(t[(upTo - m.count)..<upTo]) == m }
        }
        func startsWithMark(_ from: Int) -> Bool {
            marks.contains { m in from + m.count <= t.count && Array(t[from..<(from + m.count)]) == m }
        }
        for k in 0...(t.count - l.count) where Array(t[k..<(k + l.count)]) == l {
            let end = k + l.count
            let before = k == 0 || adminSuffix.contains(t[k - 1]) || endsWithMark(k)
            let after = end == t.count || adminSuffix.contains(t[end]) || adminSuffix.contains(l[l.count - 1])
                || startsWithMark(end)
            if before && after { return true }
        }
        return false
    }

    /// **地図・撮影地の検索の当て方**（2026-10-07 判断）。字の部分一致（打ちかけの「Toky」・
    /// 「東京駅」の中の「東京」も当たる。Web の地図 `mapFilter.ts` の `matchesMapQuery` と同じ）だが、
    /// **行政区分の字で終わる長い名前の途中**に当たったものだけは数えない:
    ///
    ///     「東京都中央区」の中の「京都」 ✗（前に「東」があり、語は「区」で終わる）
    ///     「東京駅」の中の「東京」       ○   「富士山」の中の「富士」 ○
    ///     「東京都渋谷区」の中の「渋谷」 ○（直前が行政区分の字「都」）
    ///
    /// 語の区切りは `tokens` と同じ（「,」「、」空白・括弧）。揃え方は呼び手がそろえてから渡す
    static func looselyContains(_ text: String, _ needle: String) -> Bool {
        let t = Array(text), l = Array(needle)
        guard !l.isEmpty, l.count <= t.count else { return false }
        let separators = CharacterSet(charactersIn: ",、，()（）").union(.whitespacesAndNewlines)
        func isSeparator(_ c: Character) -> Bool {
            c.unicodeScalars.allSatisfy { separators.contains($0) }
        }
        for k in 0...(t.count - l.count) where Array(t[k..<(k + l.count)]) == l {
            // 語の頭から当たっていれば数える
            if k == 0 || isSeparator(t[k - 1]) { return true }
            // 直前が行政区分の字なら、そこで名前が切れているので数える（`nameIn` の「前」と同じ規則）。
            // 「東京都渋谷区」の「渋谷」・「香川県観音寺市」の「観音寺」（2026-10-09 まで外れていた）
            if adminSuffix.contains(t[k - 1]) { return true }
            // 語の途中なら、その語が行政区分の字で終わるときだけ外す
            var end = k + l.count
            while end < t.count, !isSeparator(t[end]) { end += 1 }
            if !adminSuffix.contains(t[end - 1]) { return true }
        }
        return false
    }

    /// `inner` の語の並びの中に、`outer` の語が**同じ順で続けて**名前として入っているか
    private static func contains(_ inner: String?, _ outer: String?) -> Bool {
        guard normalized(inner).count >= 2, normalized(outer).count >= 2 else { return false }
        let it = tokens(inner)
        let ot = tokens(outer)
        guard !ot.isEmpty, ot.count <= it.count else { return false }
        for i in 0...(it.count - ot.count) {
            if ot.indices.allSatisfy({ j in it[i + j] == ot[j] || nameInToken(it[i + j], ot[j]) }) {
                return true
            }
        }
        return false
    }
}
