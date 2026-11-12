import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// DM の送信取り消し（2026-11-12・owner「DM 送信取り消し必要だわ」「取り消しました。みたいなメッセージはいらない」）。
///
/// サーバー（journey.photo-web `api-user/src/dm.ts` の `unsendMessage`）の口の形・`full` の読み直し・
/// 画面を持たない層（`DMThreadLog`・`DMUnsend`）と、画面の配線（元のファイルを読む）を見張る。
/// 2026-11-12 判断: 試験は全部 `async`（`DirectMessageWiringTests` と同じ）。見る型はどれも main actor に乗らないので、
/// 組は main actor にしない（`setUp` で `session` を書けなくなる）
final class DMUnsendTests: XCTestCase {

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

    private func message(_ id: String, mine: Bool = true, t: String, text: String? = nil,
                         storyId: String? = nil, photoId: String? = nil) -> DMMessage {
        DMMessage(id: id, from: mine ? Self.me : Self.peer, mine: mine, text: text ?? id, t: t,
                  via: storyId == nil ? nil : "story", storyId: storyId, photoId: photoId)
    }

    // MARK: - 口

    /// 取り消しは送る口（`POST /dm/{id}/messages`）の本文 `{unsend}` だけ。**DELETE にしない**
    /// （口の無い古いサーバーで `DELETE /dm/{id}` に届くと会話ごと消える。本文 `{unsend}` なら 400 で断られる）
    func testUnsendPostsOnlyTheMessageId() async throws {
        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
        try await service().unsend(Self.conv, messageId: "k-12345678")
        XCTAssertEqual(StubProtocol.requests.last, "POST /dm/\(Self.conv)/messages")
        let body = try XCTUnwrap(StubProtocol.lastBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json, ["unsend": "k-12345678"], "本文に取り消す id 以外（text など）を載せている")
    }

