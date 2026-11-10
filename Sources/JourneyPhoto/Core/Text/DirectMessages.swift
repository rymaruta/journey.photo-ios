import Foundation

/// メッセージ（DM・第1段・札 #505）の決まり。**画面を持たない**ので Linux の試験で見張る。
///
/// 規則はサーバー（`api-user/src/dm.ts`・本番 journey.photo-web main 2b9a4384）が正。ここはその写しではなく、
/// **画面が先に知っておくこと**（会話 id の組み方・承認前の上限・URL の見分け・断りの言葉）だけを置く。
enum DMRules {

    /// 承認（返信か承認）されるまでに、始めた人が送れる文字の通数（`DM_REQUEST_MAX`・全員に同じ・owner 判断 2026-11-09）
    static let requestLimit = 3
    /// 1通の上限（`DM_TEXT_MAX`・UTF-16 で数える・`PostLimits` と同じ数え方）
    static let textMax = 500
    /// 会話を開いている間に読み直す間隔（`?since=` で変化なしは軽い空応答）。
    /// 2026-11-10 判断: 第1段は押し出しの通知（プッシュ）＋開いている間だけの読み直し。10秒より短くしない
    static let pollInterval: Duration = .seconds(10)

    /// 会話 id（サーバーの `convIdOf`）: **小文字にして、小さい uid_大きい uid**。2人から一意に決まる
    static func conversationId(_ a: String, _ b: String) -> String {
        let x = a.lowercased(), y = b.lowercased()
        return x < y ? "\(x)_\(y)" : "\(y)_\(x)"
    }

