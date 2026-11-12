import Foundation

/// メッセージ（DM・第1段・2026-11-09 札 #505）の口。`api-user/src/dm.ts`（journey.photo-web 本番 main 2b9a4384）に合わせる。
/// **文字だけ・1対1**。サーバーは本番に出ている（2026-11-10・main 2b9a4384・新しい欄も含む）。
///
///     GET    /dm                    受信箱（リクエストも同じ一覧。`state` で分ける）→ `DMInbox`
///     GET    /dm/{id}?since=        会話（変化なしは `{unchanged:true, items:[]}`）→ `DMConversation`
///     POST   /dm/{id}/messages      続きを送る `{text, id}` → `DMSendResult`。`{unsend: <id>}` なら自分の1通を取り消す（2026-11-12）
///     PUT    /dm/{id}/read          既読
///     DELETE /dm/{id}               自分の側だけ消す
///     POST   /dm/{id}/accept        リクエストを承認
///     DELETE /dm/{id}/request       リクエストを削除（断る）
///     DELETE /dm/requests           受け取ったリクエストを全部削除 → `{ok, removed}`
///     POST   /dm/{id}/report        通報 `{reason, note}`（通報時点の直近20通の写しが運営に届く）
///
/// 会話の始まりは3つ: ストーリーへの返信（サーバーが最初の1通として写す・`mirrorStoryReplyToDm`）と、
/// 2026-11-10 からのプロフィールの「メッセージ」・受信箱の「新しいメッセージ」（owner「普通にDMできる機能がいい」・
/// 11-09 の「プロフィールには置かない」を改めた）。**1通目も `POST /dm/{id}/messages` で送る**——サーバーは
/// 会話 id（`<小さい uid>_<大きい uid>`）から相手を出し、会話が無ければ作る（`sendDm`・`POST /dm` と同じ門）。
/// `POST /dm`（相手 `to` を本文で渡す形）は使わない（送り先の作り方を2つにしない）。
///
/// 断り（`{ error, code }`）は `Refused` で返す。`code` は英字の印（`requestUrl`・`requestLimit`・`busy` など）で、
/// **画面の言葉は iOS が決める**（サーバーの注記「UI の文言は iOS 側で決める」）。受け取り方は旅のトランクと同じ
/// （`APIClient.errorBodySink`・`TrunkService.refusing`）
struct DMService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// サーバーの断り。`code` で画面の言葉を選ぶ（`DMText.refusal`）
    struct Refused: LocalizedError, Equatable {
        let status: Int
        let message: String
        let code: String?
        var errorDescription: String? { DMText.refusal(status: status, code: code, fallback: message) }

        /// サーバーが「会話が無い・見られない」と答えた（`notFound`）。**道そのものが無い 404**
        /// （本番にまだ口が無い・本文に `code` が無い）とは分ける——そちらを「会話が無い」と読むと、
        /// 口の無いサーバーで返信欄が承認前の上限を言い出す（`APIError.isMissingRoute` と同じ考え）
        var isConversationMissing: Bool { status == 404 && code == "notFound" }
    }

    /// 4xx の断りを `Refused` に包む。401 はログイン切れのまま返す（`TrunkService.refusing` と同じ）
    private func refusing<T>(_ call: () async throws -> T) async throws -> T {
        let errorBody = APIErrorBody()
        do {
            return try await APIClient.$errorBodySink.withValue(errorBody) { try await call() }
        } catch let APIError.server(status, message) where (400..<500).contains(status) && status != 401 {
            throw Refused(status: status, message: message, code: APIClient.errorCode(from: errorBody.data))
        }
    }

    /// パスに入れる会話 id（`<小さい uid>_<大きい uid>`）。**英数字・`-`・`_` 以外は要求を出さない**（`PathID`）
    private func encoded(_ id: String) throws -> String {
        try PathID.segment(id)
    }

    func inbox() async throws -> DMInbox {
        // 控え（URLCache）には載らない: サーバーが `Cache-Control: private, no-store` を付ける（`dm.ts` の `okJson`）
        try await api.authorized(.get, "/dm", as: DMInbox.self)
    }

    /// 会話を読む。`since` を渡すと、その時刻より後の分だけ（変化なしは `unchanged`）
    func conversation(_ id: String, since: String? = nil) async throws -> DMConversation {
        try await refusing {
            try await api.authorized(.get, "/dm/\(encoded(id))", query: since.map { ["since": $0] } ?? [:],
                                     as: DMConversation.self)
        }
    }

    /// 続きを送る。`clientId` は**再送で二重に入れないための鍵**（同じ1通の再送は同じ鍵・`DMOutbox`）。
    ///
    /// `photoId` を渡すと写真を送る（2026-11-11・札 #541・`dm.ts` の `photoId`）。写真があれば `text` は空でよい。
    /// **承認前は送れない**（400 `requestPhoto`）・送る人に見せられない写真は 404 `photoNotFound`。
    /// `photoId` が nil なら欄ごと送らない（今までと同じ本文）
    func send(_ id: String, text: String, clientId: String, photoId: String? = nil) async throws -> DMSendResult {
        struct Body: Encodable { let text: String; let id: String; let photoId: String? }
        return try await refusing {
            try await api.authorized(.post, "/dm/\(encoded(id))/messages",
                                     body: Body(text: text, id: clientId, photoId: photoId),
                                     as: DMSendResult.self)
        }
    }

    /// 自分が送った1通を取り消す（2026-11-12・owner「DM 送信取り消し必要だわ」・期限なし）。
    /// サーバーは会話の本体から**跡を残さず**消し（「取り消しました」の行は出さない）、受信箱の抜粋と未読を直す。
    /// 相手の画面は次の読み直し（`full: true`）で消える。他人の通・無い会話は 404 `notFound`（`dm.ts` の `unsendMessage`）。
    ///
    /// 口は送る口の本文 `{unsend}`（経路を足さない）。**古いサーバーは空の本文として 400 で断る**ので、
    /// 口の無いサーバーで会話ごと消えることはない
    func unsend(_ id: String, messageId: String) async throws {
        struct Body: Encodable { let unsend: String }
        try await refusing {
            _ = try await api.authorizedVoid(.post, "/dm/\(encoded(id))/messages", body: Body(unsend: messageId))
        }
    }

    func markRead(_ id: String) async throws {
        try await refusing { _ = try await api.authorizedVoid(.put, "/dm/\(encoded(id))/read") }
    }

    func accept(_ id: String) async throws {
        try await refusing { _ = try await api.authorizedVoid(.post, "/dm/\(encoded(id))/accept") }
    }

    /// 自分の側だけ消す（相手の画面には残る）
    func remove(_ id: String) async throws {
        try await refusing { _ = try await api.authorizedVoid(.delete, "/dm/\(encoded(id))") }
    }

    /// 受け取ったリクエストを削除する（断る）。相手には知らされない
    func decline(_ id: String) async throws {
        try await refusing { _ = try await api.authorizedVoid(.delete, "/dm/\(encoded(id))/request") }
    }

    struct RemovedAll: Decodable { let removed: Int? }

    /// 受け取ったリクエストを全部削除する。消えた件数を返す
    func declineAll() async throws -> Int {
        try await refusing { try await api.authorized(.delete, "/dm/requests", as: RemovedAll.self).removed ?? 0 }
    }

    /// 通報（理由は写真の通報と同じ許可リスト・`ModerationService.ReportReason`）
    func report(_ id: String, reason: ModerationService.ReportReason, note: String?) async throws {
        struct Body: Encodable {
            let reason: String
            let note: String?
        }
        try await refusing {
            _ = try await api.authorizedVoid(.post, "/dm/\(encoded(id))/report",
                                             body: Body(reason: reason.rawValue, note: ModerationService.reportNote(note)))
        }
    }
}

