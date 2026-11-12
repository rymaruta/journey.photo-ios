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

    /// 送信を取り消す: 自分の1通を一覧から外す（押したらすぐ消える・2026-11-12）。外した1通を返す（失敗したら `restore` で戻す）。
    /// **自分の通だけ**（相手の通・無い id は nil で何もしない）
    mutating func unsend(_ id: String) -> DMMessage? {
        guard let i = messages.firstIndex(where: { $0.id == id }), messages[i].mine else { return nil }
        return messages.remove(at: i)
    }

    /// 取り消しに失敗した1通を元の位置へ戻す（時刻の順に並ぶ・`merge` と同じ）
    mutating func restore(_ message: DMMessage) {
        merge([message])
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
    /// 会話を始める入口（2026-11-10）: 受信箱の見出しの鉛筆と、そこから開く一覧の題
    static var newMessageTitle: String { L("新しいメッセージ", "New message") }
    /// プロフィールの「メッセージ」ボタン
    static var messageButtonTitle: String { L("メッセージ", "Message") }
    /// 受信箱が空のとき・一覧の下の一言。**始め方を言う**（ストーリーへの返信だけではなくなった）
    static var startHint: String {
        L("フォローしている人には、プロフィールか右上のボタンからメッセージを送れます。",
          "You can message people you follow from their profile or the button at the top right.")
    }
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
        case "requestPhoto":
            // 承認前は写真を送れない（2026-11-11 判断・URL と同じ考え・`dm.ts` の `PHOTO_REFUSED`）
            return t("承認されるまでは写真を送れません。文字で送ってください",
                     "You can't send photos until they accept. Send text instead.")
        case "photoNotFound":
            return t("この写真は送れません", "This photo can't be sent.")
        default:
            return APIError.server(status: status, message: fallback).description(language: language)
        }
    }

    /// 断られたあと、入力欄に本文を戻すか（吹き出しにして「もう一度送る」を出すのは、押し直せば通りうる回だけ）
    static func returnsToField(code: String?) -> Bool {
        switch code {
        case "requestUrl", "requestLimit", "blockedByMe", "empty", "selfFull", "unavailable", "dailyLimit", "notFound",
             "requestPhoto", "photoNotFound":
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

    /// 1通目を送る前の案内（2026-11-10 判断・まだ会話が無い相手を、プロフィールか「新しいメッセージ」から開いたとき）。
    /// **送る前に**決まりが分かるように、通数とリンクの決まりを1つの文で言う。言い方はサーバーの断り
    /// （「承認されるまでは3通までです」「承認されるまではリンクを送れません」・`dm.ts`）と、
    /// リクエスト一覧の説明（「相手が送れるのは文字3通までで、リンクは送れません」）にそろえる
    static func firstMessageNote(name: String, language: String = Locale.preferredAppLanguage) -> String {
        let limit = DMRules.requestLimit
        return L("\(name) さんが承認するまで、送れるのは文字\(limit)通までで、リンクは送れません",
                 "Until \(name) accepts, you can send up to \(limit) text messages, without links.",
                 language: language)
    }

    /// 受信箱・リクエストの行の時刻（今日は「12分前」、昨日は「昨日」、6日前までは「3日前」、それより前は「10/12」）。
    /// 2026-11-12 判断: 決まりはお知らせの行と共通（`NotificationText.ago` が元）。未来の時刻は「たった今」
    static func listTime(_ iso: String, now: Date = Date(), calendar: Calendar = .current) -> String? {
        NotificationText.ago(iso, now: now, calendar: calendar)
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

    /// 吹き出しを前の1通とつなげるか（2026-11-11 案C・付け根の側の上の角も 6 に詰める）。
    /// 同じ人の続きで5分以内（前の1通に時刻が出ない＝`showsTime` が false）・同じ日・この通に札（ストーリー・写真）が無いとき
    static func joinsPrevious(current: DMMessage, previous: DMMessage?, calendar: Calendar = .current) -> Bool {
        guard let previous, previous.bubbleText != nil else { return false }
        guard !current.isStoryReply, !current.hasPhoto else { return false }
        if startsDay(current: current, previous: previous, calendar: calendar) { return false }
        return !showsTime(current: previous, next: current)
    }

    /// 札の読み上げ（「mika さんのストーリーへの返信、タップで見られます」）
    static func storyCardSpoken(owner: String, mine: Bool, state: DMStoryCardState) -> String {
        let head = mine ? L("\(owner) さんのストーリーへの返信", "Reply to \(owner)'s story")
                        : L("あなたのストーリーへの返信", "Reply to your story")
        switch state {
        case .live: return head + "、" + L("タップでストーリーを見る", "tap to view the story")
        case .ended: return head + "、" + L("ストーリーは終了しました", "this story has ended")
        case .none, .unknown: return head
        }
    }

    /// 送った写真の読み上げ（「あなたが送った写真、弘前城の桜、撮影地 青森県弘前市」）
    static func photoSpoken(title: String?, location: String?, mine: Bool) -> String {
        let head = mine ? L("あなたが送った写真", "Photo you sent") : L("届いた写真", "Photo you received")
        let parts = [head, title, location.map { L("撮影地 \($0)", "taken in \($0)") }].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.joined(separator: "、")
    }

    /// 1通の下に出す時刻（「18:30」）。同じ人の続きで5分以内なら最後の1通だけ（`showsTime`）。出さないときは nil
    static func timeLabel(current: DMMessage, next: DMMessage?) -> String? {
        guard showsTime(current: current, next: next), let date = NotificationGroups.parse(current.t) else { return nil }
        return clock(date)
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
    /// 受信箱の行の抜粋。最後の1通が自分のものなら頭に「あなた: 」（**欄があるときだけ**・画面案）。
    /// 写真だけの通の抜粋（サーバーが古いアプリ向けに日本語で埋める「写真を送りました」）は端末の言葉に直す
    static func excerpt(_ thread: DMThread, language: String = Locale.preferredAppLanguage) -> String {
        let body = thread.excerpt == serverPhotoText ? photoOnlyText(mine: thread.lastMine == true, language: language)
                                                     : thread.excerpt
        // 抜粋が空（全部の通を取り消した・2026-11-12）なら「あなた: 」だけを出さない
        guard thread.lastMine == true, !body.isEmpty else { return body }
        return L("あなた: ", "You: ", language: language) + body
    }

    /// サーバーが写真だけの通の本文・抜粋に入れる文（`dm.ts` の `DM_PHOTO_TEXT`・古いアプリ向け・日本語だけ）。
    /// **受信箱の行には `photoOnly` の欄が無い**ので、抜粋がこの文と同じときだけ写真だけの通と読む（2026-11-11 判断）
    static let serverPhotoText = "写真を送りました"

    /// 写真だけの通を端末の言葉で言う（受信箱の抜粋・中身の分からない写真の札）
    static func photoOnlyText(mine: Bool, language: String = Locale.preferredAppLanguage) -> String {
        mine ? L("写真を送りました", "Sent a photo", language: language)
             : L("写真が届きました", "Sent you a photo", language: language)
    }
}

/// 送った写真の札の見せ方（2026-11-11・札 #541・`DMStoryCardState` と同じ考え）
enum DMPhotoCardState: Equatable {
    /// 写真の通ではない
    case none
    /// 写真の通だが札の中身が分からない（古い通・新しい方から20枚を越えた通・送った直後の応答）。「表示できません」と言い切らない
    case unknown
    /// 見られる（押すと写真の詳細）
    case live(DMPhotoQuote)
    /// 見られない（消した・非公開・範囲の外・持ち主にブロックされた・**見る人が持ち主をブロックした**）
    case gone

    static func of(_ message: DMMessage, blocked: Set<String>) -> DMPhotoCardState {
        guard message.hasPhoto else { return .none }
        guard let quote = message.photo else { return .unknown }
        // 見る人がブロックした人の写真は出さない（サーバーは見る人の側のブロックを見ない・ほかの画面と同じく端末でふるう）
        if let owner = quote.ownerId, blocked.contains(owner) { return .gone }
        if quote.isLive { return .live(quote) }
        return quote.state == "gone" || quote.state == "live" ? .gone : .unknown
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

// MARK: - 会話を始める（2026-11-10 owner「普通にDMできる機能がいい」）

/// 会話を始める相手（プロフィールの「メッセージ」・受信箱の「新しいメッセージ」から）。
/// **まだ会話が無いとき**、会話の画面が見出しの名前と顔を出すのに使う（`GET /dm/{id}` は 404 で名前を返さない）
struct DMPeerSeed: Hashable, Identifiable {
    /// 相手の uid
    let id: String
    let name: String
    let username: String?

    init(id: String, name: String?, username: String? = nil) {
        self.id = id
        self.name = DMText.name(name, deleted: false)
        self.username = username
    }
}

/// 2026-11-10 判断（owner「普通にDMできる機能がいい」・札 #505 の第1段では置かなかった入口）:
/// 会話はストーリーへの返信のほかに、**プロフィールの「メッセージ」と受信箱の「新しいメッセージ」**から始められる。
///
/// サーバーの門（`api-user/src/dm.ts` の `sendDm`・本番 main 2b9a4384）: 新しい会話を始められるのは
/// **自分が相手をフォローしているときだけ**（していなければ 404 `notFound`）。だから入口はフォロー中の人にだけ出す——
/// 押して断られる体験を作らない。届いた側の置き場所（受信箱かリクエスト）は相手との関係で決まるが、
/// 送る側の決まり（返信か承認までは文字3通・URL 不可）は全員に同じ
enum DMStart {

    /// プロフィールの「メッセージ」を押したときの動き（2026-11-10・確かめ役の指摘）。
    /// 会話 → 見出し → 相手のプロフィール →「メッセージ」で**同じ会話がもう1枚積まれ**、2枚とも10秒ごとに
    /// 読み直していた。会話から開いたプロフィール（`fromConversation`）では積まずに戻る
    enum MessageAction: Equatable {
        /// この人との会話を積む
        case openConversation
        /// 来た会話へ戻る（`dismiss()`）
        case backToConversation
    }

    static func messageAction(fromConversation: Bool) -> MessageAction {
        fromConversation ? .backToConversation : .openConversation
    }

    /// 「メッセージ」の読み上げのヒント（押すと何が起きるかを言う）
    static func messageHint(fromConversation: Bool) -> String {
        fromConversation ? L("この人とのメッセージに戻ります", "Goes back to your messages with this person")
                         : L("この人とのメッセージを開きます", "Opens your messages with this person")
    }

    /// プロフィールに「メッセージ」を出すか。**ログインしていて、自分以外で、ブロックの関係になく、
    /// フォローしていると分かっている**ときだけ（分からない＝読めなかった回は出さない）
    static func showsMessageButton(viewerId: String?, userId: String, isFollowing: Bool,
                                   blocked: Set<String>) -> Bool {
        guard let viewerId, !viewerId.isEmpty, !userId.isEmpty,
              viewerId.lowercased() != userId.lowercased(), !blocked.contains(userId) else { return false }
        return isFollowing
    }

    /// 相手との会話 id（サーバーの `convIdOf`）。自分自身・空・パスに入れられない id は nil
    static func conversationId(me: String?, peer: String) -> String? {
        guard let me, !me.isEmpty, !peer.isEmpty, me.lowercased() != peer.lowercased() else { return nil }
        let id = DMRules.conversationId(me, peer)
        return PathID.isSafe(id) ? id : nil
    }

    /// 会話を読んだ断りを「まだ会話が無い＝これから始まる」と読むか。**会話を始める入口から開いたときだけ**、
    /// サーバーが `notFound` と答えた 404 に限る——受信箱から開いた会話の 404（消した・ブロックの関係）と、
    /// **道そのものが無い 404**（`code` が無い・口が古い）は今までどおり「表示できません」
    static func opensEmpty(_ refused: DMService.Refused, starting: Bool) -> Bool {
        starting && refused.isConversationMissing
    }

    /// 新しいメッセージの一覧に並べる人（フォロー中の一覧から、自分・退会した人・ブロックした人を落とす）。
    /// 並びはサーバーのまま（新しくフォローした順）
    static func candidates(_ users: [FollowUser], me: String?, blocked: Set<String>) -> [FollowUser] {
        var seen = Set<String>()
        return users.filter { user in
            user.deleted != true && !blocked.contains(user.id)
                && user.id.lowercased() != me?.lowercased() && seen.insert(user.id).inserted
        }
    }

    /// 検索語で絞る。**親しい友達・ブロック一覧と同じ絞り方**（`ListIdentity.filter`: 表示名と @ユーザー名の部分一致・
    /// 大文字小文字と全角半角を区別しない・頭の @ は外す・空の語は全員）——写しを作らない
    static func filter(_ users: [FollowUser], query: String) -> [FollowUser] {
        ListIdentity.filter(users, query: query)
    }

    /// 人の検索（`/users/search`）の答えから、**フォローしている人だけ**を一覧の形にする。
    /// フォロー中の一覧はサーバーが50人で切るので（`follow.ts` の `FOLLOWING_PAGE`）、その外の人を語で探すのに使う。
    /// 一覧に既にいる人（`excluding`）・自分・ブロックした人は落とす
    static func searchHits(_ profiles: [UserProfile], following: Set<String>, me: String?,
                           blocked: Set<String>, excluding: Set<String>) -> [FollowUser] {
        var seen = excluding
        return profiles.compactMap { profile in
            let id = profile.userId
            guard following.contains(id), !blocked.contains(id), id.lowercased() != me?.lowercased(),
                  seen.insert(id).inserted else { return nil }
            return FollowUser(id: id, name: profile.displayName, deleted: false, username: profile.username)
        }
    }

    /// 選んだ人から、会話の画面に渡す相手
    static func seed(_ user: FollowUser) -> DMPeerSeed {
        DMPeerSeed(id: user.id, name: user.name, username: user.username)
    }
}

// MARK: - 会話の中のリンク（2026-11-11・札 #541）

/// 吹き出しの中の URL を見つける（押せるリンクにする）。**画面を持たない**ので Linux の試験で見張る。
///
/// - 見つけるのは `http(s)://`・`www.`・よくある末尾のドメイン（`example.com/x`）。スキームの無いものは `https://` を付ける
/// - **開けるのは http と https だけ**（`javascript:`・`file:`・`tel:` などは見つけても押せるようにしない）
/// - 末尾の句読点・閉じ括弧（`。`・`、`・`)`・`」` など）はリンクに含めない
/// - メールアドレスの一部（`@` の後ろのドメイン）は拾わない
/// - 承認前の会話には URL が届かない（サーバーが断る・`requestUrl`）。ここは承認後の通のためだけ
///
/// 開く先は **Safari**（2026-11-11 判断: 知らない人が送ったリンクでも、アドレスバーと鍵の印が見える所で開く。
/// アプリの中の小さな窓で開くと、偽のログイン画面と見分けにくい）。SwiftUI の `Text` のリンクの既定の動き
enum DMLinks {

    struct Link: Equatable {
        let range: Range<String.Index>
        let url: URL
    }

    /// 見つけたリンク（本文の中の位置と開く URL）。重なりは先に見つけた方
    static func find(in text: String) -> [Link] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        var out: [Link] = []
        var taken: [NSRange] = []
        for regex in regexes {
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                var r = m.range
                // 末尾の句読点・閉じ括弧を外す
                while r.length > 0, let last = ns.substring(with: NSRange(location: r.location + r.length - 1, length: 1)).first,
                      trailing.contains(last) {
                    r.length -= 1
                }
                guard r.length > 0, !taken.contains(where: { NSIntersectionRange($0, r).length > 0 }) else { continue }
                // メールの `@` の後ろ・語の途中から始まるものは拾わない
                if r.location > 0 {
                    let before = ns.substring(with: NSRange(location: r.location - 1, length: 1))
                    if before == "@" || before == "." || before == "/" { continue }
                }
                let raw = ns.substring(with: r)
                let lower = raw.lowercased()
                let full = lower.hasPrefix("http://") || lower.hasPrefix("https://") ? raw : "https://" + raw
                guard let url = URL(string: full) else { continue }
                // 🔴 **名前・合言葉の付いた URL はリンクにしない**（`https://apple.com@evil.com/login` は evil.com へ行く。
                // 見えている字と行き先が違う・2026-11-11 確かめ役の指摘）。その範囲は取ったことにして、中の
                // `apple.com` だけを別のリンクにもしない
                if url.user != nil || url.password != nil {
                    taken.append(r)
                    continue
                }
                guard isOpenable(url), let range = Range(r, in: text) else { continue }
                taken.append(r)
                out.append(Link(range: range, url: url))
            }
        }
        return out.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// 開けるリンクか（http・https・ホストあり・名前や合言葉が付いていない）
    static func isOpenable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host?.isEmpty == false
            && url.user == nil && url.password == nil
    }

    /// URL に使える ASCII の字だけ（日本語が続いてもリンクに含めない・閉じ括弧は外す）
    private static let body = #"[A-Za-z0-9\-._~:/?#\[\]@!$&'*+,;=%]"#
    /// 見つける式（1回だけ作る・2026-11-11 確かめ役の指摘）
    private static let regexes: [NSRegularExpression] = patterns.compactMap {
        try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
    }
    private static let patterns: [String] = [
        #"https?://"# + body + "+",
        #"www\."# + body + "+",
        #"(?<![A-Za-z0-9_@.-])[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:"# + tlds + #")(?![A-Za-z0-9_-])(?:/"# + body + "*)?",
    ]
    /// サーバーの `TLDS` と同じ並び（`DMRules.containsURL` と同じ末尾を押せるようにする）
    private static let tlds = "com|net|org|jp|io|co|me|ly|gl|link|app|dev|xyz|info|biz|cc|tv|to|us|uk|ru|cn|site|online|shop|top|club"
        + "|gg|be|ee|asia|ink|page|live|store|tech"
    private static let trailing: Set<Character> = [".", ",", "!", "?", ":", ";", ")", "]", "}", "'", "\"",
                                                   "。", "、", "！", "？", "）", "」", "』", "】", "…"]
}

// MARK: - 写真を送る（2026-11-11・札 #541）

/// 写真を DM で送る口（写真の詳細の「送る」のシートから呼ぶ）。会話 id は2人から組む（`DMStart.conversationId`）。
/// **承認前の相手には送れない**（サーバーが 400 `requestPhoto` を返す・`DMText.refusal` の言葉）
enum DMPhotoSend {

    enum Failure: Error, Equatable {
        /// ログインしていない・自分あて・相手の id の形が違う
        case invalid
    }

    /// 写真を1通送る。`text` は添える文（空でよい）。鍵は1回の送信につき1つ（押し直しは呼ぶ側が同じ鍵で）
    @discardableResult
    static func send(service: DMService, me: String?, peerId: String, photoId: String, text: String = "",
                     clientId: String = DMRules.newClientId()) async throws -> DMSendResult {
        guard let id = DMStart.conversationId(me: me, peer: peerId), !photoId.isEmpty else { throw Failure.invalid }
        return try await service.send(id, text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                      clientId: clientId, photoId: photoId)
    }
}

/// 送信の取り消し（2026-11-12・owner「DM 送信取り消し必要だわ」「取り消しました。みたいなメッセージはいらない」）。
///
/// **確かめのダイアログは出さない**（直感的で簡単に・押す回数は長押し→1回）。代わりに、取り消した文は入力欄に戻す
/// ——直して送り直せるし、間違えて押しても文を失わない。写真・ストーリーへの返信の通は、入力欄に戻すと
/// 別の通（ただの文字）になってしまうので、取り消すだけ（2026-11-12 判断・秘書室）。
enum DMUnsend {
    /// 入力欄に戻す文。文字だけの自分の通だけ（写真・ストーリーへの返信は nil）。
    /// **送れない会話（`canSend` が偽: 承認前の3通を使い切った・相手が退会）では戻さない**——欄は止まっていて、
    /// 戻しても送り直せない（2026-11-12・確かめ役の指摘）
    static func returnedText(_ message: DMMessage, canSend: Bool = true) -> String? {
        guard canSend, message.mine, !message.hasPhoto, !message.isStoryReply, let text = message.bubbleText else { return nil }
        return text
    }

    /// 取り消しの答えを受けて、画面をどうするか（2026-11-12・確かめ役の指摘: 404 を一律「消えたまま」にしていた）
    enum Outcome: Equatable {
        /// サーバーで消えた（成功・`messageNotFound`＝もう消えている・自分の通ではない）。吹き出しは消えたまま
        case gone
        /// サーバーが断った（会話が見られない `notFound`＝ブロックの関係など・上限・形の誤り）。**消えていないのが確か**:
        /// 吹き出しを戻し、欄も戻す
        case refused
        /// 答えが分からない（時間切れ・圏外・5xx）。サーバーでは消えたかもしれない: 吹き出しは戻すが、**戻した文は欄に残す**
        /// （消えていたら次の読み直しで吹き出しが消え、文は欄に残る＝失わない）
        case unknown
    }

    static func outcome(of error: Error?) -> Outcome {
        guard let error else { return .gone }
        if let refused = error as? DMService.Refused {
            return refused.status == 404 && refused.code == "messageNotFound" ? .gone : .refused
        }
        return .unknown
    }

    /// 戻したあとの入力欄。**打ちかけの文は消さない**（空ならそのまま、あれば改行して後ろに足す）。上限で切る
    static func draft(current: String, returning text: String, limit: Int = DMRules.textMax) -> String {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let joined = trimmed.isEmpty ? text : current + "\n" + text
        return String(joined.prefix(limit))
    }

    /// 失敗して戻すときの入力欄。**戻したままの文なら元に戻す**（そのあと打ち直していれば触らない）
    static func draftAfterFailure(current: String, returned: String, before: String) -> String {
        current == returned ? before : current
    }
}
