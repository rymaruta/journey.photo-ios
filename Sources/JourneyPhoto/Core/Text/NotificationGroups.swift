import Foundation

/// お知らせの時間ごとのまとまり（モック10）。
///
/// **並べ替えない。** サーバーが新しい順で返すので、その順のまま
/// 「今日」「昨日」「今週」「それ以前」に切る。並べ替えると、届いた順と
/// 画面の順が食い違う。
enum NotificationGroups {

    enum Bucket: String, Identifiable {
        case today, yesterday, thisWeek, earlier

        var id: String { rawValue }

        var label: String {
            switch self {
            case .today: return L("今日", "Today")
            case .yesterday: return L("昨日", "Yesterday")
            case .thisWeek: return L("今週", "This week")
            case .earlier: return L("それ以前", "Earlier")
            }
        }
    }

    struct Group: Identifiable, Equatable {
        let bucket: Bucket
        let rows: [AppNotification]
        var id: String { bucket.rawValue }

        static func == (lhs: Group, rhs: Group) -> Bool {
            lhs.bucket == rhs.bucket && lhs.rows.map(\.id) == rhs.rows.map(\.id)
        }
    }

    /// 時刻の読めないお知らせは **`earlier` に置く**。
    /// 捨てると届いたことが伝わらないし、「今日」に置くと嘘になる。
    static func bucket(of row: AppNotification, now: Date = Date(),
                       calendar: Calendar = .current) -> Bucket {
        guard let text = row.t, let date = parse(text) else { return .earlier }
        if calendar.isDateInToday(date) { return .today }
        if calendar.isDateInYesterday(date) { return .yesterday }
        // **7日で切る**（週の始まりに依らない。月曜に開いた人だけ
        // 「今週」が空、という揺れを作らない）
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7, days >= 0 {
            return .thisWeek
        }
        return .earlier
    }

    /// **空のまとまりは作らない**（見出しだけの段を出さない）
    static func grouped(_ rows: [AppNotification], now: Date = Date(),
                        calendar: Calendar = .current) -> [Group] {
        var byBucket: [Bucket: [AppNotification]] = [:]
        for row in rows {
            byBucket[bucket(of: row, now: now, calendar: calendar), default: []].append(row)
        }
        return [Bucket.today, .yesterday, .thisWeek, .earlier].compactMap { bucket in
            guard let rows = byBucket[bucket], !rows.isEmpty else { return nil }
            return Group(bucket: bucket, rows: rows)
        }
    }
}

extension NotificationGroups {

    /// **小数秒の有無どちらでも読む。**
    ///
    /// `ISO8601DateFormatter` は `withFractionalSeconds` を付けると
    /// **小数秒の無い文字列を読めなくなる**（付けなければ逆）。いまの
    /// サーバーは `new Date().toISOString()` なので小数秒つきだが、
    /// 片方しか読めない作りにすると、書き方が変わった日に**全部が
    /// 「それ以前」に落ちる**——見出しだけが静かに壊れる形なので、
    /// 最初から両方を試す。
    static func parse(_ text: String) -> Date? {
        withFraction.date(from: text) ?? withoutFraction.date(from: text)
    }

    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let withoutFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
