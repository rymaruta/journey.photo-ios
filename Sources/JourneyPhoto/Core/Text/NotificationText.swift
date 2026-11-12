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
        /// まとめた中に、その人にとって初めてのいいね・コメントが在るか（2026-11-08・`FirstReaction`）
        var firstReaction: FirstReaction.Kind? = nil

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
    static func collapse(_ rows: [AppNotification], unreadIds: Set<String> = [],
                         firstReactions: [String: FirstReaction.Kind] = [:]) -> [Entry] {
        var order: [String] = []
        var leads: [String: AppNotification] = [:]
        var people: [String: [String]] = [:]
        var unread: [String: Bool] = [:]
        var firsts: [String: FirstReaction.Kind] = [:]
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
            if let first = firstReactions[row.id] { firsts[key] = first }
        }
        return order.compactMap { key in
            guard let lead = leads[key] else { return nil }
            return Entry(lead: lead, others: max(0, (people[key]?.count ?? 1) - 1),
                         unread: unread[key] ?? false, firstReaction: firsts[key])
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
        // メダルは左にメダルの絵を出す（右の小窓は使わない）
        guard row.kind != .storyreply, row.kind != .storymention, row.kind != .badge, let src = row.photoSrc else { return nil }
        return URL(string: src)
    }

    /// 板の文言（「[user] があなたの写真にいいねしました」）。
    /// 種類の分からないものは nil——**既定の文言で嘘を出さない**。
    static func line(for entry: Entry) -> Line? {
        let row = entry.lead
        if row.kind == .badge { return badgeLine(row) }
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
        // 文言は Web の `NotificationsBell` と同じ（プッシュの `NOTIF_INSPIRED` とも同じ）
        case .inspired: rest = L(" があなたの写真を見て撮影しました", " took a photo inspired by yours")
        // 文言はプッシュの `NOTIF_STORY_MENTION` と同じ
        case .storymention: rest = L(" がストーリーであなたをメンションしました", " mentioned you in a story")
        // 文言はプッシュの `NOTIF_STORY_SHARE`・`NOTIF_COMMENT_REPLY` と同じ（札 #541）
        case .storyshare: rest = L(" があなたの写真をストーリーで紹介しました", " shared your photo in a story")
        case .commentreply: rest = L(" があなたのコメントに返信しました", " replied to your comment")
        // 光と天気の知らせは一覧の行にならない（プッシュだけ）
        case .badge, .light, .none: return nil
        }
        return Line(who: who, rest: rest)
    }

    /// 新しいメダル（板 15・2026-10-09）: 「**朝の光**のメダルを手に入れました · 銅」。
    /// 太字はメダルの名前。**知らない鍵（絵の無いバッジ）は出さない**——既定の文言で嘘を出さない
    static func badgeLine(_ row: AppNotification) -> Line? {
        guard let key = row.key, BadgeCatalog.isKnown(key) else { return nil }
        let name = BadgeCatalog.name(key)
        let tier = BadgeCatalog.hasTiers(key)
            ? "\u{2002}" + BadgeCatalog.tierWord(key, row.tier ?? 1) : ""
        return Line(who: name, rest: L("のメダルを手に入れました", " medal earned") + tier)
    }

    // MARK: - 経過時間

    /// 行の下の時刻（今日は「12分前」、昨日は「昨日」、6日前までは「3日前」、それより前は「10/9」）。
    ///
    /// 2026-11-12 判断: お知らせと DM の受信箱・リクエストの行（`DMText.listTime`）で**同じ決まり**を
    /// 使う（ここが1か所の元）。Web のお知らせ（`NotificationsBell`）も7日前から「10/9」の形。
    /// 前は上限が無く「34日前」と出ていた。7日前からは月/日で、年は付けない（受信箱の作りと同じ。
    /// 年をまたいでも「12/20」）。
    ///
    /// 今日のうちは分・時間で（`StoryPlayback.ago` と同じ書き方）、それより前は**暦の日数**で
    /// 数える——見出し（`NotificationGroups` の今日／昨日／今週＝7日未満）と食い違わないように。
    /// 端末の時計より先の時刻（サーバーの時計が少し進んでいる）は「たった今」——見出しはその行を
    /// 「今日」に入れるので、何も出さないと時刻の無い行になっていた（2026-11-12 判断）。
    /// 読めない時刻は何も出さない。
    static func ago(_ iso: String?, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let iso, let date = NotificationGroups.parse(iso) else { return nil }
        if date > now { return L("たった今", "just now") }
        if calendar.isDate(date, inSameDayAs: now) {
            return StoryPlayback.ago(from: iso, now: now)
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 1 { return L("昨日", "Yesterday") }
        if days <= 6 { return L("\(days)日前", "\(days)d ago") }
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)/\(parts.day ?? 0)"
    }

    /// 行の読み上げの文。未読・初めての印を足す。（ビューの中で変数を書き換えないよう、ここに出してある）
    static func spokenLabel(_ plain: String, unread: Bool, first: FirstReaction.Kind?) -> String {
        let base = unread ? L("未読、", "Unread, ") + plain : plain
        guard let first else { return base }
        return first.eyebrow + "。" + first.note + "。" + base
    }
}
