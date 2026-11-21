import Foundation

/// グループの DM（みんなで話す DM・2026-11-20・札 #582・案「グループチャットを簡単に」の推奨 C）の決まり。
/// **画面を持たない**ので Linux の試験で見張る。規則はサーバー（`api-user/src/groups.ts`）が正で、ここは
/// 画面が先に知っておくこと（人数の上限・選ぶ画面の主ボタン・会話の並べ方・言葉）だけを置く。
///
/// 2026-11-20 判断（案の推奨 C・owner「いいよ」）:
/// - 新しいメッセージで**2人以上を選ぶとグループ**、1人なら今の1対1（入口を別に作らない）
/// - 1対1の会話に人を足すと、相手と足した人でグループを作る（1対1の会話はそのまま残る）
/// - 既読の人数・入力中の印は出さない（1対1と同じ）
/// - 名前は付けなくても始まる（名前が無ければサーバーの `displayName`「けん、みお」）
enum GroupRules {
    /// 1つのグループの人数（自分と招待中の人を含む・owner 2026-11-12 に決めた）
    static let membersMax = 30
    /// 名前の長さ（サーバーの `GROUP_NAME_MAX`）
    static let nameMax = 20
    /// 開いている間に読み直す間隔。**サーバーに差分の口が無い**（毎回全部・最大200通）ので、1対1の 10 秒より長くし、
    /// 旅行プランの会話（`TripChatPane`）と同じ 15 秒にした。知らせが届いたらすぐ読み直す（2026-11-20 判断）
    static let pollInterval: Duration = .seconds(15)

    /// 空の会話の、はじめの一言の候補（**AI ではない・決まった2つの言葉**）。押すと入力欄に入るだけで、送らない
    static var starters: [String] { [L("どこ行く？", "Where to?"), L("いつ空いてる？", "When are you free?")] }

    /// 候補を押したあとの入力欄。空ならその言葉、書きかけがあれば後ろに足す（書いた文を消さない）。上限で切る
    static func starterDraft(current: String, adding phrase: String, limit: Int = DMRules.textMax) -> String {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let joined = trimmed.isEmpty ? phrase : current + (current.hasSuffix(" ") || current.hasSuffix("\n") ? "" : " ") + phrase
        return String(joined.prefix(limit))
    }
}

// MARK: - 選ぶ画面（新しいメッセージ・人を足す）

/// 人を選ぶ画面の決まり（`DMNewMessageView`）。**グループの口が無いサーバーでは今の1対1のまま**（`single`）
enum GroupPick {

    enum Mode: Equatable {
        /// 今の「新しいメッセージ」（押すとすぐその人との会話）。グループの口が無いとき
        case single
        /// 「新しいメッセージ」で何人でも選べる（1人なら1対1、2人以上ならグループ）
        case start
        /// グループに人を足す（もう居る人・招待中の人は選べない・席は残りだけ）
        case add(present: Set<String>, seatsLeft: Int)
        /// 1対1の会話に人を足す（相手は外せない・相手と選んだ人でグループを作る）
        case extend(peer: DMPeerSeed)
    }

    /// 選んだあとに何をするか
    enum Outcome: Equatable {
        case none
        /// その人との1対1の会話を開く
        case oneToOne(DMPeerSeed)
        /// この人たちでグループを作る（自分を除く）
        case create([String])
        /// この人たちを今のグループに足す
        case add([String])
    }

    /// 新しいメッセージの入口の形。**グループの一覧が読めたときだけ** 何人でも選べる形にする
    static func startMode(groupsAvailable: Bool) -> Mode { groupsAvailable ? .start : .single }

    static func isMulti(_ mode: Mode) -> Bool { mode != .single }

    /// 選べる人数（自分・1対1の相手・もう居る人を除いた席）
    static func limit(_ mode: Mode) -> Int {
        switch mode {
        case .single: return 1
        case .start: return GroupRules.membersMax - 1
        case .add(_, let seatsLeft): return max(0, seatsLeft)
        case .extend: return GroupRules.membersMax - 2
        }
    }

    /// もう1人選べるか（30人目を選んだら、それ以上は押せない）
    static func canSelectMore(count: Int, mode: Mode) -> Bool { count < limit(mode) }

    /// 選んだ人数で、話し始める人数（自分を入れる）
    static func peopleCount(selected: Int, mode: Mode) -> Int {
        switch mode {
        case .single, .start: return selected + 1
        case .extend: return selected + 2
        case .add: return selected
        }
    }

