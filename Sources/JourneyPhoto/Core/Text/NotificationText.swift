import Foundation

/// お知らせの1行に出す文言・経過時間・まとめ方（板 15）。
///
/// **サーバーが返していないものはここで作らない。** コメントの本文・
/// ストーリー返信の本文は `api-user/src/comments.ts` / `storyReplies.ts` が
/// 通知に焼き込んでいない（`Notif` 型に項目が無い）ので、板の
/// 「：「[コメント本文]」」は出さない。
enum NotificationText {

    /// 画面の1行。いいねは同じ写真のぶんを1行にまとめるので、
    /// 先頭（いちばん新しい）1件と「ほか何人」を持つ。
    struct Entry: Identifiable, Equatable {
        /// いちばん新しい1件。時刻・相手・写真・行き先はこれを使う
        let lead: AppNotification
        /// 先頭の人を除いた、別の人の数（同じ人の重複は数えない）
        let others: Int
        /// まとめた中に未読が1件でもあるか
        let unread: Bool

        var id: String { lead.id }
    }

    /// 名前（太字）と、そのあとの文。**名前だけ太くする**ために分けて返す
    struct Line: Equatable {
        let who: String
        let rest: String
        var plain: String { who + rest }
    }

    // MARK: - 未読

    /// 未読の行の id。
    ///
    /// **サーバーの `unread` は「先頭から何件」という位置の数**
    /// （`api-user/src/notify.ts` の `visibleUnread`: 追記は先頭へ、
    /// 既読化は数を 0 にするだけ）。行ごとの既読の印は持っていないので、
    /// 先頭の `unread` 件を未読として扱う。ブロックした相手のぶんは
    /// サーバーが一覧と数の両方から先に抜いているので、位置はずれない。
    static func unreadIds(_ rows: [AppNotification], unread: Int) -> Set<String> {
        Set(rows.prefix(max(0, unread)).map(\.id))
    }

    // MARK: - まとめ

    /// **同じ写真へのいいねを1行にまとめる**（板の「[user] ほか N人 が
    /// いいねしました」）。並びは変えない——まとめた行は、その中で
    /// いちばん新しい1件の位置に出る。
    ///
    /// まとめるのは**いいねだけ**。コメント・返信は1件ずつ言葉が違い
    /// （本文をサーバーが載せるようになったときに畳むと読めなくなる）、
    /// フォローは写真を伴わない。写真の id が空のいいねもまとめない。
    static func collapse(_ rows: [AppNotification], unreadIds: Set<String> = []) -> [Entry] {
        var order: [String] = []
        var leads: [String: AppNotification] = [:]
        var people: [String: [String]] = [:]
        var unread: [String: Bool] = [:]
        for row in rows {
            let key: String
            if row.kind == .like, let photo = row.photoId, !photo.isEmpty {
                key = "like|\(photo)"
            } else {
                key = "row|\(row.id)|\(order.count)"
            }
            if leads[key] == nil {
                order.append(key)
                leads[key] = row
                people[key] = []
            }
            let person = personKey(row)
            if !(people[key]?.contains(person) ?? false) { people[key]?.append(person) }
            unread[key] = (unread[key] ?? false) || unreadIds.contains(row.id)
        }
        return order.compactMap { key in
            guard let lead = leads[key] else { return nil }
            return Entry(lead: lead, others: max(0, (people[key]?.count ?? 1) - 1),
                         unread: unread[key] ?? false)
        }
    }

    /// 同じ人かどうか。**id が無ければ名前、名前も無ければ別人として数える**
    private static func personKey(_ row: AppNotification) -> String {
        if let id = row.byId, !id.isEmpty { return "id:\(id)" }
        if let name = row.byName, !name.isEmpty { return "name:\(name)" }
        return "row:\(row.id)"
    }

    // MARK: - 文言

    /// 行に出す名前。退会した人は伏せ、名前の無い古い通知は「だれか」で補う
    static func who(_ row: AppNotification) -> String {
        (row.deleted == true) ? Labels.Common.deletedUser : (row.byName ?? L("だれか", "Someone"))
    }

    /// 左のアイコン（プロフィールを開く）の読み上げ。**名前は行と同じ `who` で補う**
    /// ——素のまま埋めると、名前の無い通知で「 のプロフィールを開く」と読まれる
    static func openProfileLabel(_ row: AppNotification) -> String {
        let name = who(row)
        return L("\(name) のプロフィールを開く", "Open \(name)'s profile")
    }

    /// 右の小窓の画像。**ストーリーへの返信は出さない**（Web の `NotificationsBell` と同じ）
    /// ——`photoSrc` は24時間で消えるストーリーの画像や動画で、小窓が壊れた画像になる
    static func thumbnailURL(_ row: AppNotification) -> URL? {
        guard row.kind != .storyreply, let src = row.photoSrc else { return nil }
        return URL(string: src)
    }

    /// 板の文言（「[user] があなたの写真にいいねしました」）。
    /// 種類の分からないものは nil——**既定の文言で嘘を出さない**。
    static func line(for entry: Entry) -> Line? {
        let row = entry.lead
        let who = self.who(row)
        let rest: String
        switch row.kind {
        case .like:
            if entry.others > 0 {
                rest = L(" ほか \(entry.others)人 がいいねしました",
                         entry.others == 1 ? " and 1 other liked your photo"
                                           : " and \(entry.others) others liked your photo")
            } else {
                rest = L(" があなたの写真にいいねしました", " liked your photo")
            }
        case .comment: rest = L(" がコメントしました", " commented on your photo")
        case .follow: rest = L(" があなたをフォローしました", " followed you")
        case .storyreply: rest = L(" がストーリーに返信しました", " replied to your story")
        case .none: return nil
        }
        return Line(who: who, rest: rest)
    }

    // MARK: - 経過時間

    /// 行の下の「2時間前」「昨日」「3日前」。
    ///
    /// 今日のうちは分・時間で（`StoryPlayback.ago` と同じ書き方）、
    /// 昨日は「昨日」、それより前は**暦の日数**で数える——見出し
    /// （`NotificationGroups` の今日／昨日／今週）と食い違わないように。
    /// 読めない・未来の時刻は何も出さない。
    static func ago(_ iso: String?, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let iso, let date = NotificationGroups.parse(iso), date <= now else { return nil }
        if calendar.isDate(date, inSameDayAs: now) {
            return StoryPlayback.ago(from: iso, now: now)
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 1 { return L("昨日", "Yesterday") }
        return L("\(days)日前", "\(days)d ago")
    }
}
