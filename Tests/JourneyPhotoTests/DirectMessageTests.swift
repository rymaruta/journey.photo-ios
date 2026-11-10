import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// メッセージ（DM・第1段・札 #505・2026-11-10）の試験。
///
/// サーバー（`api-user/src/dm.ts`・`staging/dm-phase1` 2b70b2a1e）の応答の形・断り（`code`）・規則を、
/// 画面を持たない層（`DMService`・`DMRules`・`DMThreadLog`・`DMInbox`・`DMReplyGate`）で確かめる。
/// 画面の配線は元のファイルを読んで見張る（Linux では SwiftUI を描けない）
final class DirectMessageTests: XCTestCase {

    private static let me = "11111111-1111-4111-8111-111111111111"
    private static let peer = "22222222-2222-4222-8222-222222222222"
    private static let conv = "\(me)_\(peer)"

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset()
    }

    override func tearDown() {
        StubProtocol.reset()
        super.tearDown()
    }

    private func service() -> DMService {
        DMService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                 tokenProvider: StubTokenProvider(token: "t"), session: session,
                                 retryPause: { _ in }))
    }

    private func decode<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
        try JSONDecoder.api.decode(T.self, from: Data(json.utf8))
    }

    // MARK: - 応答の読み取り（サーバーの `listInbox`・`getConversation`・`sendResult` の形）

    func testDecodesInbox() throws {
        let inbox = try decode("""
        {"items":[
          {"id":"\(Self.conv)","peerId":"\(Self.peer)","name":"旅人B","username":"tabi_b",
           "t":"2026-11-09T11:50:00.000Z","excerpt":"テスト1通目","unread":3,"state":"request"},
          {"id":"a_b","peerId":"b","name":"退会したユーザー","deleted":true,
           "t":"2026-11-08T11:50:00.000Z","excerpt":"ありがとう","unread":0,"state":"inbox"},
          {"id":"a_c","peerId":"c","name":"C","t":"2026-11-07T11:50:00.000Z","excerpt":"x","unread":1,"state":"pending"}
        ],"unread":1,"requestCount":1}
        """, as: DMInbox.self)
        XCTAssertEqual(inbox.items.count, 3)
        XCTAssertEqual(inbox.items[0].state, .request)
        XCTAssertEqual(inbox.items[0].username, "tabi_b")
        XCTAssertTrue(inbox.items[1].isDeleted)
        XCTAssertEqual(inbox.items[2].state, .pending)
        XCTAssertEqual(inbox.requests.map(\.id), [Self.conv])
        XCTAssertEqual(inbox.conversations.map(\.id), ["a_b", "a_c"])
        XCTAssertEqual(inbox.unread, 1)
        XCTAssertEqual(inbox.requestCount, 1)
    }

    /// 知らない置き場所は受信箱に倒す（行を落とさない）・欠けた欄で落ちない
    func testInboxToleratesUnknownStateAndMissingFields() throws {
        let inbox = try decode(#"{"items":[{"id":"a_b","peerId":"b","state":"archived"}]}"#, as: DMInbox.self)
        XCTAssertEqual(inbox.items.first?.state, .inbox)
        XCTAssertEqual(inbox.items.first?.unread, 0)
        XCTAssertEqual(inbox.unread, 0)
        XCTAssertEqual(inbox.requestCount, 0)
    }

    func testDecodesConversationAndUnchanged() throws {
        let full = try decode("""
        {"id":"\(Self.conv)","peerId":"\(Self.peer)","name":"旅人B","username":"tabi_b","state":"pending",
         "canSend":false,"requestRemaining":0,"t":"2026-11-09T11:52:00.000Z",
         "items":[{"id":"m-test-0001","from":"\(Self.me)","mine":true,"text":"テスト1通目","t":"2026-11-09T11:50:00.000Z","via":"story"}]}
        """, as: DMConversation.self)
        XCTAssertFalse(full.unchanged)
        XCTAssertEqual(full.state, .pending)
        XCTAssertEqual(full.canSend, false)
        XCTAssertEqual(full.requestRemaining, 0)
        XCTAssertEqual(full.items.first?.isStoryReply, true)
        XCTAssertEqual(full.items.first?.mine, true)

        let same = try decode(#"{"id":"a_b","unchanged":true,"items":[]}"#, as: DMConversation.self)
        XCTAssertTrue(same.unchanged)
        XCTAssertNil(same.requestRemaining)
        XCTAssertTrue(same.items.isEmpty)
    }

    func testDecodesSendResult() throws {
        let result = try decode("""
        {"success":true,"conversationId":"\(Self.conv)","state":"pending",
         "message":{"id":"m-test-0002","from":"\(Self.me)","mine":true,"text":"テスト2通目","t":"2026-11-09T11:51:00.000Z"}}
        """, as: DMSendResult.self)
        XCTAssertEqual(result.conversationId, Self.conv)
        XCTAssertEqual(result.state, .pending)
        XCTAssertEqual(result.message.id, "m-test-0002")
    }

    // MARK: - 口（道・本文・断り）

    /// 続きは `POST /dm/{id}/messages` に `{text, id}`。**鍵（id）を本文に載せる**（再送で二重に入れない）
    func testSendPostsTextAndClientId() async throws {
        StubProtocol.respond(status: 200, body: """
        {"success":true,"conversationId":"\(Self.conv)","state":"inbox",
         "message":{"id":"k-12345678","from":"\(Self.me)","mine":true,"text":"やあ","t":"2026-11-09T11:51:00.000Z"}}
        """)
        _ = try await service().send(Self.conv, text: "やあ", clientId: "k-12345678")
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/dm/\(Self.conv)/messages")
        let body = try XCTUnwrap(StubProtocol.lastBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json, ["text": "やあ", "id": "k-12345678"])
    }

    /// 断りは `code` つきの `Refused` に包む（画面の言葉は `code` で選ぶ）
    func testRefusalCarriesCode() async throws {
        StubProtocol.respond(status: 400, body: #"{"error":"承認されるまではリンクを送れません","code":"requestUrl"}"#)
        do {
            _ = try await service().send(Self.conv, text: "https://example.com", clientId: "k-12345678")
            XCTFail("断りが投げられていない")
        } catch let refused as DMService.Refused {
            XCTAssertEqual(refused.status, 400)
            XCTAssertEqual(refused.code, "requestUrl")
            XCTAssertEqual(refused.errorDescription, DMText.refusal(status: 400, code: "requestUrl", fallback: ""))
        }
    }

    /// 道の無い 404（本番にまだ口が無い）を「会話が無い」と読まない
    func testMissingRouteIsNotAMissingConversation() async throws {
        StubProtocol.respond(status: 404, body: #"{"message":"Not Found"}"#)
        do {
            _ = try await service().conversation(Self.conv)
            XCTFail("404 が投げられていない")
        } catch let refused as DMService.Refused {
            XCTAssertFalse(refused.isConversationMissing)
        }
        StubProtocol.respond(status: 404, body: #"{"error":"会話が見つかりません","code":"notFound"}"#)
        do {
            _ = try await service().conversation(Self.conv)
            XCTFail("404 が投げられていない")
        } catch let refused as DMService.Refused {
            XCTAssertTrue(refused.isConversationMissing)
        }
    }

    /// 各口の道とメソッド（サーバーの 10 口のうち、画面が使う 9 口）
    func testRoutes() async throws {
        StubProtocol.respond(status: 200, body: #"{"ok":true,"removed":2,"items":[],"unread":0,"requestCount":0}"#)
        let dm = service()
        _ = try await dm.inbox()
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/dm")
        try await dm.markRead(Self.conv)
        XCTAssertEqual(StubProtocol.requests.last, "PUT /dm/\(Self.conv)/read")
        try await dm.accept(Self.conv)
        XCTAssertEqual(StubProtocol.requests.last, "POST /dm/\(Self.conv)/accept")
        try await dm.decline(Self.conv)
        XCTAssertEqual(StubProtocol.requests.last, "DELETE /dm/\(Self.conv)/request")
        try await dm.remove(Self.conv)
        XCTAssertEqual(StubProtocol.requests.last, "DELETE /dm/\(Self.conv)")
        let removed = try await dm.declineAll()
        XCTAssertEqual(removed, 2)
        XCTAssertEqual(StubProtocol.requests.last, "DELETE /dm/requests")
        try await dm.report(Self.conv, reason: .minor, note: "  ")
        XCTAssertEqual(StubProtocol.requests.last, "POST /dm/\(Self.conv)/report")
        let body = try XCTUnwrap(StubProtocol.lastBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["reason"] as? String, "minor")
        _ = try? await dm.conversation(Self.conv, since: "2026-11-09T11:50:00.000Z")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.query?.contains("since="), true)
    }

    /// パスに入れられない id は要求を出さない
    func testRejectsUnsafeConversationId() async {
        do {
            _ = try await service().conversation("../user/account")
            XCTFail("危ない id で要求を出した")
        } catch {
            XCTAssertEqual(error as? APIError, .invalidIdentifier)
        }
        XCTAssertEqual(StubProtocol.requestCount, 0)
    }

    // MARK: - 決まり

    /// 会話 id はサーバーの `convIdOf` と同じ（小文字・小さい方が先）
    func testConversationIdMatchesServer() {
        XCTAssertEqual(DMRules.conversationId(Self.peer, Self.me), Self.conv)
        XCTAssertEqual(DMRules.conversationId(Self.me, Self.peer), Self.conv)
        XCTAssertEqual(DMRules.conversationId("B-UPPER", "a-lower"), "a-lower_b-upper")
        XCTAssertEqual(DMRules.peer(of: Self.conv, me: Self.me), Self.peer)
        XCTAssertEqual(DMRules.peer(of: Self.conv, me: Self.peer), Self.me)
        XCTAssertNil(DMRules.peer(of: Self.conv, me: "33333333-3333-4333-8333-333333333333"))
        XCTAssertNil(DMRules.peer(of: "abc", me: Self.me))
    }

    /// 送る鍵はサーバーが受ける形（`^[A-Za-z0-9_-]{8,64}$`）で、毎回違う
    func testClientIdShape() {
        let a = DMRules.newClientId(), b = DMRules.newClientId()
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(DMRules.isValidClientId(a))
        XCTAssertFalse(DMRules.isValidClientId("short"))
        XCTAssertFalse(DMRules.isValidClientId("has space here"))
    }

    /// URL の見分けはサーバーの試験（`dm.test.ts`「URL の判定」）と同じ答え。日本語に挟まれた URL も拾う
    func testContainsURLMatchesServerCases() {
        for text in ["https://example.com/a", "http://x", "www.example.org", "example.com",
                     "ｈｔｔｐｓ：／／ｅｘａｍｐｌｅ．ｃｏｍ", "見て bit.ly/abc", "foo.jp",
                     "ここexample.comです", "example . com", "example[.]com", "example(dot)com", "example。com",
                     "discord.gg/abc", "exa\u{200B}mple.com"] {
            XCTAssertTrue(DMRules.containsURL(text), text)
        }
        for text in ["こんにちは", "写真きれいですね。", "3.5mm の話", "v1.2 です", "Fine. To be honest"] {
            XCTAssertFalse(DMRules.containsURL(text), text)
        }
    }

    // MARK: - 断りの言葉（`code` ごと）

    func testRefusalTextPerCode() {
        func ja(_ code: String?, _ status: Int = 400, fallback: String = "") -> String {
            DMText.refusal(status: status, code: code, fallback: fallback, language: "ja")
        }
        XCTAssertEqual(ja("requestUrl"), "URLは送れません。リンクを消して、文字だけで送ってください")
        XCTAssertEqual(ja("requestLimit", 429), "承認されるまで、送れるのは文字3通までです")
        XCTAssertEqual(ja("busy", 409), "混み合っています。もう一度お試しください")
        XCTAssertEqual(ja("dailyLimit", 429), "今日はこれ以上送れません。明日またお試しください")
        XCTAssertEqual(ja("blockedByMe", 403), "ブロック中の相手には送れません")
        XCTAssertEqual(ja("notFound", 404), "この会話は表示できません")
        XCTAssertEqual(ja("unavailable", 409), "いま送れません")
        // 知らない code はサーバーの文（日本語の画面）
        XCTAssertEqual(ja("somethingNew", 400, fallback: "サーバーの文"), "サーバーの文")
        // 英語の画面に日本語を出さない
        let en = DMText.refusal(status: 400, code: "requestUrl", fallback: "", language: "en")
        XCTAssertFalse(APIError.containsJapanese(en))
        for code in ["requestLimit", "busy", "dailyLimit", "selfFull", "unavailable", "blockedByMe", "notFound", "empty"] {
            XCTAssertFalse(APIError.containsJapanese(DMText.refusal(status: 400, code: code, fallback: "", language: "en")), code)
        }
    }

    /// 押し直しても通らない断りは入力に戻す。混雑・落ちた通信は吹き出しに残して「もう一度送る」
    func testWhichRefusalsReturnToTheField() {
        for code in ["requestUrl", "requestLimit", "blockedByMe", "dailyLimit"] {
            XCTAssertTrue(DMText.returnsToField(code: code), code)
        }
        XCTAssertFalse(DMText.returnsToField(code: "busy"))
        XCTAssertFalse(DMText.returnsToField(code: nil))
    }

    /// 承認前の残りの案内（板: 2通目のあとは「あと1通」・使い切ったら 3/3）
    func testRequestNote() {
        XCTAssertNil(DMText.requestNote(name: "B", remaining: nil, language: "ja"))
        XCTAssertEqual(DMText.requestNote(name: "B", remaining: 3, language: "ja"), "B さんが承認するまで、送れるのは文字3通までです")
        XCTAssertEqual(DMText.requestNote(name: "B", remaining: 2, language: "ja"), "B さんが承認するまで、送れるのは文字3通までです")
        XCTAssertEqual(DMText.requestNote(name: "B", remaining: 1, language: "ja"), "B さんが承認するまで、あと1通送れます")
        XCTAssertEqual(DMText.requestNote(name: "B", remaining: 0, language: "ja"), "B さんが承認するまで、送れるのは文字3通までです（3/3）")
    }

    // MARK: - 未読の数え方

    private func row(_ id: String, peer: String, unread: Int, state: DMEntryState) -> DMThread {
        DMThread(id: id, peerId: peer, name: id, t: "2026-11-09T00:00:00.000Z", excerpt: "", unread: unread, state: state)
    }

    /// 点に数えるのは受信箱の未読だけ。**リクエストとブロックした相手は数えない**（サーバーの `unreadConvCount`）
    func testUnreadCountsInboxOnly() {
        let inbox = DMInbox(rebuilding: [
            row("a", peer: "pa", unread: 2, state: .inbox),
            row("b", peer: "pb", unread: 5, state: .request),
            row("c", peer: "pc", unread: 1, state: .pending),
            row("d", peer: "pd", unread: 0, state: .inbox),
            row("e", peer: "pe", unread: 3, state: .inbox),
        ])
        XCTAssertEqual(inbox.unread, 3)
        XCTAssertEqual(inbox.unreadConversations(), 3)
        XCTAssertEqual(inbox.unreadConversations(hiding: ["pe"]), 2)
        XCTAssertEqual(inbox.requestCount, 1)
        XCTAssertEqual(inbox.requestTotal(hiding: ["pb"]), 0)
    }

    /// 開いた・承認した・消したあとの数（サーバーの答えを待たずに点を合わせる）
    func testLocalChangesKeepCountsInStep() {
        let inbox = DMInbox(rebuilding: [
            row("a", peer: "pa", unread: 2, state: .inbox),
            row("b", peer: "pb", unread: 1, state: .request),
        ])
        let read = inbox.markingRead("a")
        XCTAssertEqual(read.unreadConversations(), 0)
        let accepted = read.accepting("b")
        XCTAssertEqual(accepted.requestCount, 0)
        XCTAssertEqual(accepted.unreadConversations(), 1, "承認した会話の未読は受信箱で数える")
        let removed = accepted.removing("b")
        XCTAssertEqual(removed.items.map(\.id), ["a"])
        XCTAssertEqual(removed.unreadConversations(), 0)
    }

    // MARK: - 二重に送らない

    private func message(_ id: String, mine: Bool = true, t: String = "2026-11-09T00:00:00.000Z") -> DMMessage {
        DMMessage(id: id, from: mine ? Self.me : Self.peer, mine: mine, text: id, t: t)
    }

    /// 同じ鍵の1通は控えに2つ入らない・サーバーに入った後も足さない
    func testSameClientIdIsNotQueuedTwice() {
        var log = DMThreadLog()
        XCTAssertTrue(log.begin(text: "やあ", clientId: "k-00000001"))
        XCTAssertFalse(log.begin(text: "やあ", clientId: "k-00000001"), "同じ鍵で2通目を控えに入れた")
        XCTAssertEqual(log.outgoing.count, 1)
        log.succeed("k-00000001", with: message("k-00000001"))
        XCTAssertFalse(log.begin(text: "やあ", clientId: "k-00000001"), "届いた1通の鍵でもう1通を入れた")
        XCTAssertEqual(log.messages.count, 1)
        XCTAssertTrue(log.outgoing.isEmpty)
    }

    /// 送れなかった1通の押し直しは**同じ鍵**（サーバーが二重に入れない）。送っている間は押し直せない
    func testRetryKeepsTheSameClientId() {
        var log = DMThreadLog()
        log.begin(text: "やあ", clientId: "k-00000002")
        XCTAssertNil(log.retry("k-00000002"), "送っている最中に押し直せた")
        log.fail("k-00000002", reason: "送れませんでした")
        XCTAssertFalse(log.isSending)
        XCTAssertEqual(log.retry("k-00000002"), "やあ")
        XCTAssertEqual(log.outgoing.map(\.clientId), ["k-00000002"])
        XCTAssertTrue(log.isSending)
        // 応答が落ちたあと、読み直しで同じ1通が届いた: 控えは外れ、1通だけ
        log.merge([message("k-00000002")])
        XCTAssertTrue(log.outgoing.isEmpty)
        XCTAssertEqual(log.messages.map(\.id), ["k-00000002"])
    }

    /// 読み直しの重なり（送った応答と `since` の答え）でも同じ id は1通・時刻の順
    func testMergeDeduplicatesAndOrders() {
        var log = DMThreadLog(messages: [message("b", t: "2026-11-09T00:00:02.000Z")])
        log.merge([message("a", mine: false, t: "2026-11-09T00:00:01.000Z"), message("b", t: "2026-11-09T00:00:02.000Z"),
                   message("c", t: "2026-11-09T00:00:03.000Z")])
        XCTAssertEqual(log.messages.map(\.id), ["a", "b", "c"])
        XCTAssertTrue(log.peerHasSpoken)
        log.replace(with: [message("c", t: "2026-11-09T00:00:03.000Z")])
        XCTAssertEqual(log.messages.map(\.id), ["c"])
    }

    /// 断られた1通は控えから外し、本文を返す（入力に戻す）
    func testWithdrawReturnsText() {
        var log = DMThreadLog()
        log.begin(text: "https://example.com", clientId: "k-00000003")
        XCTAssertEqual(log.withdraw("k-00000003"), "https://example.com")
        XCTAssertTrue(log.outgoing.isEmpty)
        XCTAssertNil(log.withdraw("k-00000003"))
    }

    // MARK: - ストーリーの返信欄の門

    func testReplyGate() {
        let fresh = DMReplyGate.from(nil, peerId: Self.peer)
        XCTAssertEqual(fresh.remaining, 3, "まだ会話が無い相手は承認前の3通")
        XCTAssertTrue(fresh.refusesURL(in: "見て https://example.com"))
        XCTAssertFalse(fresh.refusesURL(in: "きれい"))
        XCTAssertFalse(fresh.limitReached)
        XCTAssertEqual(fresh.afterSending().afterSending().afterSending().remaining, 0)
        XCTAssertTrue(fresh.afterSending().afterSending().afterSending().limitReached)

        let request = DMConversation(id: Self.conv, peerId: Self.peer, name: "B", state: .request, canSend: true,
                                     requestRemaining: nil, t: nil, items: [])
        let reply = DMReplyGate.from(request, peerId: Self.peer)
        XCTAssertNil(reply.remaining, "相手からのリクエストに返すのは承認（上限なし）")
        XCTAssertFalse(reply.refusesURL(in: "https://example.com"))

        let used = DMConversation(id: Self.conv, peerId: Self.peer, name: "B", state: .pending, canSend: false,
                                  requestRemaining: 0, t: nil, items: [])
        let gate = DMReplyGate.from(used, peerId: Self.peer)
        XCTAssertTrue(gate.limitReached)
        XCTAssertEqual(gate.note(name: "B", language: "ja"), "B さんが承認するまで、これ以上送れません（3/3）")
    }

    // MARK: - 通報の理由

    func testReportReasons() {
        XCTAssertEqual(DMReportReason.allCases.map(\.serverReason),
                       [.harassment, .sexual, .minor, .spam, .other, .other])
        XCTAssertEqual(DMReportReason.impersonation.note(adding: " 本人ではない "), "なりすまし：本人ではない")
        XCTAssertEqual(DMReportReason.impersonation.note(adding: ""), "なりすまし")
        XCTAssertEqual(DMReportReason.spam.note(adding: " x "), "x")
    }
}

/// 主アクタの部品（受信箱の控え・通知の行き先）の試験
@MainActor
final class DirectMessageMainActorTests: XCTestCase {

    private static let me = "11111111-1111-4111-8111-111111111111"
    private static let peer = "22222222-2222-4222-8222-222222222222"
    private static let conv = "\(me)_\(peer)"

    func testStoreDropsAnotherPersonsInbox() {
        let store = DMInboxStore()
        store.setForTesting(DMInbox(rebuilding: [DMThread(id: "a", peerId: "pa", name: "a", t: "2026-11-09T00:00:00.000Z", excerpt: "", unread: 1, state: .inbox)]), owner: "u1")
        XCTAssertTrue(store.hasUnread(hiding: []))
        XCTAssertFalse(store.hasUnread(hiding: ["pa"]))
        store.use(owner: "u2")
        XCTAssertEqual(store.inbox, .empty)
        XCTAssertEqual(store.phase, .loading)
        XCTAssertFalse(store.hasUnread(hiding: []))
    }

    // MARK: - 通知

    func testPushPayloadOpensConversation() {
        XCTAssertEqual(NotificationRouter.dmConversationId(["type": "dm", "convId": Self.conv, "byId": Self.peer]), Self.conv)
        XCTAssertNil(NotificationRouter.dmConversationId(["type": "like", "convId": Self.conv]))
        XCTAssertNil(NotificationRouter.dmConversationId(["type": "dm", "convId": "../user/account"]))
        XCTAssertNil(NotificationRouter.dmConversationId(["type": "dm"]))
        let router = NotificationRouter()
        let before = router.conversationRequests
        router.openConversation(Self.conv, now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(router.conversationRequests, before + 1)
        XCTAssertEqual(router.takePendingConversation(now: Date(timeIntervalSince1970: 10)), Self.conv)
        XCTAssertNil(router.takePendingConversation(now: Date(timeIntervalSince1970: 11)), "2回受け取れた")
        router.openConversation(Self.conv, now: Date(timeIntervalSince1970: 0))
        XCTAssertNil(router.takePendingConversation(now: Date(timeIntervalSince1970: 10_000)), "古い行き先を開いた")
    }
}