    /// 主ボタンの言葉（押すと何が起きるかを言う・「直感的で簡単に」）。押せないときは nil（ボタンを出さない）
    static func mainTitle(selected: Int, mode: Mode, language: String = Locale.preferredAppLanguage) -> String? {
        guard selected > 0 else { return nil }
        let n = peopleCount(selected: selected, mode: mode)
        switch mode {
        case .single:
            return nil
        case .start:
            // 2026-11-20 owner「◯人で話す ではなく グループで話す の方がいい」。人数は選んだ人の札で見える
            return selected == 1 ? L("メッセージを送る", "Send a message", language: language)
                                 : L("グループで話す", "Start a group chat", language: language)
        case .extend:
            return L("グループで話す", "Start a group chat", language: language)
        case .add:
            return L("\(n)人を足す", n == 1 ? "Add 1 person" : "Add \(n) people", language: language)
        }
    }

    /// 画面の題（新しいメッセージ・人を足す）
    static func title(_ mode: Mode, language: String = Locale.preferredAppLanguage) -> String {
        switch mode {
        case .single, .start: return DMText.newMessageTitle
        case .add, .extend: return L("人を足す", "Add people", language: language)
        }
    }

    /// まだ誰も選んでいないときの主ボタン（押せない）
    static func idleTitle(_ mode: Mode, language: String = Locale.preferredAppLanguage) -> String {
        switch mode {
        case .add, .extend: return L("足す人を選んでください", "Choose people to add", language: language)
        case .single, .start: return L("話す人を選んでください", "Choose who to message", language: language)
        }
    }

    static func outcome(selected: [FollowUser], mode: Mode) -> Outcome {
        guard !selected.isEmpty, selected.count <= limit(mode) else { return .none }
        switch mode {
        case .single:
            return selected.count == 1 ? .oneToOne(DMStart.seed(selected[0])) : .none
        case .start:
            return selected.count == 1 ? .oneToOne(DMStart.seed(selected[0])) : .create(selected.map(\.id))
        case .extend(let peer):
            let others = selected.map(\.id).filter { $0 != peer.id }
            return others.isEmpty ? .none : .create([peer.id] + others)
        case .add(let present, _):
            let fresh = selected.map(\.id).filter { !present.contains($0) }
            return fresh.isEmpty ? .none : .add(fresh)
        }
    }

    /// 並べない人（もう居る人・1対1の相手）
    static func excluded(_ mode: Mode) -> Set<String> {
        switch mode {
        case .add(let present, _): return present
        case .extend(let peer): return [peer.id]
        case .single, .start: return []
        }
    }

    /// 「最近話した人」（受信箱の会話の新しい順・フォロー中の人だけ・5人まで）。旅の仲間は直近で話している人のことが多い
    static func recent(threads: [DMThread], following: [FollowUser], excluding: Set<String> = [], limit: Int = 5) -> [FollowUser] {
        let byId = Dictionary(following.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        var out: [FollowUser] = []
        for thread in threads where !thread.isRequest && !thread.isDeleted {
            guard let user = byId[thread.peerId], !excluding.contains(user.id), seen.insert(user.id).inserted else { continue }
            out.append(user)
            if out.count >= limit { break }
        }
        return out
    }

    /// 選んだ札の並び（選んだ順）から1人を外す・足す。グループになる選び方では、相互フォローでない人は足さない
    static func toggled(_ selected: [FollowUser], _ user: FollowUser, mode: Mode,
                        mutual: MutualFollow = .unknownAll) -> [FollowUser] {
        if selected.contains(where: { $0.id == user.id }) { return selected.filter { $0.id != user.id } }
        guard canSelectMore(count: selected.count, mode: mode),
              blockedByMutual(user, selected: selected, mode: mode, mutual: mutual) == false else { return selected }
        return selected + [user]
    }

    // MARK: 相互フォロー（2026-11-20 owner 判断「相互フォローじゃないと話せない方がいい」）

    /// この人を選ぶとグループになるか（1人目は今の1対1の決まりのまま。2人目からグループ。足す・1対1に足すは必ずグループ）
    static func makesGroup(adding count: Int, mode: Mode) -> Bool {
        switch mode {
        case .single: return false
        case .start: return count >= 1
        case .add, .extend: return true
        }
    }

    /// 相互フォローでないために選べないか。**グループになる選び方だけ**で見る。2人目を選ぶときは、もう選んだ人も相互でなければ
    /// 選べない（相互でない1人目のまま2人目を選ぶと、その人が入れないグループになる）。分からない人（`unknown`）は選べる
    /// （サーバーが決め、入れなければ `notAdded` で知らせる）
    static func blockedByMutual(_ user: FollowUser, selected: [FollowUser], mode: Mode, mutual: MutualFollow) -> Bool {
        guard !selected.contains(where: { $0.id == user.id }), makesGroup(adding: selected.count, mode: mode) else { return false }
        return ([user] + selected).contains { mutual.status(of: $0.id) == .no }
    }

    /// 選べない人を押したときの1行
    static func mutualNotice(language: String = Locale.preferredAppLanguage) -> String {
        L("お互いにフォローしている人だけ、グループに入れられます", "Only people who follow each other can be added to a group.",
          language: language)
    }
}

/// 相互フォローかどうか（2026-11-20 owner 判断）。**アプリが今持っている情報から決める**:
/// 自分のフォロー中の全員の ID（`GET /user/following`）と、自分のフォロワーの一覧（`GET /users/{me}/followers`・名前つきで50人まで）。
/// フォロワーが50人を越えて一覧が欠けている（`total` が一覧より多い）ときは、一覧に居ない人を「分からない」にする
/// （選べない形にしない。サーバーが決め、入れなければ「お互いにフォローしていない人は入れられませんでした」）
struct MutualFollow: Equatable {
    enum Status: Equatable { case yes, no, unknown }