    /// 他人の通・無い会話はサーバーが 404 `notFound` で断る（`Refused` で受ける）
    func testUnsendRefusalIsConversationMissing() async throws {
        StubProtocol.respond(status: 404, body: #"{"error":"メッセージが見つかりません","code":"notFound"}"#)
        do {
            try await service().unsend(Self.conv, messageId: "k-12345678")
            XCTFail("断りが投げられていない")
        } catch let refused as DMService.Refused {
            XCTAssertTrue(refused.isConversationMissing)
        }
    }

    /// `since` より後に取り消しがあれば、サーバーは全部を `full: true` で返す。欄の無い応答は差分のまま
    func testDecodesFullConversation() async throws {
        let full = try JSONDecoder.api.decode(DMConversation.self, from: Data("""
        {"id":"\(Self.conv)","peerId":"\(Self.peer)","name":"旅人B","state":"inbox","canSend":true,
         "t":"2026-11-12T00:00:05.000Z","full":true,"items":[]}
        """.utf8))
        XCTAssertTrue(full.full)
        let diff = try JSONDecoder.api.decode(DMConversation.self, from: Data(#"{"id":"a_b","items":[]}"#.utf8))
        XCTAssertFalse(diff.full)
    }

    // MARK: - 一覧（押したらすぐ消える・失敗したら戻る）

    /// 自分の1通だけ外せる。相手の通・無い id は外さない。戻すと元の位置（時刻の順）
    func testLogUnsendRemovesOnlyMineAndRestoresInPlace() async {
        var log = DMThreadLog(messages: [
            message("a-0000001", mine: false, t: "2026-11-12T00:00:01.000Z"),
            message("b-0000002", t: "2026-11-12T00:00:02.000Z"),
            message("c-0000003", mine: false, t: "2026-11-12T00:00:03.000Z"),
        ])
        XCTAssertNil(log.unsend("a-0000001"), "相手の通を外した")
        XCTAssertNil(log.unsend("z-9999999"))
        XCTAssertEqual(log.messages.count, 3)
        let removed = log.unsend("b-0000002")
        XCTAssertEqual(removed?.id, "b-0000002")
        XCTAssertEqual(log.messages.map(\.id), ["a-0000001", "c-0000003"], "取り消した1通の跡が残っている")
        log.restore(try! XCTUnwrap(removed))
        XCTAssertEqual(log.messages.map(\.id), ["a-0000001", "b-0000002", "c-0000003"], "元の位置に戻らない")
    }

    /// 相手の画面: `full` の応答で置き換えると、取り消された1通が消える（差分の重ねでは残る）
    func testFullReplaceDropsTheUnsentMessage() async {
        var log = DMThreadLog(messages: [
            message("a-0000001", mine: false, t: "2026-11-12T00:00:01.000Z"),
            message("b-0000002", mine: false, t: "2026-11-12T00:00:02.000Z"),
        ])
        let server = [message("a-0000001", mine: false, t: "2026-11-12T00:00:01.000Z")]
        var merged = log
        merged.merge(server)
        XCTAssertEqual(merged.messages.count, 2, "前提: 差分の重ねでは消えない")
        log.replace(with: server)
        XCTAssertEqual(log.messages.map(\.id), ["a-0000001"])
    }

    // MARK: - 入力欄に戻す文

    /// 文字だけの自分の通は文を戻す。写真・ストーリーへの返信・相手の通は戻さない（取り消すだけ）
    func testReturnedTextOnlyForPlainTextOfMine() async {
        XCTAssertEqual(DMUnsend.returnedText(message("m-0000001", t: "t", text: "まちがい")), "まちがい")
        XCTAssertNil(DMUnsend.returnedText(message("m-0000002", mine: false, t: "t", text: "相手")))
        XCTAssertNil(DMUnsend.returnedText(message("m-0000003", t: "t", text: "返信", storyId: "s1")),
                     "ストーリーへの返信をただの文として戻している")
        XCTAssertNil(DMUnsend.returnedText(message("m-0000004", t: "t", text: "写真に添えた文", photoId: "p1")),
                     "写真の通の文を戻している（送り直すと写真の無い通になる）")
    }

    /// 打ちかけの文は消さない（後ろに改行して足す）・上限で切る。失敗したら戻したままの欄だけ元に戻す
    func testDraftKeepsWhatWasBeingTyped() async {
        XCTAssertEqual(DMUnsend.draft(current: "", returning: "まちがい"), "まちがい")
        XCTAssertEqual(DMUnsend.draft(current: "  \n", returning: "まちがい"), "まちがい")
        XCTAssertEqual(DMUnsend.draft(current: "打ちかけ", returning: "まちがい"), "打ちかけ\nまちがい")
        XCTAssertEqual(DMUnsend.draft(current: "あ", returning: "いいい", limit: 3), "あ\nい")
        XCTAssertEqual(DMUnsend.draftAfterFailure(current: "打ちかけ\nまちがい", returned: "打ちかけ\nまちがい", before: "打ちかけ"),
                       "打ちかけ")
        XCTAssertEqual(DMUnsend.draftAfterFailure(current: "直した文", returned: "まちがい", before: ""), "直した文",
                       "戻したあとに打ち直した文を消している")
    }

    // MARK: - 画面の配線（Linux では SwiftUI を描けないので、元のファイルを読む）

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func slice(_ text: String, from start: String, to end: String) -> String {
        guard let s = text.range(of: start),
              let e = text.range(of: end, range: s.upperBound..<text.endIndex) else {
            XCTFail("「\(start)」〜「\(end)」が無い")
            return ""
        }
        return String(text[s.lowerBound..<e.lowerBound])
    }

    /// 長押しの「送信を取り消す」は自分の通だけ。確かめのダイアログを挟まない。写真・ストーリーの札にも付ける
    func testMenuOffersUnsendOnlyForMineWithoutConfirm() async throws {
        let view = try source("Features/Messages/DMConversationView.swift")
        let menu = slice(view, from: "private func bubbleMenu(_ message: DMMessage, text: String)", to: "\n    }\n")
        XCTAssertTrue(menu.contains("if message.mine { unsendButton(message) }"), "相手の吹き出しにも取り消しが出る")
        XCTAssertTrue(view.contains(".contextMenu { bubbleMenu(message, text: text) }"))
        XCTAssertTrue(view.contains("unsendMenu(storyCard(for: message), for: message)"), "ストーリーへの返信の札から取り消せない")
        XCTAssertTrue(view.contains(".modifier(DMUnsendMenu(enabled: mine) { unsendButton(message) })"), "写真の札から取り消せない")
        let button = slice(view, from: "private func unsendButton(_ message: DMMessage)", to: "\n    }\n")
        XCTAssertTrue(button.contains("Task { await unsend(message) }"), "押してすぐ取り消さない（確かめを挟んでいる）")
        XCTAssertTrue(button.contains(#"L("送信を取り消す", "Unsend")"#))
        XCTAssertFalse(view.contains("送信を取り消しました"), "「取り消しました」の文を出している")
    }

    /// 押したらすぐ消え、文は欄へ。失敗したら1通と欄を戻して赤の一言（`actionError`）
    func testUnsendActionOrder() async throws {
        let view = try source("Features/Messages/DMConversationView.swift")
        let action = slice(view, from: "private func unsend(_ message: DMMessage) async {", to: "private func accept() async")
        guard let remove = action.range(of: "log.unsend(message.id)"),
              let call = action.range(of: "environment.dm.unsend(conversationId, messageId: removed.id)"),
              let toField = action.range(of: "draft = returned") else {
            return XCTFail("取り消しの手順が見つからない")
        }
        XCTAssertLessThan(remove.lowerBound, call.lowerBound, "サーバーの答えを待ってから消している（押したらすぐ消えない）")
        XCTAssertLessThan(toField.lowerBound, call.lowerBound, "文を欄に戻すのが答えの後")
        XCTAssertTrue(action.contains("log.restore(removed)"), "失敗したときに1通を戻さない")
        XCTAssertTrue(action.contains("actionError = L("), "失敗したときに一言を出さない")
        XCTAssertTrue(action.contains("store.refresh(service: environment.dm"), "受信箱の最後の一言を読み直さない")
    }

    /// 相手の画面: 読み直しが `full` なら置き換え、会話ごと外れた（404 notFound）なら画面からも消す
    func testPeerScreenDropsUnsentOnRefresh() async throws {
        let view = try source("Features/Messages/DMConversationView.swift")
        let refresh = slice(view, from: "private func refreshSince() async {", to: "private func markRead() async {")
        XCTAssertTrue(refresh.contains("if fetched.full {\n            log.replace(with: fetched.items)"),
                      "取り消しのあとの全部の応答を差分として重ねている（消えた1通が残る）")
        XCTAssertTrue(refresh.contains("refused.isConversationMissing && !isNew"))
        XCTAssertTrue(refresh.contains("log.replace(with: [])"))
    }
}
