import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// DM の作り直し（2026-11-11・札 #541・owner 承認の案C「黒塗りに真鍮の縁」）と、承認後の URL のリンク・写真を送る口の試験。
///
/// 画面を持たない層（`DMLinks`・`DMMessage`・`DMPhotoQuote`・`DMText`・`DMService`・`DMPhotoSend`）は値で、
/// 画面の色・寸法・配線は元のファイルを読んで見張る（Linux では SwiftUI を描けない）
final class DirectMessageRedesignTests: XCTestCase {

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

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
            .joined(separator: "\n")
    }

    private func links(_ text: String) -> [String] {
        DMLinks.find(in: text).map { String(text[$0.range]) }
    }

    // MARK: - URL のリンク

    func testFindsLinksAndTrimsTrailingPunctuation() {
        XCTAssertEqual(links("見て https://example.com/a?b=1。"), ["https://example.com/a?b=1"])
        XCTAssertEqual(links("www.example.org/x、ここ"), ["www.example.org/x"])
        XCTAssertEqual(links("地図は journey-photo.com/spots にあります"), ["journey-photo.com/spots"])
        XCTAssertEqual(links("(https://a.jp)"), ["https://a.jp"])
        // 日本語が続いてもリンクに含めない
        XCTAssertEqual(links("https://a.jp/xです"), ["https://a.jp/x"])
        XCTAssertEqual(links("1つ目 a.com と 2つ目 https://b.net"), ["a.com", "https://b.net"])
        // スキームの無いものは https で開く
        XCTAssertEqual(DMLinks.find(in: "example.com").first?.url.absoluteString, "https://example.com")
        XCTAssertEqual(DMLinks.find(in: "http://example.com").first?.url.absoluteString, "http://example.com")
    }

    func testDoesNotLinkNonWebThings() {
        XCTAssertEqual(links("写真きれいですね。3.5mm の話・v1.2 です"), [])
        XCTAssertEqual(links("javascript:alert(1)"), [])
        XCTAssertEqual(links("mail me@example.com"), [], "メールアドレスのドメインをリンクにしている")
        XCTAssertEqual(links("tel:0312345678"), [])
        XCTAssertFalse(DMLinks.isOpenable(URL(string: "file:///etc/passwd")!))
        XCTAssertFalse(DMLinks.isOpenable(URL(string: "javascript:alert(1)")!))
        XCTAssertTrue(DMLinks.isOpenable(URL(string: "https://a.jp")!))
    }

    /// 名前・合言葉の付いた URL（見えている字と行き先が違う）はリンクにしない。中の字だけ別のリンクにもしない
    func testDoesNotLinkURLsWithUserInfo() throws {
        XCTAssertEqual(links("ログインはここ https://apple.com@evil.com/login です"), [])
        XCTAssertEqual(links("www.apple.com@evil.com"), [])
        XCTAssertEqual(links("http://user:pass@example.com/x"), [])
        XCTAssertFalse(DMLinks.isOpenable(try XCTUnwrap(URL(string: "https://apple.com@evil.com/login"))))
        // 前後のふつうのリンクは残る
        XCTAssertEqual(links("a.jp と https://apple.com@evil.com と https://b.jp"), ["a.jp", "https://b.jp"])
    }

    /// 見つける式は1回だけ作る（吹き出しを描くたびに作らない）
    func testLinkPatternsAreBuiltOnce() throws {
        let text = try source("Core/Text/DirectMessages.swift")
        let finder = text.components(separatedBy: "enum DMLinks {").dropFirst().first ?? ""
        let find = finder.components(separatedBy: "static func isOpenable").first ?? ""
        XCTAssertFalse(find.contains("try? NSRegularExpression"), "find のたびに式を作っている")
        XCTAssertTrue(finder.contains("private static let regexes: [NSRegularExpression]"))
    }

    @MainActor
    func testBubbleTextKeepsCharactersAndLinksOnlyTheURL() async {
        let text = "地図はここ https://example.com/x です"
        let linked = DMBubble.linked(text)
        XCTAssertEqual(String(linked.characters), text, "字の並びが変わっている")
        let linkedRuns = linked.runs.filter { $0.link != nil }
        XCTAssertEqual(linkedRuns.count, 1)
        XCTAssertEqual(linkedRuns.first?.link?.absoluteString, "https://example.com/x")
        XCTAssertEqual(DMBubble.linked("リンクなし").runs.filter { $0.link != nil }.count, 0)
    }

    // MARK: - 写真の通の読み取り（`dm.ts` の `shapeMessage`）

    func testDecodesPhotoMessage() throws {
        let conv = try decode("""
        {"id":"\(Self.conv)","state":"inbox","canSend":true,"t":"2026-11-11T00:00:00.000Z","items":[
          {"id":"a","from":"\(Self.me)","mine":true,"text":"写真を送りました","t":"2026-11-11T00:00:00.000Z",
           "photoId":"p1","photoOnly":true,
           "photo":{"id":"p1","state":"live","src":"https://cdn/p_t.webp","title":"弘前城の桜","location":"青森県弘前市","ownerId":"o"}},
          {"id":"b","from":"\(Self.peer)","mine":false,"text":"この場所です","t":"2026-11-11T00:00:01.000Z",
           "photoId":"p2","photo":{"id":"p2","state":"gone"}},
          {"id":"c","from":"\(Self.peer)","mine":false,"text":"ふつうの文","t":"2026-11-11T00:00:02.000Z","photoOnly":true}
        ]}
        """, as: DMConversation.self)
        let photoOnly = conv.items[0]
        XCTAssertTrue(photoOnly.hasPhoto)
        XCTAssertNil(photoOnly.bubbleText, "写真だけの通に「写真を送りました」の吹き出しを出している")
        XCTAssertEqual(photoOnly.photo, DMPhotoQuote(id: "p1", state: "live", src: "https://cdn/p_t.webp",
                                                     title: "弘前城の桜", location: "青森県弘前市", ownerId: "o"))
        XCTAssertTrue(photoOnly.photo?.isLive == true)
        let withText = conv.items[1]
        XCTAssertEqual(withText.bubbleText, "この場所です")
        XCTAssertEqual(withText.photo?.isLive, false)
        // 写真の無い通で photoOnly だけ来ても文を消さない
        XCTAssertEqual(conv.items[2].bubbleText, "ふつうの文")
        XCTAssertFalse(conv.items[2].hasPhoto)
    }

    func testBrokenPhotoQuoteKeepsTheMessage() throws {
        let m = try decode("""
        {"id":"a","from":"x","mine":false,"text":"写真を送りました","t":"2026-11-11T00:00:00.000Z","photoId":"p1","photoOnly":true,"photo":{"state":3}}
        """, as: DMMessage.self)
        XCTAssertNil(m.photo)
        XCTAssertTrue(m.hasPhoto)
        XCTAssertEqual(DMPhotoQuote(id: "p", state: "live", src: "").isLive, false, "絵の無い live を見られる扱いにしている")
    }

    // MARK: - 写真を送る口

    func testSendCarriesPhotoIdOnlyWhenGiven() async throws {
        StubProtocol.respond(status: 200, body: """
        {"success":true,"conversationId":"\(Self.conv)","state":"inbox",
         "message":{"id":"k-12345678","from":"\(Self.me)","mine":true,"text":"写真を送りました","t":"2026-11-11T00:00:00.000Z","photoId":"p1","photoOnly":true}}
        """)
        let result = try await service().send(Self.conv, text: "", clientId: "k-12345678", photoId: "p1")
        XCTAssertEqual(result.message.photoId, "p1")
        let body = try XCTUnwrap(StubProtocol.lastBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json, ["text": "", "id": "k-12345678", "photoId": "p1"])
    }

    func testPhotoSendBuildsTheConversationId() async throws {
        StubProtocol.respond(status: 200, body: """
        {"success":true,"conversationId":"\(Self.conv)","state":"inbox",
         "message":{"id":"k-12345678","from":"\(Self.me)","mine":true,"text":"写真を送りました","t":"2026-11-11T00:00:00.000Z"}}
        """)
        try await DMPhotoSend.send(service: service(), me: Self.peer, peerId: Self.me, photoId: "p1", text: "  見て  ",
                                   clientId: "k-12345678")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/dm/\(Self.conv)/messages")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(StubProtocol.lastBody)) as? [String: String])
        XCTAssertEqual(json["text"], "見て")
        // 自分あて・ログインなしは要求を出さない
        StubProtocol.reset()
        do {
            try await DMPhotoSend.send(service: service(), me: nil, peerId: Self.me, photoId: "p1")
            XCTFail("ログインなしで送った")
        } catch {
            XCTAssertEqual(error as? DMPhotoSend.Failure, .invalid)
        }
        XCTAssertEqual(StubProtocol.requestCount, 0)
    }

    /// 写真の札の見せ方: 分からない（札が無い）は言い切らない・見る人がブロックした持ち主の写真は出さない
    func testPhotoCardStates() {
        func m(_ photo: DMPhotoQuote?, has: Bool = true) -> DMMessage {
            DMMessage(id: "a", from: "x", mine: false, text: "写真を送りました", t: "2026-11-11T00:00:00.000Z",
                      photoId: has ? "p1" : nil, photoOnly: has, photo: photo)
        }
        let live = DMPhotoQuote(id: "p1", state: "live", src: "https://cdn/p.jpg", ownerId: "owner")
        XCTAssertEqual(DMPhotoCardState.of(m(nil, has: false), blocked: []), .none)
        XCTAssertEqual(DMPhotoCardState.of(m(nil), blocked: []), .unknown, "札の無い写真を「表示できません」と言い切っている")
        XCTAssertEqual(DMPhotoCardState.of(m(live), blocked: []), .live(live))
        XCTAssertEqual(DMPhotoCardState.of(m(live), blocked: ["owner"]), .gone, "ブロックした人の写真を出している")
        XCTAssertEqual(DMPhotoCardState.of(m(DMPhotoQuote(id: "p1", state: "gone")), blocked: []), .gone)
        XCTAssertEqual(DMPhotoCardState.of(m(DMPhotoQuote(id: "p1", state: "live", src: "")), blocked: []), .gone)
        XCTAssertEqual(DMPhotoCardState.of(m(DMPhotoQuote(id: "p1", state: "later")), blocked: []), .unknown)
    }

    /// 写真だけの通の抜粋（サーバーは日本語だけ）を端末の言葉で出す
    func testPhotoOnlyExcerptFollowsTheLanguage() {
        func row(_ excerpt: String, mine: Bool?) -> DMThread {
            DMThread(id: "c", peerId: "p", name: "A", t: "2026-11-11T00:00:00.000Z", excerpt: excerpt, unread: 0,
                     state: .inbox, lastMine: mine)
        }
        XCTAssertEqual(DMText.excerpt(row(DMText.serverPhotoText, mine: false), language: "en"), "Sent you a photo")
        XCTAssertEqual(DMText.excerpt(row(DMText.serverPhotoText, mine: true), language: "en"), "You: Sent a photo")
        XCTAssertEqual(DMText.excerpt(row(DMText.serverPhotoText, mine: true), language: "ja"), "あなた: 写真を送りました")
        XCTAssertEqual(DMText.excerpt(row("こんにちは", mine: false), language: "en"), "こんにちは")
        XCTAssertEqual(DMText.photoOnlyText(mine: false, language: "ja"), "写真が届きました")
    }

    func testPhotoRefusalWords() {
        XCTAssertEqual(DMText.refusal(status: 400, code: "requestPhoto", fallback: "x", language: "ja"),
                       "承認されるまでは写真を送れません。文字で送ってください")
        XCTAssertEqual(DMText.refusal(status: 404, code: "photoNotFound", fallback: "x", language: "ja"), "この写真は送れません")
        XCTAssertTrue(DMText.returnsToField(code: "requestPhoto"))
        XCTAssertTrue(DMText.returnsToField(code: "photoNotFound"))
    }

    // MARK: - 吹き出しのかたまり

    func testBubblesJoinWithinFiveMinutesFromTheSamePerson() {
        func m(_ id: String, mine: Bool, _ t: String, story: Bool = false, photo: Bool = false, photoOnly: Bool = false) -> DMMessage {
            DMMessage(id: id, from: mine ? "me" : "you", mine: mine, text: "x", t: t,
                      storyId: story ? "s" : nil, photoId: photo ? "p" : nil, photoOnly: photoOnly)
        }
        let a = m("a", mine: true, "2026-11-11T10:00:00.000Z")
        let b = m("b", mine: true, "2026-11-11T10:02:00.000Z")
        let c = m("c", mine: false, "2026-11-11T10:03:00.000Z")
        let d = m("d", mine: true, "2026-11-11T10:20:00.000Z")
        XCTAssertFalse(DMText.joinsPrevious(current: a, previous: nil))
        XCTAssertTrue(DMText.joinsPrevious(current: b, previous: a))
        XCTAssertFalse(DMText.joinsPrevious(current: c, previous: b), "相手の吹き出しとつないでいる")
        XCTAssertFalse(DMText.joinsPrevious(current: d, previous: b), "5分を越えた吹き出しをつないでいる")
        // 札（ストーリー・写真）のある通は、つながず前と離す。写真だけの通（吹き出しが無い）にもつながない
        XCTAssertFalse(DMText.joinsPrevious(current: m("e", mine: true, "2026-11-11T10:02:30.000Z", story: true), previous: b))
        XCTAssertFalse(DMText.joinsPrevious(current: m("f", mine: true, "2026-11-11T10:02:30.000Z", photo: true), previous: b))
        XCTAssertFalse(DMText.joinsPrevious(current: b, previous: m("g", mine: true, "2026-11-11T10:01:00.000Z", photo: true, photoOnly: true)))
    }

    func testSpokenLabels() {
        XCTAssertEqual(DMText.photoSpoken(title: "桜", location: "弘前", mine: true), "あなたが送った写真、桜、撮影地 弘前")
        XCTAssertEqual(DMText.photoSpoken(title: nil, location: nil, mine: false), "届いた写真")
        XCTAssertEqual(DMText.storyCardSpoken(owner: "A", mine: true, state: .ended), "A さんのストーリーへの返信、ストーリーは終了しました")
    }

    // MARK: - 寸法（案C）

    func testLookValues() {
        XCTAssertEqual(DMLook.rowAvatar, 52)
        XCTAssertEqual(DMLook.headerAvatar, 32)
        XCTAssertEqual(DMLook.storyThumbWidth, 104)
        XCTAssertEqual(DMLook.storyThumbHeight, 138)
        XCTAssertEqual(DMLook.photoWidth, 220)
        XCTAssertEqual(DMLook.photoHeight / DMLook.photoWidth, 1.25, accuracy: 0.001, "写真が 4:5 でない")
        XCTAssertEqual(DMLook.bubbleBorder, 1)
        // 最大幅は会話の幅の 78%（固定の 304 をやめた）
        XCTAssertEqual(DMLook.bubbleMaxWidth(container: 375), 375 * 0.78, accuracy: 0.001)
        XCTAssertEqual(DMLook.bubbleMaxWidth(container: 320), 320 * 0.78, accuracy: 0.001)
        XCTAssertEqual(DMLook.bubbleMaxWidth(container: 0), 390 * 0.78, accuracy: 0.001)
        for size in [DMLook.sendSize, DMLook.fieldHeight] { XCTAssertGreaterThanOrEqual(size, WebTheme.minTapTarget) }
    }

    // MARK: - 画面の色と配線（元のファイルを読む）

    /// 吹き出しの色の型の名前（元のファイルの字を探すだけ。型そのものは @MainActor なので呼ばない）
    private static let colorsEnum = "DMBubble" + "Colors"

    /// 案C: 自分の吹き出しは accent-soft の塗り＋真鍮の縁、相手は surface-8。送るボタン・承認は真鍮の塗りに墨。
    /// 入力欄と削除の縁は outline。**白の塗り（accentBackground）を DM の画面に残さない**
    func testColorsFollowPlanC() throws {
        let parts = try source("Features/Messages/DMParts.swift")
        let colors = parts.components(separatedBy: "enum " + Self.colorsEnum + " {").dropFirst().first ?? ""
        XCTAssertTrue(colors.contains("mine ? WebTheme.accentSoft : WebTheme.surface8"))
        XCTAssertTrue(colors.contains("mine ? WebTheme.accent : Color.clear"))
        let view = try source("Features/Messages/DMConversationView.swift")
        let requests = try source("Features/Messages/DMRequestsView.swift")
        for (name, text) in [("会話", view), ("リクエスト", requests), ("部品", parts)] {
            XCTAssertFalse(text.contains("WebTheme.accentBackground"), "\(name): 白の塗りが残っている")
            XCTAssertFalse(text.contains("Color.white.opacity(0.28)"), "\(name): 部品の縁が 3:1 に届かない白 28%")
            XCTAssertFalse(text.contains("Color.white.opacity(0.2), lineWidth"), "\(name): 入力欄の縁が白 20%")
        }
        XCTAssertTrue(view.contains("sendEnabled ? WebTheme.accentFill : Color.white.opacity(0.16)"), "送るボタンが真鍮でない")
        XCTAssertTrue(view.contains("fieldError != nil ? WebTheme.danger : WebTheme.outline"), "入力欄の縁が outline でない")
        XCTAssertEqual(view.components(separatedBy: ".background(WebTheme.accentFill, in: Capsule())").count - 1, 1, "帯の承認")
        XCTAssertEqual(requests.components(separatedBy: ".background(WebTheme.accentFill, in: Capsule())").count - 1, 1, "札の承認")
        XCTAssertTrue(view.contains(Self.colorsEnum + ".fill(mine: mine)"))
        XCTAssertTrue(view.contains("shape.stroke(" + Self.colorsEnum + ".border(mine: true), lineWidth: DMLook.bubbleBorder)"))
        XCTAssertFalse(view.contains("maxWidth: CGFloat = 304"), "吹き出しの最大幅が固定のまま")
    }

    /// 字は JPFont の段か jpSystemFont（大きい文字の設定に追従）。DM の画面に固定の大きさの字を置かない（印は除く）
    func testTextFollowsDynamicType() throws {
        for file in ["Features/Messages/DMConversationView.swift", "Features/Messages/DMInboxView.swift",
                     "Features/Messages/DMRequestsView.swift", "Features/Messages/DMParts.swift"] {
            let text = try source(file)
            for line in text.components(separatedBy: "\n") where line.contains(".font(.system(size:") {
                XCTAssertTrue(isIconLine(line, in: text), "\(file): 固定の字 \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        let view = try source("Features/Messages/DMConversationView.swift")
        XCTAssertFalse(view.contains(".font(.system(size: 15))"), "本文が固定の 15")
        XCTAssertFalse(view.contains(".font(.system(size: 16, weight: .semibold))"), "見出しの名前が固定の 16")
        let parts = try source("Features/Messages/DMParts.swift")
        XCTAssertFalse(parts.contains(".font(.system(size: 15, weight: unread ? .bold : .medium))"))
        XCTAssertFalse(parts.contains(".font(.system(size: 14, weight: unread ? .medium : .regular))"))
    }

    /// 固定の大きさが許されるのは印（直前の行が `Image(systemName:`）だけ
    private func isIconLine(_ line: String, in text: String) -> Bool {
        let lines = text.components(separatedBy: "\n")
        guard let i = lines.firstIndex(of: line), i > 0 else { return false }
        return lines[i - 1].contains("Image(systemName:") || line.contains("Image(systemName:")
    }

    /// 受信箱: 顔は行の外（輪を押すとストーリー・行を押すと会話）・一覧の下の説明文はやめた・空の受信箱に顔の列
    func testInboxLayout() throws {
        let inbox = try source("Features/Messages/DMInboxView.swift")
        XCTAssertTrue(inbox.contains("DMStoryFace(userId: thread.peerId"))
        XCTAssertEqual(inbox.components(separatedBy: "DMText.startHint").count - 1, 1, "一覧の下の説明文が残っている")
        XCTAssertTrue(inbox.contains("DMPeopleFacesRow(people: faces)"))
        XCTAssertTrue(inbox.contains("route = .start(DMStart.seed(user))"), "顔を押してもその人との会話にならない")
        XCTAssertTrue(inbox.contains("DMStart.candidates(fetched.users, me: me, blocked: hidden.blockedUserIds)"),
                      "顔の列がブロックした人・自分をふるっていない")
        let parts = try source("Features/Messages/DMParts.swift")
        let row = parts.components(separatedBy: "struct DMThreadRow: View {").dropFirst().first ?? ""
        XCTAssertFalse(row.prefix(1500).contains("DMAvatar("), "行の中に顔を入れている（ボタンの中にボタン）")
    }

    /// 会話: 写真の札・ストーリーの写真 104×138・日付の線・リンク・写真だけの通は吹き出しを出さない
    func testConversationWiring() throws {
        let view = try source("Features/Messages/DMConversationView.swift")
        XCTAssertTrue(view.contains("if message.hasPhoto { photoCard(for: message) }"))
        XCTAssertTrue(view.contains("if let text = message.bubbleText {"), "写真だけの通に吹き出しを出している")
        XCTAssertTrue(view.contains("DMDayDivider(text: DMText.dayLabel(date))"))
        XCTAssertTrue(view.contains(".frame(width: DMLook.storyThumbWidth,"))
        XCTAssertTrue(view.contains("Text(Self.linked(text))"), "本文のリンクを押せない")
        XCTAssertTrue(view.contains("piece.link = link.url"))
        XCTAssertTrue(view.contains("PhotoDetailView(photo: openedPhoto, fromPublicFeed: openedPhotoIsPublic)"))
        XCTAssertTrue(view.contains(#".accessibilityIdentifier("dm.photoCard.live")"#))
        XCTAssertTrue(view.contains("DMPhotoCardState.of(message, blocked: hidden.blockedUserIds)"), "ブロックした持ち主の写真を出す")
        XCTAssertTrue(view.contains(#"identifier: "dm.photoCard.unknown""#))
        // 写真を開く: 公開の一覧 → 絞った写真のうち自分に見えるぶん → 自分の写真
        XCTAssertTrue(view.contains("environment.photos.restrictedFeed()"), "フォロワー限定の写真を開けない")
        XCTAssertTrue(view.contains(#"identifier: "dm.photoCard.gone""#))
        // 承認前の会話では今までどおり URL を断る（サーバーの requestUrl・欄に戻す）
        XCTAssertTrue(DMText.returnsToField(code: "requestUrl"))
    }
}