    /// 自分がフォローしている人（全員）。nil は読めていない
    let following: Set<String>?
    /// 自分をフォローしている人（一覧に載った分）。nil は読めていない
    let followers: Set<String>?
    /// フォロワーの一覧が全員そろっているか
    let followersComplete: Bool

    static let unknownAll = MutualFollow(following: nil, followers: nil, followersComplete: false)

    init(following: Set<String>?, followers: Set<String>?, followersComplete: Bool) {
        self.following = following
        self.followers = followers
        self.followersComplete = followersComplete
    }

    /// フォロワーの一覧の答えから作る（`total` が一覧の人数以下なら全員そろっている）
    init(following: Set<String>?, followerList: [FollowUser], followerTotal: Int) {
        self.init(following: following, followers: Set(followerList.map(\.id)),
                  followersComplete: followerTotal <= followerList.count)
    }

    func status(of id: String) -> Status {
        if let following, !following.contains(id) { return .no }
        guard let followers else { return .unknown }
        if followers.contains(id) { return following == nil ? .unknown : .yes }
        return followersComplete ? .no : .unknown
    }
}

/// グループができた・人を足した（選ぶ画面 → 呼ぶ側）。会話を開く印と、入れられなかった人の知らせ
struct GroupReady: Equatable {
    let change: GroupChange

    var groupId: String { change.detail.group.groupId }
    var info: GroupInfo { change.detail.group }
    /// 開いた会話・詳しい画面の上に1回出す知らせ（入れられなかった人・招待になった人）。無ければ nil
    /// 今回招待になった人の数（`invitedNow`）。2026-11-20 owner 判断（相互フォローの人だけ）のサーバー 3d01fa933 から、
    /// 招待が生まれるのは抜けた人・外された人を入れ直すときだけ（作るときは生まれない）。前から招待中の人は数えない
    var invitedCount: Int { change.invitedNow.count }