// MARK: - 応答の形

/// 受信箱の1行の置き場所（`dmInbox.ts` の `DmEntryState`）。
/// `inbox` ふつうの会話・`request` 相手からのリクエスト・`pending` 自分が始めて相手がまだ話していない会話
enum DMEntryState: String, Decodable, Equatable {
    case inbox, request, pending

    /// 知らない値は `inbox` に倒す（リクエストの棚に入れて見落とさせない・一覧から消さない）
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DMEntryState(rawValue: raw) ?? .inbox
    }
}

/// `GET /dm` の1行
struct DMThread: Decodable, Identifiable, Equatable {
    /// 会話 id（`<小さい uid>_<大きい uid>`）
    let id: String
    let peerId: String
    let name: String
    let username: String?
    /// 相手が退会した（名前は「退会したユーザー」・プロフィールへは行かない）
    let deleted: Bool?
    /// 最後のメッセージの時刻（ISO）
    let t: String
    /// 最後のメッセージの抜粋（40字まで）
    let excerpt: String
    let unread: Int
    let state: DMEntryState
    /// 最後の1通が自分のものか（2026-11-10 から・journey.photo-web 8b03528db・本番 main 2b9a4384）。**欄の無い行（古い行・
    /// 口がまだ古い）は nil**——そのときは抜粋の頭に「あなた: 」を付けない
    let lastMine: Bool?

    var isDeleted: Bool { deleted == true }
    var isRequest: Bool { state == .request }
    /// 未読の点を出すか（リクエストは数えない・サーバーの `unreadConvCount` と同じ）
    var showsUnread: Bool { unread > 0 && !isRequest }

