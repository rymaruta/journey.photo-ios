import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// メッセージ（DM・第1段・札 #505・2026-11-10）の試験。
///
/// サーバー（`api-user/src/dm.ts`・本番 journey.photo-web main 2b9a4384）の応答の形・断り（`code`）・規則を、
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

    // MARK: - 2026-11-10 に足した欄（journey.photo-web 8b03528db・本番 main 2b9a4384）。欄が無いときは今までどおり

    /// 受信箱の `lastMine`: 欄があるときだけ「あなた: 」
    func testLastMinePrefixesExcerptOnlyWhenPresent() throws {
        let inbox = try decode("""
        {"items":[
          {"id":"a_b","peerId":"b","name":"B","t":"2026-11-09T00:00:00.000Z","excerpt":"ありがとう","unread":0,"state":"inbox","lastMine":true},
          {"id":"a_c","peerId":"c","name":"C","t":"2026-11-09T00:00:00.000Z","excerpt":"やあ","unread":0,"state":"inbox","lastMine":false},
          {"id":"a_d","peerId":"d","name":"D","t":"2026-11-09T00:00:00.000Z","excerpt":"古い行","unread":0,"state":"inbox"}
        ],"unread":0,"requestCount":0}
        """, as: DMInbox.self)
        XCTAssertEqual(inbox.items.map { DMText.excerpt($0, language: "ja") }, ["あなた: ありがとう", "やあ", "古い行"])
        XCTAssertNil(inbox.items[2].lastMine)
    }

    /// 会話の `storyId`・`story` と引用札の見せ方（期限を過ぎたら手元で「終了」に倒す・欄が無ければ枠だけ）
    func testStoryQuoteStates() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let iso = ISO8601DateFormatter()
        let later = iso.string(from: now.addingTimeInterval(3600)), earlier = iso.string(from: now.addingTimeInterval(-60))
        let conv = try decode("""
        {"id":"a_b","peerId":"b","name":"B","state":"inbox","canSend":true,"t":"x","items":[
          {"id":"m1","from":"b","mine":false,"text":"見て","t":"1","via":"story","storyId":"s1",
           "story":{"id":"s1","state":"live","mediaType":"image","src":"https://cdn.example/s1.jpg","expiresAt":"\(later)"}},
          {"id":"m2","from":"b","mine":false,"text":"動画","t":"2","storyId":"s2","story":{"id":"s2","state":"live","mediaType":"video","expiresAt":"\(later)"}},
          {"id":"m3","from":"b","mine":false,"text":"終わり","t":"3","storyId":"s3","story":{"id":"s3","state":"ended"}},
          {"id":"m4","from":"b","mine":false,"text":"期限切れ","t":"4","storyId":"s4","story":{"id":"s4","state":"live","mediaType":"image","src":"https://cdn.example/s4.jpg","expiresAt":"\(earlier)"}},
          {"id":"m5","from":"b","mine":false,"text":"古い通","t":"5","via":"story","storyId":"s5"},
          {"id":"m6","from":"b","mine":false,"text":"ふつう","t":"6"},
          {"id":"m7","from":"b","mine":false,"text":"壊れた札","t":"7","storyId":"s7","story":"x"}
        ]}
        """, as: DMConversation.self)
        let states = conv.items.map { DMStoryCardState.of($0, now: now) }
        XCTAssertEqual(states, [
            .live(storyId: "s1", image: URL(string: "https://cdn.example/s1.jpg"), isVideo: false),
            .live(storyId: "s2", image: nil, isVideo: true),
            .ended, .ended, .unknown, .none, .unknown,
        ])
        XCTAssertEqual(states[0].liveStoryId, "s1")
        XCTAssertNil(states[2].liveStoryId)
        // 開いている間に次に期限が来る時刻（その時刻に描き直す）。期限の無い札・終わった札・過ぎた札は数えない
        XCTAssertEqual(DMStoryCardState.nextExpiry(conv.items, after: now), NotificationGroups.parse(later))
        XCTAssertNil(DMStoryCardState.nextExpiry(conv.items, after: now.addingTimeInterval(7200)))
        // 一覧に無かったストーリーは札を「終了」に倒す
        var log = DMThreadLog(messages: conv.items)
        log.markStoryEnded("s1")
        XCTAssertEqual(DMStoryCardState.of(log.messages[0], now: now), .ended)
        XCTAssertEqual(DMStoryCardState.of(log.messages[1], now: now), .live(storyId: "s2", image: nil, isVideo: true))
    }

    /// ストーリーの返信の応答の `dm` 欄: 写ったときだけ会話へ。欄が無ければ2人から組む（今までの作り）
    func testStoryReplyOutcome() throws {
        let mirrored = try decode(#"{"success":true,"reply":{},"dm":{"conversationId":"\#(Self.conv)"}}"#, as: StoryReplyOutcome.self)
        XCTAssertTrue(mirrored.knowsMirror)
        XCTAssertEqual(mirrored.conversationToOpen(me: Self.me, owner: Self.peer), Self.conv)
        let skipped = try decode(#"{"success":true,"dm":null,"dmSkipped":"requestLimit"}"#, as: StoryReplyOutcome.self)
        XCTAssertTrue(skipped.knowsMirror)
        XCTAssertEqual(skipped.skipped, "requestLimit")
        XCTAssertNil(skipped.conversationToOpen(me: Self.me, owner: Self.peer), "写らなかった返信で会話へ誘う")
        let old = try decode(#"{"success":true,"reply":{}}"#, as: StoryReplyOutcome.self)
        XCTAssertFalse(old.knowsMirror)
        XCTAssertEqual(old.conversationToOpen(me: Self.me, owner: Self.peer), Self.conv)
        XCTAssertNil(old.conversationToOpen(me: Self.me, owner: Self.me))
        let bad = try decode(#"{"dm":{"conversationId":"../x"}}"#, as: StoryReplyOutcome.self)
        XCTAssertNil(bad.conversationToOpen(me: Self.me, owner: Self.peer))
    }

    /// 返信の応答を読む口: 欄を返す・読めない応答でも返信は成功（今までの作り）
    func testStoryServiceReplyReturnsOutcome() async throws {
        let stories = StoryService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                                 tokenProvider: StubTokenProvider(token: "t"), session: session))
        StubProtocol.respond(status: 200, body: #"{"success":true,"dm":null,"dmSkipped":"requestUrl"}"#)
        let outcome = try await stories.reply(id: "story-1", text: "https://example.com")
        XCTAssertEqual(outcome.skipped, "requestUrl")
        StubProtocol.respond(status: 200, body: "")
        let empty = try await stories.reply(id: "story-1", text: "やあ")
        XCTAssertEqual(empty, .unknown)
    }

    /// 自分のストーリーの返信の行の矢印: 受信箱に在る会話だけ
    func testRepliesListOpensOnlyKnownConversations() {
        let inbox = DMInbox(rebuilding: [DMThread(id: Self.conv, peerId: Self.peer, name: "B", t: "", excerpt: "",
                                                  unread: 0, state: .request)])
        XCTAssertEqual(StoryReplyConversation.id(me: Self.me, replier: Self.peer, hasText: true, inbox: inbox), Self.conv)
        XCTAssertNil(StoryReplyConversation.id(me: Self.me, replier: Self.peer, hasText: true, inbox: .empty),
                     "写らなかった返信に矢印を出した")
        XCTAssertNil(StoryReplyConversation.id(me: Self.me, replier: Self.peer, hasText: false, inbox: inbox))
        XCTAssertNil(StoryReplyConversation.id(me: Self.me, replier: Self.me, hasText: true, inbox: inbox))
    }

    /// ベルの `storyreply` の `dmConvId`: 行はベルに出さない。ベルの未読はサーバーの `unreadExcludingDm`（アプリで数え直さない）、
    /// 欄が無ければ `unread`
    func testBellSkipsRepliesMirroredIntoMessages() throws {
        let page = try decode("""
        {"items":[
          {"type":"storyreply","byId":"u1","byName":"A","t":"3","photoId":"story-1","replyKind":"text","dmConvId":"\(Self.conv)"},
          {"type":"storyreply","byId":"u2","byName":"B","t":"2","photoId":"story-1","replyKind":"reaction"},
          {"type":"like","byId":"u3","byName":"C","t":"1","photoId":"p1"},
          {"type":"like","byId":"u4","byName":"D","t":"0","photoId":"p2"}
        ],"unread":3,"unreadExcludingDm":2}
        """, as: NotificationService.Page.self)
        XCTAssertEqual(page.bellUnread, 2, "サーバーの unreadExcludingDm を使っていない（受信箱と二重に数える）")
        XCTAssertEqual(page.items[0].dmConvId, Self.conv)
        XCTAssertEqual(page.items[0].replyKind, "text")
        XCTAssertTrue(page.items[0].isInMessages)
        XCTAssertFalse(page.items[1].isInMessages)
        let old = try decode(#"{"items":[{"type":"storyreply","byId":"u1","t":"1"}],"unread":1}"#, as: NotificationService.Page.self)
        XCTAssertEqual(old.bellUnread, 1, "欄が無いのに unread を使っていない")
        // アプリで数え直さない: 欄があれば、行の dmConvId に関わらずサーバーの数
        let server = try decode(#"{"items":[{"type":"storyreply","byId":"u1","t":"1","dmConvId":"a_b"}],"unread":1,"unreadExcludingDm":1}"#,
                                as: NotificationService.Page.self)
        XCTAssertEqual(server.bellUnread, 1)
        let shown = NotificationsView.shown(page.items, blocked: [], filter: .all)
        XCTAssertEqual(shown.count, 3)
        XCTAssertFalse(shown.contains { $0.dmConvId != nil }, "受信箱に入った返信がベルにも出ている")
    }

    // MARK: - アイコンの数字を置く順番（2026-11-10 再確認の指摘1）

    /// 起動直後の読み込みの順を作って、アプリが置く数字を確かめる。**両方を今の人で読めるまでは触らない**
    /// （受信箱が先に読めた回に「0＋メッセージの未読」でお知らせの分を消していた）
    func testBadgeWaitsForBothCountsInEitherOrder() {
        struct Step { var bellOwner: String?; var bell: Int; var dmOwner: String?; var dmLoaded: Bool; var dm: Int }
        func value(_ s: Step, me: String? = "u1") -> Int? {
            AppBadge.syncValue(me: me, bellOwner: s.bellOwner, bellUnread: s.bell,
                               messagesOwner: s.dmOwner, messagesLoaded: s.dmLoaded, messagesUnread: s.dm)
        }
        // 受信箱 → お知らせ の順
        var s = Step(bellOwner: nil, bell: 0, dmOwner: "u1", dmLoaded: true, dm: 2)
        XCTAssertNil(value(s), "お知らせを読む前に数字を置いた（お知らせの分が消える）")
        s.bellOwner = "u1"; s.bell = 3
        XCTAssertEqual(value(s), 5)
        // お知らせ → 受信箱 の順
        var r = Step(bellOwner: "u1", bell: 3, dmOwner: "u1", dmLoaded: false, dm: 0)
        XCTAssertNil(value(r), "受信箱を読む前に数字を置いた（メッセージの分が消える）")
        r.dmLoaded = true; r.dm = 2
        XCTAssertEqual(value(r), 5)
        // お知らせを読んだ（0）あとは、メッセージの未読だけ残る
        r.bell = 0
        XCTAssertEqual(value(r), 2)
        // 前の人の数・ログアウト中は触らない
        XCTAssertNil(value(Step(bellOwner: "u0", bell: 1, dmOwner: "u1", dmLoaded: true, dm: 1)))
        XCTAssertNil(value(Step(bellOwner: "u1", bell: 1, dmOwner: "u0", dmLoaded: true, dm: 1)))
        XCTAssertNil(value(s, me: nil))
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
/// 2026-11-10 判断: このクラスの試験は全部 `async` にする。同期のままだと Linux の自動登録が
/// `main actor-isolated` でコンパイルできない（PR #512 の単体テストの記録・bd5467af と同じ直し）
@MainActor
final class DirectMessageMainActorTests: XCTestCase {

    private static let me = "11111111-1111-4111-8111-111111111111"
    private static let peer = "22222222-2222-4222-8222-222222222222"
    private static let conv = "\(me)_\(peer)"

    /// 受信箱の口。**要求を出す手前で止められる**（`Gate`・応答を遅らせない・`TestGate.swift` の注記）
    private func service(gate: Gate? = nil) -> DMService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return DMService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                        tokenProvider: StubTokenProvider(token: "t"),
                                        session: URLSession(configuration: config),
                                        retryPause: { _ in },
                                        beforeRequest: gate.map { gate in { (_: URLRequest) async in await gate.wait() } }))
    }

    private static func inboxJSON(_ id: String, unread: Int) -> String {
        #"{"items":[{"id":"\#(id)","peerId":"p-\#(id)","name":"\#(id)","t":"2026-11-09T00:00:00.000Z","excerpt":"x","unread":\#(unread),"state":"inbox"}],"unread":\#(unread),"requestCount":0}"#
    }

    /// **最初の読み込みの途中に手元で変えても、読めた一覧を捨てない**（2026-11-10 レビュー指摘3）。
    /// プッシュから会話が先に積まれると、受信箱を読み終える前に会話が既読の印を置く。
    /// 世代を進めて答えを捨てると、空の一覧を「読めた」にしてしまう
    func testApplyDuringFirstLoadKeepsTheAnswer() async {
        StubProtocol.reset()
        defer { StubProtocol.reset() }
        StubProtocol.respond(status: 200, body: Self.inboxJSON("a", unread: 2))
        let gate = Gate(holds: 1)
        let store = DMInboxStore()
        let dm = service(gate: gate)
        let task = Task { await store.refresh(service: dm, owner: "u1") }
        await gate.untilWaiting()
        store.apply { $0.markingRead("a") }
        await gate.open()
        await task.value
        XCTAssertEqual(store.phase, .loaded)
        XCTAssertEqual(store.inbox.items.map(\.id), ["a"], "読めた一覧を捨てて空にした")
        XCTAssertEqual(store.inbox.items.first?.unread, 0, "読み込み中に置いた既読の印が消えた")
    }

    /// 古い読み込みの答えで、新しい読み込みの答えを上書きしない（世代の確かめ・`DMInboxStore.refresh`）
    func testOlderRefreshDoesNotOverwriteNewer() async {
        StubProtocol.reset()
        defer { StubProtocol.reset() }
        // 1本目は止めておき、2本目が先に答えを受け取る（順に返す: 先に着いた要求が1つ目）
        StubProtocol.respondInOrder([(200, Self.inboxJSON("new", unread: 1)), (200, Self.inboxJSON("old", unread: 1))])
        let gate = Gate(holds: 1)
        let store = DMInboxStore()
        let dm = service(gate: gate)
        let first = Task { await store.refresh(service: dm, owner: "u1") }
        await gate.untilWaiting()
        await store.refresh(service: dm, owner: "u1")
        XCTAssertEqual(store.inbox.items.map(\.id), ["new"])
        await gate.open()
        await first.value
        XCTAssertEqual(store.inbox.items.map(\.id), ["new"], "古い答えが新しい答えを上書きした")
    }

    /// 読み込みの間に人が替わったら、前の人の答えを置かない（持ち主の確かめ）
    func testRefreshForPreviousOwnerIsDropped() async {
        StubProtocol.reset()
        defer { StubProtocol.reset() }
        StubProtocol.respond(status: 200, body: Self.inboxJSON("a", unread: 1))
        let gate = Gate(holds: 1)
        let store = DMInboxStore()
        let dm = service(gate: gate)
        let task = Task { await store.refresh(service: dm, owner: "u1") }
        await gate.untilWaiting()
        store.use(owner: "u2")
        await gate.open()
        await task.value
        XCTAssertTrue(store.inbox.items.isEmpty, "前の人の会話を次の人に出した")
        XCTAssertEqual(store.owner, "u2")
    }

    /// 前面で届いたメッセージの通知: 開いている会話の分は帯を出さず、読み直しの合図だけ（レビュー指摘6）
    func testForegroundDMOnOpenConversationIsSilent() async {
        let router = NotificationRouter()
        XCTAssertFalse(router.noteDMArrival(Self.conv), "開いていない会話の通知を黙らせた")
        router.conversationOpened(Self.conv)
        let before = router.dmArrival.serial
        XCTAssertTrue(router.noteDMArrival(Self.conv))
        XCTAssertEqual(router.dmArrival, NotificationRouter.DMArrival(conversationId: Self.conv, serial: before + 1))
        XCTAssertFalse(router.noteDMArrival("a_b"), "別の会話の通知まで黙らせた")
        XCTAssertTrue(NotificationRouter.presentation(forDMWhileShowing: true).isEmpty)
        XCTAssertFalse(NotificationRouter.presentation(forDMWhileShowing: false).isEmpty)
        router.conversationClosed(Self.conv)
        XCTAssertFalse(router.noteDMArrival(Self.conv))
    }

    /// アイコンの数字はサーバーと同じ「お知らせの未読＋メッセージの未読会話」（レビュー指摘1）。
    /// 消す通知はその会話のメッセージの通知だけ
    func testBadgeCountsMessagesAndRemovesOnlyThatConversation() async {
        XCTAssertEqual(AppBadge.count(bellUnread: 0, messagesUnread: 2), 2, "お知らせを読んだらメッセージの未読まで消えた")
        XCTAssertEqual(AppBadge.count(bellUnread: 3, messagesUnread: 1), 4)
        XCTAssertEqual(AppBadge.count(bellUnread: -1, messagesUnread: 0), 0)
        let delivered: [(id: String, userInfo: [AnyHashable: Any])] = [
            ("n1", ["type": "dm", "convId": Self.conv]),
            ("n2", ["type": "dm", "convId": "a_b"]),
            ("n3", ["type": "like", "photoId": "p"]),
            ("n4", ["type": "dm", "convId": Self.conv]),
        ]
        XCTAssertEqual(AppBadge.deliveredIds(delivered, conversationId: Self.conv), ["n1", "n4"])
    }

    func testStoreDropsAnotherPersonsInbox() async {
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

    func testPushPayloadOpensConversation() async {
        XCTAssertEqual(NotificationRouter.dmConversationId(["type": "dm", "convId": Self.conv, "byId": Self.peer]), Self.conv)
        XCTAssertNil(NotificationRouter.dmConversationId(["type": "like", "convId": Self.conv]))
        XCTAssertNil(NotificationRouter.dmConversationId(["type": "dm", "convId": "../user/account"]))
        XCTAssertNil(NotificationRouter.dmConversationId(["type": "dm"]))
        // ストーリーへの文字の返信が受信箱に入った通知（2026-11-10 から `convId` 付き）も会話へ。欄が無ければ今までどおりお知らせへ
        XCTAssertEqual(NotificationRouter.dmConversationId(["type": "storyreply", "convId": Self.conv, "photoId": "story-1"]), Self.conv)
        XCTAssertNil(NotificationRouter.dmConversationId(["type": "storyreply", "photoId": "story-1"]))
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
