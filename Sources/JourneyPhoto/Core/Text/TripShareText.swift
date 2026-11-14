import Foundation

/// 旅行プランを仲間と使う（2026-11-12・資料「SNS をもっと SNS に」2b・札 #553）の決まり（画面に依らない部分）。
///
/// - 日程は仲間の誰もが直せる。**ぶつかったら黙って上書きしない**: サーバーは版（`rev`）が古い書き込みを 409 で断り、
///   画面は読み直したプランの上に**自分が変えた分だけ**を重ね直して送り直す（`rebase`）
/// - 受信箱の会話の行・プッシュから開く先は、DM の会話 ID と混ざらない `trip_<planId>` で運ぶ（`conversationId`）
enum TripShareText {

    /// 日程と会話の切り替え（板「表示の切替」と同じ形）
    enum Tab: Hashable { case days, chat }

    /// 項目の同じさ（サーバーの `itemKey` と同じ・足した人の鍵）
    static func itemKey(_ item: TripItem) -> String {
        switch item {
        case .spot(let id, _): return "s:\(id)"
        case .location(let slug, _): return "l:\(slug)"
        }
    }

    // MARK: - 会話の1通の通報とブロック（2026-11-14・札 #597・審査ガイドライン 1.2）

    /// 1通の長押しに出す操作
    enum MessageAction: Equatable { case report, block }

    /// 1通の長押しに出す操作。**ほかの仲間が書いた文の通だけ**（自分の通・「日程に足しました」の札には出さない——
    /// サーバーも自分の通・札の通報は 400 で断る）。退会した人はブロックの相手にならない（DM の「…」と同じ・通報は出す）。
    /// ブロック中の人の通は画面から外れているので、ここに来ない
    static func messageActions(_ message: TripChatMessage, authorDeleted: Bool) -> [MessageAction] {
        guard !message.mine, message.event == nil, let text = message.text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return authorDeleted ? [.report] : [.report, .block]
    }

    // MARK: - 受信箱・プッシュ

    static let conversationPrefix = "trip_"

    /// 受信箱・プッシュで運ぶ会話の印（DM の会話 ID は `小さいuid_大きいuid` で、`trip_` では始まらない）
    static func conversationId(planId: String) -> String { conversationPrefix + planId }

    static func planId(fromConversation id: String) -> String? {
        guard id.hasPrefix(conversationPrefix) else { return nil }
        let rest = String(id.dropFirst(conversationPrefix.count))
        return rest.isEmpty || !PathID.isSafe(rest) ? nil : rest
    }

    /// プッシュの中身（サーバーの `tripShare.ts` の `notify`: `{type: "tripchat"|"tripshare", planId}`）から会話の印
    static func conversationId(push userInfo: [AnyHashable: Any]) -> String? {
        let type = userInfo["type"] as? String
        guard type == "tripchat" || type == "tripshare", let planId = userInfo["planId"] as? String,
              PathID.isSafe(planId) else { return nil }
        return conversationId(planId: planId)
    }

    // MARK: - 文

    static func memberCount(_ n: Int) -> String { L("\(n)人", n == 1 ? "1 person" : "\(n) people") }

    static func shareWith(_ name: String) -> String { L("\(name) と共有する", "Share with \(name)") }
    static func sharedWith(_ name: String) -> String { L("\(name) と共有しています", "Shared with \(name)") }
    static var shareNote: String {
        L("共有すると、2人で日程を変えられて、プランの中で話せます", "Once shared, you can both edit the plan and chat in it")
    }
    static var invite: String { L("仲間を誘う", "Invite") }
    static func inviteTitle(_ title: String) -> String { L("\(title)に誘う", "Invite to \(title)") }
    static var inviteNote: String {
        L("リンクを受け取った人は、アプリが無くても Web で見て参加できます", "People with the link can view and join on the web, even without the app")
    }
    static var leave: String { L("このプランから抜ける", "Leave this trip") }
    static var leaveConfirm: String {
        L("抜けると、このプランと会話が見えなくなります。もう一度入るには招待リンクが要ります。",
          "You'll no longer see this trip or its chat. You'll need an invite link to rejoin.")
    }

    /// 項目の下の「[名前] が足しました」（自分が足した項目・足した人が分からない項目は出さない）
    static func addedBy(_ plan: TripPlan, _ item: TripItem, members: [TripMember], me: String?) -> String? {
        guard plan.share != nil, let uid = plan.addedBy[itemKey(item)], uid != me else { return nil }
        let name = members.first { $0.id == uid }.map { $0.deleted == true ? L("退会したユーザー", "Deleted user") : $0.name }
        guard let name else { return nil }
        return L("\(name) が足しました", "Added by \(name)")
    }

    /// 会話の札の「日程に足しました」。何日目かは `eventDay` で別の文字にし、余白で分けて並べる
    /// （中黒で区切らない・2026-11-12 の決まり）
    static var eventAdded: String { L("日程に足しました", "Added to the plan") }

    /// 会話の札の「1日目」
    static func eventDay(_ day: Int) -> String { L("\(day + 1)日目", "Day \(day + 1)") }

    /// 会話の1通の上限（サーバーの `TRIP_CHAT_TEXT_MAX`・UTF-16 で数える・`PostLimits` と同じ数え方）。
    /// 越えたぶんは打てない（2026-11-12 確かめ役の指摘10。サーバーは越えたぶんを黙って切る）
    static let chatTextMax = 500