    /// 会話 id から相手の uid を出す。自分が入っていない・形が違う id は nil
    static func peer(of conversationId: String, me: String) -> String? {
        let parts = conversationId.split(separator: "_", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        let mine = me.lowercased()
        if parts[0] == mine { return parts[1] }
        if parts[1] == mine { return parts[0] }
        return nil
    }

    /// 再送で二重に入れないための鍵（サーバーは `^[A-Za-z0-9_-]{8,64}$` を受ける）。**1通につき1回だけ作る**
    static func newClientId() -> String {
        UUID().uuidString.lowercased()
    }

    /// サーバーが受ける鍵の形か
    static func isValidClientId(_ id: String) -> Bool {
        (8...64).contains(id.utf8.count) && PathID.isSafe(id)
    }

    // MARK: - URL（承認前だけ）

    /// URL に見える文字を含むか。**サーバーの `containsUrl` と同じ見分け**（2026-11-10 判断）。
    ///
    /// 使うのはストーリーの返信欄だけ: 返信は URL を含んでもストーリーには届くが、承認前の会話へは写らない
    /// （サーバーが `requestUrl` で写すのを断る）。黙って会話に残らない返信を作らないよう、承認前の相手には
    /// 送る前に止める（板の案 D）。会話の画面はサーバーの 400 `requestUrl` で知る（ここで先回りしない）
    static func containsURL(_ text: String) -> Bool {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.precomposedStringWithCompatibilityMapping.unicodeScalars   // NFKC
            .filter { !invisible.contains($0.value) })
        var t = String(scalars)
        t = t.replacingOccurrences(of: "。", with: ".").replacingOccurrences(of: "｡", with: ".")
        t = replace(t, #"\s*[\[(<{【（]\s*(?:\.|dot|ドット)\s*[\])>}】）]\s*"#, with: ".")
        t = replace(t, #"\s+dot\s+"#, with: ".")
        // 🔴 JS の `\b` は ASCII の語（`[A-Za-z0-9_]`）の境目。ICU の `\b` は仮名・漢字も語に数えるので、
        // 「ここexample.comです」を拾えない。境目は前後の読みで JS と同じにする
        let start = #"(?<![A-Za-z0-9_])"#, end = #"(?![A-Za-z0-9_])"#
        return matches(t, #"(?:https?|ftp)://|www\."#)
            || matches(t, start + #"[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:"# + tlds + ")" + end)
            || matches(t, start + #"[a-z0-9-]+(?:\s*\.\s*[a-z0-9-]+)*\s*\.\s*(?:"# + spacedTlds + ")" + end)
    }

    /// サーバーの `TLDS`・`SPACED_TLDS` と同じ並び
    private static let tlds = "com|net|org|jp|io|co|me|ly|gl|link|app|dev|xyz|info|biz|cc|tv|to|us|uk|ru|cn|site|online|shop|top|club"
        + "|gg|be|ee|asia|ink|page|live|store|tech"
    private static let spacedTlds = "com|net|org|jp|io|co|ly|gl|link|xyz|info|biz|cc|tv|gg|asia|shop|site|online"
    /// ゼロ幅・方向制御・ソフトハイフン（サーバーの `INVISIBLE`）
    private static let invisible: Set<UInt32> = [
        0x200B, 0x200C, 0x200D, 0x200E, 0x200F,
        0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
        0x2060, 0x2066, 0x2067, 0x2068, 0x2069,
        0xFEFF, 0x00AD,
    ]

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func replace(_ text: String, _ pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}

extension DMInbox {
    /// 未読のある会話の数。**リクエストとブロックした相手は数えない**（サーバーの `unreadConvCount` と同じ数え方。
    /// ホームの吹き出しの点・受信箱の点はこれで決める・板「ヘッダーの真鍮の点は受信箱の未読だけ」）
    func unreadConversations(hiding blocked: Set<String> = []) -> Int {
        items.filter { $0.showsUnread && !blocked.contains($0.peerId) }.count
    }

    /// 受け取ったリクエストの数（ブロックした相手は数えない）
    func requestTotal(hiding blocked: Set<String> = []) -> Int {
        items.filter { $0.isRequest && !blocked.contains($0.peerId) }.count
    }

    /// 1つの会話を読んだことにした姿（開いた直後に点を消す。サーバーの既読を待たない）
    func markingRead(_ id: String) -> DMInbox {
        let next = items.map { row in
            row.id == id && row.unread > 0
                ? DMThread(id: row.id, peerId: row.peerId, name: row.name, username: row.username, deleted: row.deleted,
                           t: row.t, excerpt: row.excerpt, unread: 0, state: row.state)
                : row
        }
        return DMInbox(rebuilding: next)
    }

    /// 1つの会話を外した姿（削除・承認しないで断った・ブロックした）
    func removing(_ id: String) -> DMInbox {
        DMInbox(rebuilding: items.filter { $0.id != id })
    }

    /// リクエストを承認した姿（受信箱へ移す。未読は残す）
    func accepting(_ id: String) -> DMInbox {
        let next = items.map { row in
            row.id == id && row.isRequest
                ? DMThread(id: row.id, peerId: row.peerId, name: row.name, username: row.username, deleted: row.deleted,
                           t: row.t, excerpt: row.excerpt, unread: row.unread, state: .inbox)
                : row
        }
        return DMInbox(rebuilding: next)
    }

    /// 行から数を数え直して作る（手元で変えたあと、数と行を割らない）
    init(rebuilding items: [DMThread]) {
        self.init(items: items,
                  unread: items.filter(\.showsUnread).count,
                  requestCount: items.filter(\.isRequest).count)
    }
}

// MARK: - 送る1通（手元の控え）

/// 送っている・送れなかった1通。**鍵（`clientId`）は作ったときの1つを使い続ける**——
/// 応答が落ちて押し直しても、サーバーは同じ鍵の1通を二度入れない（`sendDm` の `stored` の枝）
struct DMOutgoing: Identifiable, Equatable {
    enum Phase: Equatable { case sending, failed(String) }

    let clientId: String
    let text: String
    let createdAt: Date
    var phase: Phase

    var id: String { clientId }
}

/// 会話の手元の控え（並び・重ね合わせ・送る1通）。**画面を持たない**
struct DMThreadLog: Equatable {
    /// サーバーから読めたメッセージ（古い順・id で重ならない）
    private(set) var messages: [DMMessage] = []
    /// まだサーバーの答えが無い・送れなかった1通（古い順）
    private(set) var outgoing: [DMOutgoing] = []

    init(messages: [DMMessage] = [], outgoing: [DMOutgoing] = []) {
        self.messages = []
        self.outgoing = outgoing
        merge(messages)
    }

    /// 読めた分を重ねる。**同じ id は1つにする**（`since` の読み直し・送った応答と読み直しが重なっても1通）。
    /// 並びは時刻の順（同じ時刻は来た順のまま）。重ねた1通が控えにあれば控えから外す
    mutating func merge(_ incoming: [DMMessage]) {
        guard !incoming.isEmpty else { return }
        var byId: [String: Int] = [:]
        for (i, m) in messages.enumerated() { byId[m.id] = i }
        for m in incoming {
            if let i = byId[m.id] {
                messages[i] = m
            } else {
                byId[m.id] = messages.count
                messages.append(m)
            }
        }
        messages = messages.enumerated().sorted { a, b in
            a.element.t == b.element.t ? a.offset < b.offset : a.element.t < b.element.t
        }.map(\.element)
        let known = Set(messages.map(\.id))
        outgoing.removeAll { known.contains($0.clientId) }
    }

    /// 全部を読み直した（`since` なし）。サーバーに無い分は落とす（自分の側を消した・通報で消えた）
    mutating func replace(with all: [DMMessage]) {
        messages = []
        merge(all)
    }

    /// 送り始める。**同じ鍵の1通がもう控えにあれば足さない**（押し直しで二重にしない）
    @discardableResult
    mutating func begin(text: String, clientId: String, at date: Date = Date()) -> Bool {
        guard !outgoing.contains(where: { $0.clientId == clientId }),
              !messages.contains(where: { $0.id == clientId }) else { return false }
        outgoing.append(DMOutgoing(clientId: clientId, text: text, createdAt: date, phase: .sending))
        return true
    }

    /// もう一度送る（同じ鍵のまま）。送れなかった1通だけ。送る本文を返す
    mutating func retry(_ clientId: String) -> String? {
        guard let i = outgoing.firstIndex(where: { $0.clientId == clientId }),
              case .failed = outgoing[i].phase else { return nil }
        outgoing[i].phase = .sending
        return outgoing[i].text
    }

    /// 送れた: サーバーの1通に置き換える
    mutating func succeed(_ clientId: String, with message: DMMessage) {
        outgoing.removeAll { $0.clientId == clientId }
        merge([message])
    }

    /// 送れなかった: 控えに残して「もう一度送る」を出す
    mutating func fail(_ clientId: String, reason: String) {
        guard let i = outgoing.firstIndex(where: { $0.clientId == clientId }) else { return }
        outgoing[i].phase = .failed(reason)
    }

    /// 断られて控えから外す（URL・上限・ブロック: 吹き出しにせず、入力欄に戻す）。外した本文を返す
    mutating func withdraw(_ clientId: String) -> String? {
        guard let i = outgoing.firstIndex(where: { $0.clientId == clientId }) else { return nil }
        return outgoing.remove(at: i).text
    }

    /// 送っている最中の1通があるか（同じ時に2通を走らせない）
    var isSending: Bool { outgoing.contains { $0.phase == .sending } }

    /// 開こうとしたストーリーが一覧に無かった（見られなくなった・終わった）: その札を「終了」に倒す
    mutating func markStoryEnded(_ storyId: String) {
        messages = messages.map { m in
            guard m.storyId == storyId || m.story?.id == storyId else { return m }
            return DMMessage(id: m.id, from: m.from, mine: m.mine, text: m.text, t: m.t, via: m.via,
                             storyId: m.storyId ?? storyId, story: DMStoryQuote(id: storyId, state: "ended"))
        }
    }

    /// 相手が話したことがあるか（承認前の残り数を出すかの手がかり。サーバーが `requestRemaining` で正を返す）
    var peerHasSpoken: Bool { messages.contains { !$0.mine } }
}

// MARK: - 画面の言葉

enum DMText {

    static var title: String { L("メッセージ", "Messages") }
    static var requestsTitle: String { L("リクエスト", "Requests") }
    /// 退会した相手の名前（サーバーの `DELETED_USER_NAME` と同じ語）
    static var deletedName: String { L("退会したユーザー", "Deleted user") }
    /// 読めなかったときの説明（画面案「失敗」）
    static var loadFailedMessage: String {
        L("通信を確かめて、もう一度お試しください。", "Check your connection and try again.")
    }

    /// 相手の名前（退会していれば「退会したユーザー」・空なら「ユーザー」）
    static func name(_ raw: String?, deleted: Bool) -> String {
        if deleted { return deletedName }
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? L("ユーザー", "User") : trimmed
    }

    /// 断りの言葉。**`code` で選ぶ**（サーバーの文は日本語だけ・相手との関係で変えない1種類）。
    /// 知らない `code` はサーバーの文（英語の画面では状態の数の文・`APIError.description`）
    static func refusal(status: Int, code: String?, fallback: String, language: String = Locale.preferredAppLanguage) -> String {
        func t(_ ja: String, _ en: String) -> String { L(ja, en, language: language) }
        switch code {
        case "requestUrl":
            return t("URLは送れません。リンクを消して、文字だけで送ってください",
                     "Links can't be sent yet. Remove the link and send text only.")
        case "requestLimit":
            return t("承認されるまで、送れるのは文字\(DMRules.requestLimit)通までです",
                     "You can send up to \(DMRules.requestLimit) messages until they accept.")
        case "busy":
            return t("混み合っています。もう一度お試しください", "It's busy right now. Please try again.")
        case "dailyLimit":
            return t("今日はこれ以上送れません。明日またお試しください", "You can't send more today. Please try again tomorrow.")
        case "selfFull":
            return t("会話が200件に達しています。不要な会話を削除してください",
                     "You have 200 conversations. Delete ones you no longer need.")
        case "unavailable":
            return t("いま送れません", "Can't send right now.")
        case "blockedByMe":
            return t("ブロック中の相手には送れません", "You can't message someone you've blocked.")
        case "notFound":
            return t("この会話は表示できません", "This conversation isn't available.")
        case "empty":
            return t("メッセージを入力してください", "Type a message.")
        default:
            return APIError.server(status: status, message: fallback).description(language: language)
        }
    }

    /// 断られたあと、入力欄に本文を戻すか（吹き出しにして「もう一度送る」を出すのは、押し直せば通りうる回だけ）
    static func returnsToField(code: String?) -> Bool {
        switch code {
        case "requestUrl", "requestLimit", "blockedByMe", "empty", "selfFull", "unavailable", "dailyLimit", "notFound":
            return true
        default:
            return false
        }
    }

    /// 承認前の残り数の案内（板「リクエストの 3 通上限」: 2通目のあとは「あと1通」を同じ位置に）。
    /// 残りが無い（`remaining` が nil）なら出さない
    static func requestNote(name: String, remaining: Int?, language: String = Locale.preferredAppLanguage) -> String? {
        guard let remaining else { return nil }
        func t(_ ja: String, _ en: String) -> String { L(ja, en, language: language) }
        let limit = DMRules.requestLimit
        switch remaining {
        case ...0:
            return t("\(name) さんが承認するまで、送れるのは文字\(limit)通までです（\(limit)/\(limit)）",
                     "Until \(name) accepts, you can send up to \(limit) messages (\(limit)/\(limit)).")
        case 1:
            return t("\(name) さんが承認するまで、あと1通送れます",
                     "You can send 1 more message until \(name) accepts.")
        default:
            return t("\(name) さんが承認するまで、送れるのは文字\(limit)通までです",
                     "Until \(name) accepts, you can send up to \(limit) messages.")
        }
    }

    /// 受信箱・リクエストの行の時刻（今日は「12分前」、昨日は「昨日」、6日前までは「3日前」、それより前は「10/12」）
    static func listTime(_ iso: String, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let date = NotificationGroups.parse(iso), date <= now else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 6 { return NotificationText.ago(iso, now: now, calendar: calendar) }
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)/\(parts.day ?? 0)"
    }

    /// 会話の日付の区切り（「今日」「昨日」「11月3日」）
    static func dayLabel(_ date: Date, now: Date = Date(), calendar: Calendar = .current,
                         language: String = Locale.preferredAppLanguage) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return L("今日", "Today", language: language) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return L("昨日", "Yesterday", language: language)
        }
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        let sameYear = calendar.component(.year, from: now) == p.year
        let month = p.month ?? 0, day = p.day ?? 0
        if language == "en" { return sameYear ? "\(month)/\(day)" : "\(month)/\(day)/\(p.year ?? 0)" }
        return sameYear ? "\(month)月\(day)日" : "\(p.year ?? 0)年\(month)月\(day)日"
    }

    /// 吹き出しの下の時刻（「18:02」・24時間・2桁）
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let p = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", p.hour ?? 0, p.minute ?? 0)
    }

    /// 時刻を出すか（同じ人の続きで5分以内なら、最後の1通だけに出す・板の会話の並び）
    static func showsTime(current: DMMessage, next: DMMessage?) -> Bool {
        guard let next else { return true }
        if next.mine != current.mine { return true }
        guard let a = NotificationGroups.parse(current.t), let b = NotificationGroups.parse(next.t) else { return true }
        return b.timeIntervalSince(a) >= 5 * 60
    }

    /// 日付の区切りを前に置くか（前の1通と暦の日が違う）
    static func startsDay(current: DMMessage, previous: DMMessage?, calendar: Calendar = .current) -> Bool {
        guard let date = NotificationGroups.parse(current.t) else { return false }
        guard let previous, let before = NotificationGroups.parse(previous.t) else { return true }
        return !calendar.isDate(date, inSameDayAs: before)
    }
}

// MARK: - ストーリーの返信欄（画面案「ストーリーからの返信」A〜E）

/// ストーリーへの返信が会話に写るときの門（2026-11-10 札 #505）。サーバーは文字の返信を、その人との会話の1通として
/// 写す（`mirrorStoryReplyToDm`）。承認前の会話には**文字3通まで・URL 不可**が掛かり、外れた返信は会話に写らない
/// ——黙って会話に残らない返信を作らないよう、返信欄が先に知って止める（板の案 B・D・E）
struct DMReplyGate: Equatable {
    /// ストーリーの持ち主（会話の相手）
    let peerId: String
    /// 承認前に送れる残り。nil＝承認済み・相手からのリクエストに返す（上限なし）
    let remaining: Int?

    /// 3通を使い切った（欄を止める・反応の絵文字は今までどおり送れる）
    var limitReached: Bool { remaining.map { $0 <= 0 } ?? false }

    /// この本文を承認前の会話に写せないか（URL）
    func refusesURL(in text: String) -> Bool {
        remaining != nil && DMRules.containsURL(text)
    }

    /// 1通送ったあとの門（残りを1つ減らす）
    func afterSending() -> DMReplyGate {
        DMReplyGate(peerId: peerId, remaining: remaining.map { max(0, $0 - 1) })
    }

    /// 会話を読んだ答えから作る。`conversation` が nil（404）＝まだ会話が無い＝これから始まる（3通まで）
    static func from(_ conversation: DMConversation?, peerId: String) -> DMReplyGate {
        guard let conversation else { return DMReplyGate(peerId: peerId, remaining: DMRules.requestLimit) }
        // 相手から届いたリクエストに返す回は、返した時点で承認（上限なし）
        if conversation.state == .request { return DMReplyGate(peerId: peerId, remaining: nil) }
        return DMReplyGate(peerId: peerId, remaining: conversation.requestRemaining)
    }

    /// 返信欄の下の2行目（B: 上限を先に伝える・E: 使い切った）
    func note(name: String, language: String = Locale.preferredAppLanguage) -> String? {
        guard let remaining else { return nil }
        if remaining <= 0 {
            return L("\(name) さんが承認するまで、これ以上送れません（\(DMRules.requestLimit)/\(DMRules.requestLimit)）",
                     "You can't send more until \(name) accepts (\(DMRules.requestLimit)/\(DMRules.requestLimit)).",
                     language: language)
        }
        return DMText.requestNote(name: name, remaining: remaining, language: language)
    }

    /// URL を止めたときの文（板の案 D）
    static var urlRefusal: String {
        L("URLは送れません。文字だけで送ってください", "Links can't be sent yet. Send text only.")
    }
}

// MARK: - アイコンの数字（2026-11-10 札 #505）

/// アプリのアイコンの数字。**サーバーと同じ数え方**（`notify.ts` の `sendToDevices`: お知らせの未読＋メッセージの未読会話数。
/// リクエストとブロックした相手は数えない）。お知らせを読んだ・会話を読んだときに、アプリの側でもこの数に合わせる
enum AppBadge {
    static func count(bellUnread: Int, messagesUnread: Int) -> Int {
        max(0, bellUnread) + max(0, messagesUnread)
    }

    /// アプリが数字を置いてよい値。**お知らせの未読と受信箱の両方を、今の人で読めた後だけ**（片方だけなら nil＝触らない）。
    /// 起動直後に受信箱が先に読めた回に「0＋メッセージの未読」でお知らせの分を消していた（2026-11-10 再確認の指摘）
    static func syncValue(me: String?, bellOwner: String?, bellUnread: Int,
                          messagesOwner: String?, messagesLoaded: Bool, messagesUnread: Int) -> Int? {
        guard let me, bellOwner == me, messagesOwner == me, messagesLoaded else { return nil }
        return count(bellUnread: bellUnread, messagesUnread: messagesUnread)
    }

    /// 通知センターの通知のうち、その会話のメッセージの通知の id（`{type: "dm", convId}`）
    static func deliveredIds(_ items: [(id: String, userInfo: [AnyHashable: Any])], conversationId: String) -> [String] {
        items.filter { NotificationRouter.dmConversationId($0.userInfo) == conversationId }.map { $0.id }
    }
}

// MARK: - 2026-11-10 に足した欄（journey.photo-web 8b03528db・本番 main 2b9a4384）

/// ストーリーへの返信の引用札の見せ方（画面案「会話」の先頭の札）。**欄が無いときは今の作り（枠だけ）**
enum DMStoryCardState: Equatable {
    /// 返信した1通ではない
    case none
    /// ストーリーへの返信だが、札の中身が分からない（古い通・新しい方から20件を越えた通・口が古い）
    case unknown
    /// 見られる（止め絵・動画は絵なし）。押すと見る
    case live(storyId: String, image: URL?, isVideo: Bool)
    /// 終わった（期限・棚・見られなくなった）
    case ended

    /// 開いている間に次に期限が来る見られる札の時刻（その時刻に描き直して「終了しました」に倒す）
    static func nextExpiry(_ messages: [DMMessage], after now: Date) -> Date? {
        messages.compactMap { m -> Date? in
            guard let story = m.story, story.state == "live",
                  let at = story.expiresAt.flatMap(NotificationGroups.parse), at > now else { return nil }
            return at
        }.min()
    }

    /// 見られる札のストーリー（押して開く）
    var liveStoryId: String? {
        if case .live(let id, _, _) = self { return id }
        return nil
    }

    /// `since` の読み直しでは古い通の札は届き直さないので、**期限を過ぎたら手元で「終了」に倒す**
    static func of(_ message: DMMessage, now: Date = Date()) -> DMStoryCardState {
        guard message.isStoryReply else { return .none }
        guard let story = message.story else { return .unknown }
        guard story.state == "live" else { return story.state == "ended" ? .ended : .unknown }
        if let expires = story.expiresAt.flatMap(NotificationGroups.parse), expires <= now { return .ended }
        let isVideo = story.mediaType == "video"
        return .live(storyId: story.id, image: isVideo ? nil : story.src.flatMap(URL.init(string:)), isVideo: isVideo)
    }
}

extension DMText {
    /// 受信箱の行の抜粋。最後の1通が自分のものなら頭に「あなた: 」（**欄があるときだけ**・画面案）
    static func excerpt(_ thread: DMThread, language: String = Locale.preferredAppLanguage) -> String {
        thread.lastMine == true ? L("あなた: ", "You: ", language: language) + thread.excerpt : thread.excerpt
    }
}

/// ストーリーへの返信の応答の `dm` 欄（`POST /stories/{id}/replies`）。
///
///     写った: {dm: {conversationId}}   写らなかった: {dm: null, dmSkipped: "requestUrl" …}   欄が無い（口が古い）: 何も無い
struct StoryReplyOutcome: Decodable, Equatable {
    /// 写った会話。nil は「写らなかった」か「欄が無い」（`knowsMirror` で分ける）
    let conversationId: String?
    /// 写らなかった訳（`sendDm` の `code`・`reaction`・`error`）
    let skipped: String?
    /// 応答に `dm` の欄があったか（無ければ今までの作り: 会話 id を2人から組む）
    let knowsMirror: Bool

    static let unknown = StoryReplyOutcome(conversationId: nil, skipped: nil, knowsMirror: false)

    init(conversationId: String?, skipped: String?, knowsMirror: Bool) {
        self.conversationId = conversationId
        self.skipped = skipped
        self.knowsMirror = knowsMirror
    }

    private enum CodingKeys: String, CodingKey { case dm, dmSkipped }
    private struct Ref: Decodable { let conversationId: String? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        knowsMirror = c.contains(.dm)
        conversationId = (try? c.decodeIfPresent(Ref.self, forKey: .dm))?.conversationId
        skipped = try? c.decodeIfPresent(String.self, forKey: .dmSkipped)
    }

    /// 「送りました ›メッセージを見る」で開く会話。**欄があれば欄だけを信じる**（写らなかった返信で
    /// 会話へ誘わない）。欄が無ければ2人から組む（今までの作り）
    func conversationToOpen(me: String?, owner: String?) -> String? {
        if knowsMirror { return conversationId.flatMap { PathID.isSafe($0) ? $0 : nil } }
        guard let me, let owner, me != owner else { return nil }
        return DMRules.conversationId(me, owner)
    }
}

/// 自分のストーリーの返信の行から開く会話（`StoryRepliesSheet`）。**受信箱に在る会話だけ**
enum StoryReplyConversation {
    static func id(me: String, replier: String, hasText: Bool, inbox: DMInbox) -> String? {
        guard hasText, !replier.isEmpty, replier != me else { return nil }
        let id = DMRules.conversationId(me, replier)
        return inbox.items.contains { $0.id == id } ? id : nil
    }
}