    private enum CodingKeys: String, CodingKey {
        case id, peerId, name, username, deleted, t, excerpt, unread, state, lastMine
    }

    init(id: String, peerId: String, name: String, username: String? = nil, deleted: Bool? = nil,
         t: String, excerpt: String, unread: Int, state: DMEntryState, lastMine: Bool? = nil) {
        self.id = id
        self.peerId = peerId
        self.name = name
        self.username = username
        self.deleted = deleted
        self.t = t
        self.excerpt = excerpt
        self.unread = unread
        self.state = state
        self.lastMine = lastMine
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        peerId = try c.decode(String.self, forKey: .peerId)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        username = try c.decodeIfPresent(String.self, forKey: .username)
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted)
        t = try c.decodeIfPresent(String.self, forKey: .t) ?? ""
        excerpt = try c.decodeIfPresent(String.self, forKey: .excerpt) ?? ""
        unread = max(0, try c.decodeIfPresent(Int.self, forKey: .unread) ?? 0)
        state = try c.decodeIfPresent(DMEntryState.self, forKey: .state) ?? .inbox
        lastMine = try? c.decodeIfPresent(Bool.self, forKey: .lastMine)
    }
}

/// `GET /dm`
struct DMInbox: Decodable, Equatable {
    let items: [DMThread]
    /// 未読のある会話の数（リクエストとブロックの相手は含めない）。ヘッダーの点はこれで出す
    let unread: Int
    /// 受け取ったリクエストの数
    let requestCount: Int

    static let empty = DMInbox(items: [], unread: 0, requestCount: 0)

    init(items: [DMThread], unread: Int, requestCount: Int) {
        self.items = items
        self.unread = unread
        self.requestCount = requestCount
    }

    private enum CodingKeys: String, CodingKey { case items, unread, requestCount }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([DMThread].self, forKey: .items) ?? []
        unread = max(0, try c.decodeIfPresent(Int.self, forKey: .unread) ?? 0)
        requestCount = max(0, try c.decodeIfPresent(Int.self, forKey: .requestCount) ?? 0)
    }

    /// 受信箱に並べる会話（リクエスト以外・新しい順はサーバーのまま）
    var conversations: [DMThread] { items.filter { !$0.isRequest } }
    /// リクエストの棚
    var requests: [DMThread] { items.filter(\.isRequest) }
}

/// 会話の1通
struct DMMessage: Decodable, Identifiable, Equatable {
    let id: String
    let from: String
    let mine: Bool
    let text: String
    let t: String
    /// `story`＝ストーリーへの返信から写された1通
    let via: String?
    /// 返信したストーリー（2026-11-10 から・ストーリーへの返信から写した通だけ）
    let storyId: String?
    /// 読む人から見た引用札（`dmStoryQuote.ts`）。新しい方から20件を越えた古い通は無い（＝分からない）
    let story: DMStoryQuote?
    /// 送った写真（2026-11-11 から・札 #541）
    let photoId: String?
    /// 写真だけの通（サーバーが古いアプリのために `text` を「写真を送りました」で埋めた）。**吹き出しの文は出さない**
    let photoOnly: Bool
    /// 読む人から見た写真の札（`dmPhotoQuote.ts`）。新しい方から20枚を越えた古い通は無い（＝分からない）
    let photo: DMPhotoQuote?

    var isStoryReply: Bool { via == "story" || storyId != nil }
    /// 写真を送った通
    var hasPhoto: Bool { photoId != nil }
    /// 吹き出しに出す文（写真だけの通は無い）
    var bubbleText: String? {
        if photoOnly { return nil }
        return text.isEmpty ? nil : text
    }

    init(id: String, from: String, mine: Bool, text: String, t: String, via: String? = nil,
         storyId: String? = nil, story: DMStoryQuote? = nil,
         photoId: String? = nil, photoOnly: Bool = false, photo: DMPhotoQuote? = nil) {
        self.id = id
        self.from = from
        self.mine = mine
        self.text = text
        self.t = t
        self.via = via
        self.storyId = storyId
        self.story = story
        self.photoId = photoId
        self.photoOnly = photoOnly
        self.photo = photo
    }

    private enum CodingKeys: String, CodingKey { case id, from, mine, text, t, via, storyId, story, photoId, photoOnly, photo }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
        mine = try c.decodeIfPresent(Bool.self, forKey: .mine) ?? false
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        t = try c.decodeIfPresent(String.self, forKey: .t) ?? ""
        via = try c.decodeIfPresent(String.self, forKey: .via)
        storyId = try? c.decodeIfPresent(String.self, forKey: .storyId)
        // 引用札が壊れていても1通は落とさない（札を出さないだけ）
        story = try? c.decodeIfPresent(DMStoryQuote.self, forKey: .story)
        photoId = (try? c.decodeIfPresent(String.self, forKey: .photoId)).flatMap { $0.isEmpty ? nil : $0 }
        // 写真の無い通で `photoOnly` だけ来ても、文を消さない（何も出ない吹き出しを作らない）
        photoOnly = photoId != nil && (try? c.decodeIfPresent(Bool.self, forKey: .photoOnly)) == true
        photo = try? c.decodeIfPresent(DMPhotoQuote.self, forKey: .photo)
    }
}