    /// 入力欄の直しを上限に収める（DM の入力欄と同じ `PostLimits.limited`）
    static func limitedDraft(old: String, new: String) -> String {
        PostLimits.limited(old: old, new: new, limit: chatTextMax)
    }

    /// 受信箱の行の抜粋（「あお: …」・自分は「あなた: …」・場所を足した通は決まった文）
    static func inboxExcerpt(_ item: TripInboxItem) -> String {
        guard let last = item.last else { return L("まだメッセージはありません", "No messages yet") }
        let who = last.mine ? L("あなた", "You") : last.fromName
        let body = last.event == true ? L("日程に場所を足しました", "Added a place to the plan") : last.excerpt
        return "\(who): \(body)"
    }

    // MARK: - ぶつかったときの重ね直し

    /// 項目に「何回目に現れたか」を付けた鍵（同じ場所を2回置いても見分ける）
    private static func keyed(_ days: [TripDay]) -> [[String]] {
        var seen: [String: Int] = [:]
        return days.map { day in
            day.items.map { item in
                let k = itemKey(item)
                let n = seen[k, default: 0]
                seen[k] = n + 1
                return "\(k)#\(n)"
            }
        }
    }

    private static func position(of key: String, in keys: [[String]]) -> (day: Int, index: Int)? {
        for (d, row) in keys.enumerated() { if let i = row.firstIndex(of: key) { return (d, i) } }
        return nil
    }

    /// 読み直したプラン（`server`）の上に、開いたとき（`base`）から自分が変えた分（`mine`）だけを重ねる。
    ///
    /// - 自分が**足した**場所は、自分が置いた日・位置に入れる（その日が無ければ日を足す）
    /// - 自分が**外した**場所は外す（仲間がもう外していれば何もしない）
    /// - 自分が**動かした**場所は、自分が置いた日・位置へ動かす（仲間が外していれば戻さない）
    /// - ひとことは自分が変えた項目だけ写す
    /// - ほかの仲間の変更（足した・外した・動かした・ひとこと）は残す
    static func rebase(base: [TripDay], mine: [TripDay], server: [TripDay]) -> [TripDay] {
        let baseKeys = keyed(base), mineKeys = keyed(mine)
        let baseSet = Set(baseKeys.flatMap { $0 }), mineSet = Set(mineKeys.flatMap { $0 })
        var mineItems: [String: TripItem] = [:]
        for (d, row) in mineKeys.enumerated() { for (i, k) in row.enumerated() { mineItems[k] = mine[d].items[i] } }
        var baseItems: [String: TripItem] = [:]
        for (d, row) in baseKeys.enumerated() { for (i, k) in row.enumerated() { baseItems[k] = base[d].items[i] } }

        // 今のサーバーの姿を鍵つきで持つ
        var result: [[(key: String, item: TripItem)]] = zip(keyed(server), server).map { keys, day in
            Array(zip(keys, day.items)).map { (key: $0.0, item: $0.1) }
        }
        var dates = server.map(\.date)
        func ensureDay(_ d: Int) {
            while result.count <= d { result.append([]); dates.append(nil) }
        }
        func remove(_ key: String) -> TripItem? {
            for d in result.indices {
                if let i = result[d].firstIndex(where: { $0.key == key }) { return result[d].remove(at: i).item }
            }
            return nil
        }
        // 外した
        for k in baseSet.subtracting(mineSet) { _ = remove(k) }
        // 動かした・ひとことを変えた（開いたときと自分の今で、日か位置かひとことが違う）
        for (d, row) in mineKeys.enumerated() {
            for (i, k) in row.enumerated() where baseSet.contains(k) {
                guard let was = position(of: k, in: baseKeys) else { continue }
                let changedNote = baseItems[k] != mineItems[k]
                guard was.day != d || was.index != i || changedNote else { continue }
                guard let current = remove(k) else { continue }   // 仲間が外した: 戻さない
                ensureDay(d)
                let item = changedNote ? mineItems[k]! : current
                result[d].insert((key: k, item: item), at: min(i, result[d].count))
            }
        }
        // 足した（同じ場所が既にサーバーに在れば、二重に置かない）
        for (d, row) in mineKeys.enumerated() {
            for (i, k) in row.enumerated() where !baseSet.contains(k) {
                if result.contains(where: { $0.contains { $0.key == k } }) { continue }
                ensureDay(d)
                // 自分が日の最後に足したなら、仲間が足した分より後ろ（最後）へ
                let at = i >= row.count - 1 ? result[d].count : min(i, result[d].count)
                result[d].insert((key: k, item: mineItems[k]!), at: at)
            }
        }
        // 日の日付は、自分が変えた日だけ写す
        for d in mine.indices where d < result.count {
            let before = d < base.count ? base[d].date : nil
            if mine[d].date != before { dates[d] = mine[d].date }
        }
        return result.indices.map { TripDay(date: dates[$0], items: result[$0].map(\.item)) }
    }

    /// 日付（出発・帰着）は、自分が変えたときだけ自分の値・そうでなければ読み直した値
    static func rebaseDate(base: String?, mine: String?, server: String?) -> String? {
        (base ?? "") != (mine ?? "") ? mine : server
    }
}
