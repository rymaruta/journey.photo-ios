import Foundation

/// 写真詳細のコメントの見出し（「コメント（N）」）。
///
/// **数はサーバーが返した総数だけ。** 端末で数え直さない（1ページ分しか
/// 持っていないので、`comments.count` を出すと総数より少なく見える）。
/// 取れていない回は**数を出さない**——「コメント（0）」は「まだ無い」と
/// 読まれるので、圏外でそう出すと嘘になる。
///
/// 以前は「コメント／関連写真」の札の名前だった。板 02 で札をやめ、
/// 関連写真は「この近くで撮られた写真」に置き換えた
enum CommentsHeading {

    /// - Parameter commentCount: サーバーから取れた総数。取れていなければ nil
    static func label(commentCount: Int?) -> String {
        guard let commentCount else { return L("コメント", "Comments") }
        return L("コメント（\(commentCount)）", "Comments (\(commentCount))")
    }

    /// 見出しに出す数。サーバーの総数から、読めた一覧（`loaded` 件）のうち
    /// 画面に出さない分（ブロックした人のコメント）を引く。総数が取れていなければ nil
    static func visibleCount(total: Int?, loaded: Int, shown: Int) -> Int? {
        total.map { max(0, $0 - max(0, loaded - shown)) }
    }

    /// コメントの時刻の添え書き（v2 の板 PhotoDetail の「2時間前」「昨日」）。
    ///
    /// 1分未満は「たった今」、1時間未満は「N分前」、24時間未満は「N時間前」、48時間未満は「昨日」、
    /// 7日未満は「N日前」、それより前は「2026.09.12」。**読めない時刻・未来の時刻は出さない**（nil）
    /// ——時計のずれで「-3分前」を出さない（1分までの未来は「たった今」に丸める）
    static func age(_ iso: String?, now: Date) -> String? {
        guard let iso, let date = parse(iso) else { return nil }
        let seconds = now.timeIntervalSince(date)
        guard seconds > -60 else { return nil }
        switch seconds {
        case ..<60: return L("たった今", "Just now")
        case ..<3600: let m = Int(seconds / 60); return L("\(m)分前", "\(m)m ago")
        case ..<86_400: let h = Int(seconds / 3600); return L("\(h)時間前", "\(h)h ago")
        case ..<172_800: return L("昨日", "Yesterday")
        case ..<604_800: let d = Int(seconds / 86_400); return L("\(d)日前", "\(d)d ago")
        default:
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            guard let y = c.year, let m = c.month, let d = c.day else { return nil }
            return String(format: "%04d.%02d.%02d", y, m, d)
        }
    }

    /// 2026-10-28 判断: **読み手を毎回作らない。** コメントの行ごと・描き直しのたびに `ISO8601DateFormatter` を
    /// 2つずつ作っていた（作るのは重い）。小数秒の有無の両方を試す読み方は通知の見出しと同じなので、
    /// `static` に1つずつ持っている `NotificationGroups.parse` を使う
    private static func parse(_ iso: String) -> Date? {
        NotificationGroups.parse(iso)
    }
}