/// 会話の中の、送った写真の札（`GET /dm/{id}` の `items[].photo`・2026-11-11・札 #541）。
///
///     {id, state:"live", src, title?, location?, ownerId?}   見られる（`src` は縮小版 512px）
///     {id, state:"gone"}                                     見られない（消した・非公開・範囲の外・ブロック。理由は区別しない）
struct DMPhotoQuote: Decodable, Equatable {
    let id: String
    let state: String
    let src: String?
    let title: String?
    let location: String?
    let ownerId: String?

    init(id: String, state: String, src: String? = nil, title: String? = nil, location: String? = nil, ownerId: String? = nil) {
        self.id = id
        self.state = state
        self.src = src
        self.title = title
        self.location = location
        self.ownerId = ownerId
    }

    /// 見られるか（`live` で絵がある）
    var isLive: Bool { state == "live" && imageURL != nil }
    var imageURL: URL? { src.flatMap { $0.isEmpty ? nil : URL(string: $0) } }
}

/// 会話の中の、ストーリーへの返信の引用札（`GET /dm/{id}` の `items[].story`）。
///
///     {id, state:"live", mediaType:"image", src, expiresAt} / {id, state:"live", mediaType:"video", expiresAt}（動画は絵なし）
///     {id, state:"ended"}
struct DMStoryQuote: Decodable, Equatable {
    let id: String
    let state: String
    let mediaType: String?
    /// 止め絵（原寸の CloudFront の URL）。動画には無い
    let src: String?
    let expiresAt: String?

    init(id: String, state: String, mediaType: String? = nil, src: String? = nil, expiresAt: String? = nil) {
        self.id = id
        self.state = state
        self.mediaType = mediaType
        self.src = src
        self.expiresAt = expiresAt
    }
}

/// `GET /dm/{id}`
struct DMConversation: Decodable, Equatable {
    let id: String
    /// 変化なし（`since` より後に何も無い）。このときほかの欄は来ない
    let unchanged: Bool
    let peerId: String?
    let name: String?
    let username: String?
    let deleted: Bool?
    let state: DMEntryState?
    /// 送れるか（退会した相手・承認待ちの3通を使い切った後は false）
    let canSend: Bool?
    /// 始めた人だけ: 相手が話すまでに送れる残りの通数（0〜3）。相手が話したら来ない
    let requestRemaining: Int?
    /// 会話の最後の更新時刻（次の `since`）
    let t: String?
    /// `since` より後に送信の取り消しがあった: `items` は差分ではなく**全部**（画面は置き換える・2026-11-12）
    let full: Bool
    let items: [DMMessage]

    private enum CodingKeys: String, CodingKey {
        case id, unchanged, peerId, name, username, deleted, state, canSend, requestRemaining, t, full, items
    }

    init(id: String, unchanged: Bool = false, peerId: String?, name: String?, username: String? = nil,
         deleted: Bool? = nil, state: DMEntryState?, canSend: Bool?, requestRemaining: Int? = nil,
         t: String?, full: Bool = false, items: [DMMessage]) {
        self.id = id
        self.unchanged = unchanged
        self.peerId = peerId
        self.name = name
        self.username = username
        self.deleted = deleted
        self.state = state
        self.canSend = canSend
        self.requestRemaining = requestRemaining
        self.t = t
        self.full = full
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        unchanged = try c.decodeIfPresent(Bool.self, forKey: .unchanged) ?? false
        peerId = try c.decodeIfPresent(String.self, forKey: .peerId)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted)
        state = try c.decodeIfPresent(DMEntryState.self, forKey: .state)
        canSend = try c.decodeIfPresent(Bool.self, forKey: .canSend)
        requestRemaining = try c.decodeIfPresent(Int.self, forKey: .requestRemaining).map { max(0, $0) }
        t = try c.decodeIfPresent(String.self, forKey: .t)
        full = try c.decodeIfPresent(Bool.self, forKey: .full) ?? false
        items = try c.decodeIfPresent([DMMessage].self, forKey: .items) ?? []
    }
}

/// `POST /dm/{id}/messages` の応答
struct DMSendResult: Decodable, Equatable {
    let conversationId: String
    /// 送った人の側の置き場所（承認待ちの間は `pending`）
    let state: DMEntryState
    let message: DMMessage
}