    var notice: String? {
        let parts = [GroupText.invitedNotice(invitedCount), GroupText.notAddedNotice(change.notAdded)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

// MARK: - 会話の並び

/// グループの会話の1行（吹き出し・写真の札・真ん中の1行）。DM の会話の決まり（`DMText`）に、送った人の名前と顔を足した
struct GroupRow: Identifiable, Equatable {
    let message: DMMessage
    /// 前に日付の区切りを置く
    let startsDay: Bool
    /// 相手の通の上に名前と顔を出す（同じ人が続けて送ったら2通目から省く・LINE・インスタと同じ）
    let showsSender: Bool
    /// 吹き出しの下の時刻（同じ人の続きで5分以内なら最後の1通だけ）
    let time: String?
    /// 前の吹き出しとつなげる（付け根の側の角を詰める）
    let joinsPrevious: Bool

    var id: String { message.id }
    var isEvent: Bool { message.groupEvent != nil }
}

enum GroupRows {
    static func build(_ messages: [DMMessage], calendar: Calendar = .current) -> [GroupRow] {
        messages.enumerated().map { index, message in
            let previous = index > 0 ? messages[index - 1] : nil
            let next = index + 1 < messages.count ? messages[index + 1] : nil
            let startsDay = DMText.startsDay(current: message, previous: previous, calendar: calendar)
            guard message.groupEvent == nil else {
                return GroupRow(message: message, startsDay: startsDay, showsSender: false, time: nil, joinsPrevious: false)
            }
            // 同じ人の続き（真ん中の1行・日付の区切りで切れる）
            let samePrevious = previous.flatMap { p in
                p.groupEvent == nil && p.from == message.from && !startsDay ? p : nil
            }
            let sameNext = next.flatMap { n in
                n.groupEvent == nil && n.from == message.from
                    && !DMText.startsDay(current: n, previous: message, calendar: calendar) ? n : nil
            }
            let time = DMText.timeLabel(current: message, next: sameNext)
            return GroupRow(message: message, startsDay: startsDay,
                            showsSender: !message.mine && samePrevious == nil,
                            time: time,
                            joinsPrevious: samePrevious.map { DMText.joinsPrevious(current: message, previous: $0, calendar: calendar) } ?? false)
        }
    }

    /// 読み直しで、メンバーが変わる真ん中の1行（足した・参加した・抜けた・外した・名前を変えた）が新しく来たか。
    /// 来たときだけ詳しい中身（人数・顔・名前）を読み直す（15 秒ごとの読み直しは会話だけ・2026-11-20 確かめ役の指摘）
    static func changesMembers(old: [DMMessage], new: [DMMessage]) -> Bool {
        let known = Set(old.map(\.id))
        return new.contains { m in
            guard let type = m.groupEvent?.type, !known.contains(m.id) else { return false }
            return ["added", "joined", "left", "removed", "renamed"].contains(type)
        }
    }

    /// 送った通（文字・写真）があるか。無ければ空の会話（はじめの一言の候補を出す）
    static func hasConversation(_ messages: [DMMessage]) -> Bool {
        messages.contains { $0.groupEvent == nil }
    }
}

// MARK: - 受信箱に混ぜる

/// 受信箱の1行（1対1・旅行プランの会話・グループ）。**どれも同じ行の形で時刻の順に並ぶ**（案の画面 4・2026-11-20 判断。
/// 前は旅行プランの会話を上にまとめていた）
enum MessagesInboxItem: Identifiable, Equatable {
    case dm(DMThread)
    case trip(TripInboxItem)
    case group(GroupThread)

    var id: String {
        switch self {
        case .dm(let t): return "dm:" + t.id
        case .trip(let t): return "trip:" + t.planId
        case .group(let g): return "group:" + g.id
        }
    }

    /// 並べる時刻（読めなければ一番古い扱い）
    var time: Date {
        let raw: String?
        switch self {
        case .dm(let t): raw = t.t
        case .trip(let t): raw = t.last?.t ?? t.updatedAt
        case .group(let g): raw = g.updatedAt
        }
        return raw.flatMap(NotificationGroups.parse) ?? .distantPast
    }

    /// 新しい順に混ぜる。同じ時刻は 1対1 → 旅行プラン → グループ の順（並びが揺れない）
    static func merged(dms: [DMThread], trips: [TripInboxItem], groups: [GroupThread]) -> [MessagesInboxItem] {
        let all = dms.map(MessagesInboxItem.dm) + trips.map(MessagesInboxItem.trip) + groups.map(MessagesInboxItem.group)
        return all.enumerated().sorted { a, b in
            a.element.time == b.element.time ? a.offset < b.offset : a.element.time > b.element.time
        }.map(\.element)
    }
}

// MARK: - 言葉

enum GroupText {

    /// 受信箱・知らせから開く印（DM の会話 id と混ざらない・旅行プランの `trip_` と同じ考え）
    static let conversationPrefix = "group_"

    static func conversationId(groupId: String) -> String { conversationPrefix + groupId }

    static func groupId(fromConversation id: String) -> String? {
        guard id.hasPrefix(conversationPrefix) else { return nil }
        let rest = String(id.dropFirst(conversationPrefix.count))
        return rest.isEmpty || !PathID.isSafe(rest) ? nil : rest
    }

    /// 知らせの中身（`groups.ts` の `pushTo`: `{type: "group", groupId}`・束は `aps.thread-id`＝グループの id）から会話の印
    static func conversationId(push userInfo: [AnyHashable: Any]) -> String? {
        guard userInfo["type"] as? String == "group", let groupId = userInfo["groupId"] as? String,
              PathID.isSafe(groupId) else { return nil }
        return conversationId(groupId: groupId)
    }

    /// 知らせの束（`aps.thread-id`）。サーバーはグループの id を入れる。同じグループの知らせは1つの束に重なる
    static func threadId(push userInfo: [AnyHashable: Any]) -> String? {
        (userInfo["aps"] as? [AnyHashable: Any])?["thread-id"] as? String
    }

    /// 通知を押して開いてよい印か（今の人の DM の会話か、グループ）。人が替わった後に前の人の DM の通知を開かない
    static func opens(_ id: String, me: String) -> Bool {
        groupId(fromConversation: id) != nil || DMRules.peer(of: id, me: me) != nil
    }

    /// 30人に届いた（それ以上は選べない）
    static var fullNotice: String {
        L("グループは\(GroupRules.membersMax)人までです", "Groups can have up to \(GroupRules.membersMax) people.")
    }

    static func memberCount(_ n: Int, language: String = Locale.preferredAppLanguage) -> String {
        L("\(n)人", n == 1 ? "1 person" : "\(n) people", language: language)
    }

    static func groupSize(_ n: Int, language: String = Locale.preferredAppLanguage) -> String {
        L("\(n)人のグループ", "A group of \(n)", language: language)
    }

    /// 表に出す名前。**名前の無いグループはサーバーの `displayName`**（見る人を除いた最初の2人・区切りは「、」）
    static func title(_ info: GroupInfo) -> String {
        let shown = info.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !shown.isEmpty { return shown }
        return info.name ?? L("グループ", "Group")
    }

    static func invitedLine(by name: String, language: String = Locale.preferredAppLanguage) -> String {
        L("\(name) さんがあなたを入れようとしています", "\(name) wants to add you", language: language)
    }

    static func emptyTitle(_ info: GroupInfo, language: String = Locale.preferredAppLanguage) -> String {
        L("\(title(info))と話そう", "Say hi to \(title(info))", language: language)
    }

    /// 人の名前（引けなければ中立の「メンバー」。名前を付けていない人と取り違えない・2026-11-20 確かめ役の指摘）
    static func name(_ id: String, in names: [String: String], me: String?, language: String = Locale.preferredAppLanguage) -> String {
        if let me, id == me { return L("あなた", "You", language: language) }
        let raw = names[id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? unknownName(language: language) : raw
    }

    static func unknownName(language: String = Locale.preferredAppLanguage) -> String {
        L("メンバー", "A member", language: language)
    }

    /// 会話の真ん中の1行（作った・足した・参加した・抜けた・外した・名前を変えた）。知らせは出さない種類
    static func event(_ event: GroupEvent, actor: String, names: [String: String], me: String?,
                      language: String = Locale.preferredAppLanguage) -> String {
        func t(_ ja: String, _ en: String) -> String { L(ja, en, language: language) }
        let who = name(actor, in: names, me: me, language: language)
        let targets = event.targets.map { name($0, in: names, me: me, language: language) }
            .joined(separator: t("、", ", "))
        switch event.type {
        case "created": return t("\(who)がグループを作りました", "\(who) created the group")
        case "added": return t("\(who)が\(targets)を足しました", "\(who) added \(targets)")
        case "joined": return t("\(who)が参加しました", "\(who) joined")
        case "left": return t("\(who)が抜けました", "\(who) left")
        case "removed": return t("\(who)が\(targets)を外しました", "\(who) removed \(targets)")
        case "renamed":
            if let newName = event.name, !newName.isEmpty {
                return t("\(who)が名前を「\(newName)」にしました", "\(who) named the group \"\(newName)\"")
            }
            return t("\(who)が名前を外しました", "\(who) removed the group name")
        default: return t("グループが変わりました", "The group changed")
        }
    }

    /// 受信箱の行の抜粋（「みお: 紅葉の時期がいいな」・自分なら「あなた: 」）。真ん中の1行は短い文
    static func excerpt(_ thread: GroupThread, language: String = Locale.preferredAppLanguage) -> String {
        func t(_ ja: String, _ en: String) -> String { L(ja, en, language: language) }
        if thread.isRemoved { return t("グループから外されました", "You were removed from the group") }
        guard let last = thread.last else { return "" }
        let who = last.mine ? t("あなた", "You") : (last.fromName.isEmpty ? unknownName(language: language) : last.fromName)
        if let kind = last.event {
            switch kind {
            case "created": return t("\(who)がグループを作りました", "\(who) created the group")
            case "added": return t("\(who)が人を足しました", "\(who) added people")
            case "joined": return t("\(who)が参加しました", "\(who) joined")
            case "left": return t("\(who)が抜けました", "\(who) left")
            case "removed": return t("\(who)が人を外しました", "\(who) removed someone")
            case "renamed": return t("\(who)が名前を変えました", "\(who) renamed the group")
            default: return ""
            }
        }
        let body = last.excerpt == DMText.serverPhotoText
            ? DMText.photoOnlyText(mine: last.mine, language: language) : last.excerpt
        guard !body.isEmpty else { return "" }
        return "\(who): \(body)"
    }

    /// 入れられなかった人の知らせ（理由は言わない・サーバーも数だけ返す）。0人なら nil
    static func notAddedNotice(_ count: Int, language: String = Locale.preferredAppLanguage) -> String? {
        guard count > 0 else { return nil }
        // 2026-11-20 owner 判断（相互フォローの人だけ）: 理由はサーバーが言わないが、ふつうは相互フォローでない人
        return L("お互いにフォローしていない人は入れられませんでした",
                 "People who don't follow each other couldn't be added.", language: language)
    }

    /// 招待になった人の知らせ（相手が足した人をフォローしていない・参加するまで話は見えない）
    static func invitedNotice(_ count: Int, language: String = Locale.preferredAppLanguage) -> String? {
        guard count > 0 else { return nil }
        return L("\(count)人に招待を送りました。参加するとここで話せます", count == 1 ? "Invited 1 person. They can chat once they join."
                 : "Invited \(count) people. They can chat once they join.", language: language)
    }

    /// 断りの言葉（`code` で選ぶ・グループの口の印）。知らない印は DM の言葉（`DMText.refusal`）
    static func refusal(status: Int, code: String?, fallback: String, language: String = Locale.preferredAppLanguage) -> String {
        func t(_ ja: String, _ en: String) -> String { L(ja, en, language: language) }
        switch code {
        case "full":
            return t("グループは\(GroupRules.membersMax)人までです", "Groups can have up to \(GroupRules.membersMax) people.")
        case "joinedFull":
            return t("入れるグループは50個までです。使わないグループから抜けてください",
                     "You can be in up to 50 groups. Leave one you don't use.")
        case "dailyLimit":
            return t("今日はこれ以上できません。明日またお試しください", "You've reached today's limit. Please try again tomorrow.")
        case "notMutualFollow":
            // 2026-11-20 owner 判断: 参加するときに、招待した人と相互フォローでなければ断られる（サーバー 3d01fa933）
            return t("招待した人と相互フォローになると参加できます", "You can join once you and the inviter follow each other.")
        case "notOwner":
            return t("人を外せるのは、グループを作った人だけです", "Only the person who created the group can remove people.")
        case "notFound":
            return t("このグループは表示できません", "This group isn't available.")
        case "badRequest":
            return t("うまくいきませんでした。もう一度お試しください", "Something went wrong. Please try again.")
        default:
            return DMText.refusal(status: status, code: code, fallback: fallback, language: language)
        }
    }

    /// 送れなかった文を入力欄に戻すか（押し直しても通らない断り）。DM の決まりに、グループの印を足す
    static func returnsToField(code: String?) -> Bool {
        code == "full" || code == "notFound" || DMText.returnsToField(code: code)
    }
}

extension DMService.Refused {
    /// グループの口の断りを画面の言葉にする
    var groupMessage: String { GroupText.refusal(status: status, code: code, fallback: message) }
}

extension GroupText {
    /// 失敗を画面の1行にする（グループの口の断りはグループの言葉・それ以外はふつうの言葉）
    static func message(for error: Error, fallback: String) -> String {
        if let refused = error as? DMService.Refused { return refused.groupMessage }
        return (error as? LocalizedError)?.errorDescription ?? fallback
    }
}
