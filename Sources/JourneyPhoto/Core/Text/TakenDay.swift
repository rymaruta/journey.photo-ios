import Foundation

/// 撮影日の出し方。
///
/// 🔴 **生の値を画面に出さない。** 写真詳細は `date` をそのまま描いて
/// いたので、実機の絵に **`2026-09-19T17:46:27`** と出ていた（run 51）。
/// サーバーは `YYYY-MM-DD` で持つ約束だが、**古い行や別の経路から来た行は
/// 時刻まで入っている**——出す側で受け止める。
///
/// **時刻は出さない。** 撮影日として持っているのは日付までで、
/// 時刻は「アップロードした時刻」が混ざっている可能性がある
/// （`date` が空のときにサーバーが埋める経路は無いが、過去の行は分からない）。
/// 分からない精度を出さない。
enum TakenDay {

    /// 「2026年9月19日」。**読めない値は nil**（生のまま出すくらいなら出さない）
    static func label(_ raw: String?, locale: String = L("ja", "en")) -> String? {
        guard let head = ymd(raw) else { return nil }
        let (y, m, d) = head
        return locale == "ja" ? "\(y)年\(m)月\(d)日" : "\(monthName(m)) \(d), \(y)"
    }

    /// `YYYY-MM-DD` の頭だけを取り出して数にする。
    /// **月日の妥当さまで見る**——`2026-13-40` のような行を「13月40日」と
    /// 書かない（読めないものは出さない、に倒す）
    static func ymd(_ raw: String?) -> (Int, Int, Int)? {
        guard let raw else { return nil }
        let head = String(raw.prefix(10))
        let parts = head.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              y >= 1826, y <= 2200, m >= 1, m <= 12, d >= 1, d <= 31 else { return nil }
        return (y, m, d)
    }

    private static func monthName(_ month: Int) -> String {
        let names = ["January", "February", "March", "April", "May", "June",
                     "July", "August", "September", "October", "November", "December"]
        return names[max(0, min(11, month - 1))]
    }
}
