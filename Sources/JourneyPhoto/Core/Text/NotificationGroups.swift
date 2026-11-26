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
        // **`now` から数える。** `isDateInToday` / `isDateInYesterday` は
        // 渡した `now` を見ずに**システムの時計**を見るので、混ぜると
        // 引数が嘘になる（テストは日付が変わるまで通り、翌日に落ちた）。
        // 端末の時計より少し先の時刻（サーバーの時計が進んでいる）も「今日」。暦の日数で
        // 数えると、日をまたいだ回に −1 日で「以前」の一番下へ行った
        if calendar.isDate(date, inSameDayAs: now) || date > now { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return .yesterday }
        // **7日で切る**（週の始まりに依らない。月曜に開いた人だけ
        // 「今週」が空、という揺れを作らない）。
        // 🔴 **暦の日数で数える**（`NotificationText.ago` と同じ）。経過時間で数えると、
        // 6日23時間前のお知らせが「今週」の下に「7日前」で出ていた
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                              to: calendar.startOfDay(for: now)).day, days < 7, days >= 0 {
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
    ///
    /// 2026-11-26 判断（アプリを軽く）: **読んだ答えを控える**（`ParsedDates`）。`ISO8601DateFormatter` の読みは重く
    /// （Mac run 1804 の積みの見本で、ホームの止まりの最中に ICU の `DateFormatSymbols::loadAllSymbols` まで降りていた）、
    /// 同じ文字列を何度も読んでいた——DM の1通は描くたびに時刻を出すか・前とつなげるか・日の区切りで 4〜8 回、
    /// ホームの新しい投稿・今週のお題・コメントの見出しも写真ごとに body のたびに読む。文字列が同じなら答えも同じ
    static func parse(_ text: String) -> Date? {
        ParsedDates.shared.value(for: text) {
            withFraction.date(from: text) ?? withoutFraction.date(from: text)
        }
    }

    // 2026-11-25 判断（Swift 6）: ISO8601DateFormatter は Sendable と書かれていないが、Apple の文書で複数のスレッドから使ってよい。作った後は設定を変えないので `nonisolated(unsafe)` にする
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // 2026-11-25 判断（Swift 6）: ISO8601DateFormatter は Sendable と書かれていないが、Apple の文書で複数のスレッドから使ってよい。作った後は設定を変えないので `nonisolated(unsafe)` にする
    nonisolated(unsafe) private static let withoutFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// `NotificationGroups.parse` の答えの控え（2026-11-26 判断）。読めなかった文字列も「読めない」と控える。
/// 増えすぎたら一度に空にする（時刻の文字列は投稿・メッセージごとに違うので、長く使うと際限なく増える）
final class ParsedDates: @unchecked Sendable {
    static let shared = ParsedDates()

    /// 控える数の上限。DM の会話・ホームの写真・お知らせを合わせても数千に届かない
    static let limit = 4096

    private var dates: [String: Date?] = [:]
    private let lock = NSLock()
    /// 読んだ回数（テスト用・控えに無かった回）
    private(set) var misses = 0

    func value(for text: String, _ make: () -> Date?) -> Date? {
        lock.lock()
        if let hit = dates[text] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        let date = make()
        lock.lock()
        if dates.count >= Self.limit { dates.removeAll(keepingCapacity: true) }
        dates[text] = .some(date)
        misses += 1
        lock.unlock()
        return date
    }

    /// 控えの数（テスト用）
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return dates.count
    }

    func removeAll() {
        lock.lock()
        dates.removeAll()
        lock.unlock()
    }
}
