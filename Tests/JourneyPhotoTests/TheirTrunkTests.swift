import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JourneyPhoto

/// 人のトランク（2026-10-18・板 TheirTrunk・TheirInside・ProfileTrunk・TrunkPrivacy）:
/// 読み方・404 の扱い・地名の無いラベルの描き方・見せる設定と乗車券の送り方・写真の引き方
final class TheirTrunkTests: XCTestCase {

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

    private func service() -> TrunkService {
        TrunkService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                    tokenProvider: StubTokenProvider(token: "t"), session: session))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.api.decode(T.self, from: Data(json.utf8))
    }

    /// サーバーの `readTheirTrunk` の形（確かめたラベル・伏せた形のラベル・会員証・乗車券）
    private static let full = #"""
    { "userId": "u-1", "model": "starchart",
      "stuck": [
        { "id": "s2", "kind": "season", "place": { "name": "京都", "latin": "Kyoto", "country": "日本" },
          "season": "spring", "seed": 41207, "at": "2026-04-03", "where": { "location": "京都" } },
        { "id": "s1", "kind": "timeslot", "seed": 77031, "foil": true, "pos": { "x": 0.4, "y": 0.5, "rot": 6 },
          "place": { "name": "" }, "where": null },
        { "id": "s0", "kind": "milestone", "seed": 1001, "place": { "name": "" }, "where": null }
      ],
      "equipped": { "handle": "handle.7", "lock": "nope", "pins": ["pin.1", "pin.1"], "patches": [] },
      "posts": 42,
      "inside": { "badges": { "first": { "tier": 1, "at": "2026-01-01" }, "night": { "tier": 2 } },
                  "card": { "pro": true },
                  "ticket": { "photoId": "p-9", "note": "霧の朝", "origin": "", "destination": "海",
                              "face": 3, "showsFrom": true } } }
    """#

    // MARK: 読み方

    func testDecodesTheirTrunk() throws {
        let trunk = try decode(TheirTrunk.self, Self.full)
        XCTAssertEqual(trunk.userId, "u-1")
        XCTAssertEqual(trunk.model, .starchart)
        XCTAssertEqual(trunk.stuck.map(\.id), ["s2", "s1", "s0"], "返答の中の番号で並ぶ")
        XCTAssertEqual(trunk.posts, 42)
        XCTAssertEqual(trunk.places, ["s2": "京都"], "写真を引けるのは where のあるラベルだけ")
        XCTAssertEqual(trunk.stuck[1].pos, TrunkPos(x: 0.4, y: 0.5, rot: 6), "置き場は伏せた形でも残る")
        XCTAssertTrue(trunk.stuck[1].foil)
        XCTAssertEqual(trunk.equipped.handle, "handle.7")
        XCTAssertNil(trunk.equipped.lock, "台帳に無い部品は落とす")
        XCTAssertEqual(trunk.equipped.pins, ["pin.1"], "同じ部品の二重は落とす")
        XCTAssertEqual(trunk.badges.byKey.keys.sorted(), ["first", "night"])
        XCTAssertEqual(trunk.card, TheirTrunk.Card(pro: true))
        XCTAssertTrue(trunk.showsCard)
        XCTAssertEqual(trunk.ticket, TrunkTicket(photoId: "p-9", note: "霧の朝", origin: "", destination: "海", face: 3,
                                                  showsFrom: true))
    }

    /// 形の違う応答（stuck が無い）は投げる。項目の欠け・型違いは投げない
    func testShapeGuardsAndLenience() throws {
        XCTAssertThrowsError(try decode(TheirTrunk.self, #"{"model":"leather"}"#))
        let thin = try decode(TheirTrunk.self, #"{"stuck":[{"id":"s0"},{"id":"s1","kind":"place","seed":3,"place":{"name":""}}],"inside":{"card":null,"ticket":{"photoId":"a b"}}}"#)
        XCTAssertEqual(thin.model, .leather)
        XCTAssertEqual(thin.stuck.map(\.id), ["s1"], "種の無いラベルは描けないので落とす")
        XCTAssertNil(thin.card)
        XCTAssertFalse(thin.showsCard)
        XCTAssertNil(thin.ticket, "写真の id の形でない乗車券は読まない")
        XCTAssertNil(thin.posts)
        XCTAssertTrue(thin.badges.isEmpty)
    }

    /// 地名の空のラベルに where だけ来ても写真は引かない（地名なしの形に揃える）
    func testWhereWithoutPlaceNameIsIgnored() throws {
        let trunk = try decode(TheirTrunk.self, #"{"stuck":[{"id":"s0","kind":"place","seed":1,"place":{"name":""},"where":{"location":"京都"}}]}"#)
        XCTAssertTrue(trunk.places.isEmpty)
        XCTAssertNil(trunk.place(of: trunk.stuck[0]))
    }

    /// Pro でなくなった会員証は内ポケットに入れない（自分のトランクと同じ決まり）
    func testCardFollowsTheSameRuleAsMine() throws {
        let lapsed = try decode(TheirTrunk.self, #"{"stuck":[],"inside":{"card":{"pro":false}}}"#)
        XCTAssertNotNil(lapsed.card)
        XCTAssertFalse(lapsed.showsCard)
    }

    /// 自分の口（`GET /user/trunk`）の見せる設定とわたしの乗車券。古いサーバーは見せる・乗車券なし
    func testStateReadsShowTrunkAndTicket() throws {
        let on = try decode(TrunkState.self, #"{"pocket":[],"stuck":[]}"#)
        XCTAssertTrue(on.showTrunk)
        XCTAssertNil(on.ticket)
        let off = try decode(TrunkState.self, #"{"pocket":[],"stuck":[],"showTrunk":false,"ticket":{"photoId":"p1","note":"x"}}"#)
        XCTAssertFalse(off.showTrunk)
        XCTAssertEqual(off.ticket?.photoId, "p1")
        XCTAssertEqual(off.ticket?.showsFrom, true)
        // 書き込みの応答に引き継いでも消えない
        XCTAssertFalse(off.copy(coins: 3).showTrunk)
        XCTAssertEqual(off.keepingPosts(from: on).ticket?.photoId, "p1")
    }

    // MARK: 404 の扱い（理由は区別しない）

    func testNotFoundIsHiddenWithoutReason() async throws {
        StubProtocol.respond(status: 404, body: #"{"error":"見つかりません","code":"notFound"}"#)
        let result = try await service().theirs("u-1")
        XCTAssertNil(result)
        XCTAssertEqual(StubProtocol.requests, ["GET /users/u-1/trunk"])
        // 道の無い 404（本文なし・古いサーバー）も同じ
        StubProtocol.respond(status: 404, body: "")
        let old = try await service().theirs("u-1")
        XCTAssertNil(old)
    }

    func testReadsTheirTrunk() async throws {
        StubProtocol.respond(status: 200, body: Self.full)
        let trunk = try await service().theirs("u-1")
        XCTAssertEqual(trunk?.stuck.count, 3)
        XCTAssertEqual(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer t")
    }

    /// 人の id の形でない値は要求を出さずに nil（サーバーも 404 にする形）
    func testInvalidUserIdSendsNothing() async throws {
        let result = try await service().theirs("../user/trunk")
        XCTAssertNil(result)
        XCTAssertEqual(StubProtocol.requestCount, 0)
    }

    /// 500・圏外は投げる（「見せていない」と混ぜない）
    func testServerErrorIsNotHidden() async {
        StubProtocol.respond(status: 500, body: #"{"error":"x"}"#)
        do {
            _ = try await service().theirs("u-1")
            XCTFail("500 を見せない扱いにした")
        } catch {}
    }

    @MainActor
    func testModelPhases() async {
        let model = TheirTrunkModel(preview: false)
        StubProtocol.respond(status: 404, body: #"{"error":"x","code":"notFound"}"#)
        await model.load(userId: "u-1", service: service(), signedIn: true, offline: false)
        XCTAssertEqual(model.phase, .hidden)
        XCTAssertFalse(model.showsOnProfile(blocked: false), "404 は段ごと出さない")

        StubProtocol.respond(status: 200, body: Self.full)
        await model.load(userId: "u-1", service: service(), signedIn: true, offline: false)
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertTrue(model.showsOnProfile(blocked: false))
        XCTAssertFalse(model.showsOnProfile(blocked: true), "ブロックの関係でも段を出す")

        // 読み直しの失敗では、読めた中身を消さない
        StubProtocol.respond(status: 500, body: #"{"error":"x"}"#)
        await model.load(userId: "u-1", service: service(), signedIn: true, offline: false)
        XCTAssertTrue(model.showsOnProfile(blocked: false))

        // 人が替わったら前の人の中身を出さない。初回の失敗は「失敗」
        await model.load(userId: "u-2", service: service(), signedIn: true, offline: false)
        XCTAssertNil(model.trunk)
        if case .failed = model.phase {} else { XCTFail("失敗の形になっていない: \(model.phase)") }

        // ログインしていなければ読まない
        let before = StubProtocol.requestCount
        await model.load(userId: "u-3", service: service(), signedIn: false, offline: false)
        XCTAssertEqual(model.phase, .hidden)
        XCTAssertEqual(StubProtocol.requestCount, before)
    }

    @MainActor
    func testPreviewSendsNothing() async {
        let model = TheirTrunkModel(preview: true)
        await model.load(userId: "u-1", service: service(), signedIn: true, offline: false)
        XCTAssertEqual(StubProtocol.requestCount, 0, "見本はサーバーに何も送らない")
        let sealed = model.trunk?.stuck.filter(TrunkLabelDesign.isSealed) ?? []
        XCTAssertEqual(sealed.count, 2, "見本に地名の無いラベルが無い")
        XCTAssertTrue(sealed.allSatisfy { model.trunk?.place(of: $0) == nil })
        XCTAssertNil(PreviewSession.theirTrunkSample ? "効いている" : nil, "テストで見本が効いている")
    }

    // MARK: 地名の無いラベルの描き方

    private func sealed(_ kind: TrunkLabel.Kind, seed: Int = 77031) -> TrunkLabel {
        TrunkLabel(id: "s1", photoId: "s1", kind: kind, place: .init(name: "", latin: nil, country: nil), seed: seed, at: "")
    }

    /// 季節・時刻・節目・土地のどれでも、値が無くても専用の図案で描ける（土地の色に落ちない・空にならない）
    func testSealedLabelsHaveTheirOwnDesign() {
        let expected: [TrunkLabel.Kind: TrunkLabelArt] = [.place: .postmark, .season: .branch, .timeslot: .dial,
                                                          .milestone: .rosette]
        for (kind, art) in expected {
            for seed in [1, 2, 77031, 999_999] {
                let label = sealed(kind, seed: seed)
                XCTAssertTrue(TrunkLabelDesign.isSealed(label))
                XCTAssertEqual(TrunkLabelDesign.theme(label).palette, "journey", "\(kind)")
                let spec = TrunkLabelDesign.spec(for: label)
                XCTAssertEqual(spec.art, art, "\(kind) の図案")
                let palette = TrunkLabelDesign.palettes["journey"]!
                XCTAssertTrue(palette.contains { TrunkRGBA($0.bg) == spec.bg }, "\(kind) の色が専用の組でない")
                // 刷りの字はあるが、値（季節・時刻・節目・地名）を言わない
                for text in [spec.t1, spec.t2, spec.t3] { XCTAssertFalse(text.isEmpty, "\(kind) に空の行") }
                for word in ["SPRING", "SUMMER", "AUTUMN", "WINTER", "DAWN", "SUNSET", "NIGHT", "FIRST", "TEN", "NEW COUNTRY"] {
                    XCTAssertFalse([spec.t1, spec.t2, spec.t3].contains(word), "\(kind) が値 \(word) を刷っている")
                }
                XCTAssertFalse(TrunkArtwork.strokes(art).isEmpty)
                // 描く寸法も崩れない
                let layout = TrunkLabelLayout(w: 100, h: 66, spec: spec)
                XCTAssertGreaterThan(layout.t2Size, 3)
                XCTAssertGreaterThan(layout.artHeight, 10)
            }
        }
        XCTAssertEqual(TrunkLabelDesign.caption(sealed(.timeslot)), L("旅の記録", "Travel log"))
        // 箔押しは箔の色のまま
        let foil = TrunkLabel(id: "s1", photoId: "s1", kind: .season, place: .init(name: "", latin: nil, country: nil),
                              seed: 5, at: "", foil: true)
        XCTAssertTrue(TrunkLabelDesign.spec(for: foil).foil)
    }

    /// 値のあるラベル・地名のあるラベルは今までどおり（本人の画面の絵を変えない）
    func testOrdinaryLabelsAreUnchanged() {
        let kyoto = TrunkLabel(id: "a", photoId: "a", kind: .season, place: .init(name: "京都", latin: "Kyoto", country: "日本"),
                               season: .spring, seed: 41_207, at: "2026-04-03T09:00:00Z")
        XCTAssertFalse(TrunkLabelDesign.isSealed(kyoto))
        XCTAssertEqual(TrunkLabelDesign.theme(kyoto).palette, "spring")
        let ten = TrunkLabel(id: "b", photoId: "b", kind: .milestone, place: .init(name: "", latin: nil, country: nil),
                             milestone: .posts10, seed: 10_010, at: "2025-05-05T10:00:00Z")
        XCTAssertFalse(TrunkLabelDesign.isSealed(ten), "地名の無い節目でも値があれば節目の絵")
        XCTAssertEqual(TrunkLabelDesign.theme(ten).art, "count")
        // 地名だけ伏せて季節が残る形はサーバーは返さないが、来ても季節の絵
        let springOnly = TrunkLabel(id: "c", photoId: "c", kind: .season, place: .init(name: "", latin: nil, country: nil),
                                    season: .spring, seed: 3, at: "")
        XCTAssertEqual(TrunkLabelDesign.theme(springOnly).palette, "spring")
    }

    /// シートの言葉: 地名の無いラベルに「非公開」の類を出さない・写真の数は読めてから
    func testSheetWordingNeverRevealsWhy() {
        let subtitle = TheirTrunkText.sheetSubtitle(place: nil, owner: "丸田", count: nil)
        for word in ["非公開", "伏せ", "隠", "見せていない", "private", "hidden"] {
            XCTAssertFalse(subtitle.contains(word))
            XCTAssertFalse(TheirTrunkText.labelAccessibility(sealed(.place), place: nil).contains(word))
            XCTAssertFalse(TheirTrunkText.hiddenTitle.contains(word))
        }
        XCTAssertEqual(TheirTrunkText.sheetSubtitle(place: "京都", owner: "丸田", count: 3),
                       L("丸田さんが京都で撮った写真 · 3 枚", "Photos 丸田 took in 京都 · 3"))
        XCTAssertFalse(TheirTrunkText.sheetSubtitle(place: "京都", owner: "丸田", count: nil).contains("0"),
                       "読み込み中に 0 枚と言う")
        XCTAssertEqual(TheirTrunkText.owner("  "), L("この人", "This person"))
    }

    // MARK: 写真の引き方

    private func photos(_ locations: [String?]) throws -> [Photo] {
        let rows = locations.enumerated().map { i, loc in
            loc.map { #"{"id":"p\#(i)","src":"https://x/\#(i).jpg","location":"\#($0)"}"# } ?? #"{"id":"p\#(i)","src":"https://x/\#(i).jpg"}"#
        }
        return try decode([Photo].self, "[" + rows.joined(separator: ",") + "]")
    }

    func testPhotosMatchTheFirstSegmentThenContains() throws {
        let list = try photos(["京都, 日本", "清水寺（京都）", "京都府立植物園", "大阪", nil, "京都/嵐山"])
        XCTAssertEqual(TheirTrunkText.photos(at: "京都", in: list).map(\.id), ["p0", "p5"], "先頭の区切りが同じもの")
        XCTAssertEqual(TheirTrunkText.photos(at: "清水寺", in: list).map(\.id), ["p1"])
        // 先頭で当たらなければ、撮影地に含むもの
        XCTAssertEqual(TheirTrunkText.photos(at: "植物園", in: list).map(\.id), ["p2"])
        XCTAssertTrue(TheirTrunkText.photos(at: "札幌", in: list).isEmpty)
        XCTAssertTrue(TheirTrunkText.photos(at: " ", in: list).isEmpty)
        XCTAssertEqual(TheirTrunkText.head(" パリ ， フランス"), "パリ")
    }

    func testDefaultSelectionPrefersALabelWithPhotos() throws {
        let trunk = try decode(TheirTrunk.self, #"{"stuck":[{"id":"s1","kind":"place","seed":1,"place":{"name":""}},{"id":"s0","kind":"place","seed":2,"place":{"name":"パリ"},"where":{"location":"パリ"}}]}"#)
        XCTAssertEqual(TheirTrunkText.defaultSelection(trunk, drawn: trunk.stuck), "s0")
        let none = try decode(TheirTrunk.self, #"{"stuck":[]}"#)
        XCTAssertNil(TheirTrunkText.defaultSelection(none, drawn: []))
    }

    /// 押せる所は縮めて置いても 44pt を割らない（板の max(44, w*0.8)）
    func testHitTargetsStay44AfterScaling() {
        let p = TrunkSlots.Placed(label: sealed(.place), x: 100, y: 50, w: 40, h: 30, rot: 8, age: 0)
        for k in [1.0, 0.86, 0.6] {
            let f = TheirTrunkText.hitFrame(p, scale: k)
            XCTAssertGreaterThanOrEqual(f.w * k, 44 - 0.001)
            XCTAssertGreaterThanOrEqual(f.h * k, 44 - 0.001)
            XCTAssertEqual(f.x + f.w / 2, 120, accuracy: 0.001, "真ん中がラベルとずれる")
            XCTAssertEqual(f.y + f.h / 2, 50 + TrunkLooks.bodyTop + 15, accuracy: 0.001)
        }
        let ring = TheirTrunkText.ringFrame(p)
        XCTAssertEqual(ring, TheirTrunkText.Frame(x: 95, y: 50 + TrunkLooks.bodyTop - 5, w: 50, h: 40, rot: 8))
    }

    // MARK: 中身（人の版）

    func testTheirInsideContents() throws {
        let trunk = try decode(TheirTrunk.self, Self.full)
        let contents = TrunkInsideContents(theirs: trunk, name: "丸田")
        XCTAssertTrue(contents.isTheirs)
        XCTAssertEqual(contents.ticketCount, 1, "乗車券はわたしの乗車券1枚だけ")
        XCTAssertEqual(contents.ticketTab, L("わたしの乗車券", "Their ticket"))
        XCTAssertEqual(contents.ticketTabWidth, 112)
        XCTAssertEqual(contents.ticketPoses.count, 1)
        XCTAssertTrue(contents.showsCard)
        XCTAssertEqual(contents.medals.count, 2)
        XCTAssertFalse(contents.ticketLabel.contains("すれちがい"))
        XCTAssertEqual(contents.actionTitle(.card), L("サポーター証を回して見る", "Turn the card"))
        // 自分の版は今までどおり
        let mine = TrunkInsideContents(medals: [], showsCard: false, ticketCount: 12)
        XCTAssertEqual(mine.ticketTab, L("乗車券 12", "Tickets 12"))
        XCTAssertEqual(mine.ticketTabWidth, 92)
        XCTAssertEqual(mine.ticketPoses.count, 3)
        XCTAssertEqual(mine.actionTitle(.tickets), L("すれちがい帳を開く", "Open the pass book"))
    }

    /// 会員証は番号を刷らない: 表の絵・回す画面の番号の行・読み上げが同じ `numberLine` を通る
    /// （見直し 1: 回す画面 `SupporterCardViewer` が showsNumber を見ずに「No. 0000」を出していた）
    func testTheirCardHasNoNumber() throws {
        let face = SupporterCardFace(name: "丸田", handle: "maruta", number: 0, since: nil, showsNumber: false)
        XCTAssertNil(face.numberLine, "番号の行を出す")
        XCTAssertFalse(face.accessibilityLabel.contains("No."))
        let theirs = TheirTrunkInside(userId: "u-1", name: "丸田", handle: "maruta", homeLocation: nil,
                                      trunk: try decode(TheirTrunk.self, Self.full), profile: nil, photos: [])
        XCTAssertNil(theirs.cardFace.numberLine, "人の会員証に番号が出る")
        XCTAssertNil(theirs.cardFace.since)
        let mine = SupporterCardFace(name: "丸田", handle: nil, number: 7, since: nil)
        XCTAssertEqual(mine.numberLine, SupporterText.numberLabel(7))
        XCTAssertTrue(mine.accessibilityLabel.contains(SupporterText.numberLabel(7)))
        // 回す画面と表の絵は番号を `numberLine` からしか取らない（ほかに番号を書く道が無い）
        for path in ["Features/Pro/SupporterCardView.swift", "Features/Pro/SupporterCardTextures.swift"] {
            let text = try source(path)
            let viewer = path.hasSuffix("View.swift") ? text.components(separatedBy: "struct SupporterCardViewer")[1] : text
            XCTAssertFalse(viewer.contains("numberLabel(face.number)"), "\(path) が showsNumber を見ずに番号を書く")
        }
    }

    // MARK: 見せる設定・乗車券の送り方

    private func json(_ data: Data?) -> [String: Any]? {
        data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    func testShowTrunkSendsOnlyThatKey() async throws {
        StubProtocol.respond(status: 200, body: #"{"pocket":[],"stuck":[],"showTrunk":false}"#)
        let state = try await service().setShowTrunk(false)
        XCTAssertFalse(state.showTrunk)
        XCTAssertEqual(StubProtocol.requests, ["PUT /user/trunk/settings"])
        let body = try XCTUnwrap(json(StubProtocol.lastBody))
        XCTAssertEqual(Array(body.keys), ["showTrunk"], "ほかの設定を一緒に送っている")
        XCTAssertEqual(body["showTrunk"] as? Bool, false)
    }

    func testTicketBodyAndRemoval() async throws {
        StubProtocol.respond(status: 200, body: #"{"pocket":[],"stuck":[]}"#)
        _ = try await service().setTicket(TrunkTicket(photoId: "p-1", note: "霧", origin: "東京", destination: "", face: 3,
                                                      showsFrom: false))
        let body = try XCTUnwrap(json(StubProtocol.lastBody)?["ticket"] as? [String: Any])
        XCTAssertEqual(body["photoId"] as? String, "p-1")
        XCTAssertEqual(body["note"] as? String, "霧")
        XCTAssertEqual(body["origin"] as? String, "東京")
        XCTAssertEqual(body["destination"] as? String, "")
        XCTAssertEqual(body["face"] as? Int, 3)
        XCTAssertEqual(body["showsFrom"] as? Bool, false)
        _ = try await service().setTicket(nil)
        let removal = try XCTUnwrap(json(StubProtocol.lastBody))
        XCTAssertTrue(removal.keys.contains("ticket"), "外すときに項目を落とすと「変えない」になる")
        XCTAssertTrue(removal["ticket"] is NSNull)
    }

    /// 断り（409 ticketNotPublic）は Refused の印で返る
    func testTicketRefusal() async {
        StubProtocol.respond(status: 409, body: #"{"error":"公開している自分の写真を選んでください","code":"ticketNotPublic"}"#)
        do {
            _ = try await service().setTicket(TrunkTicket(photoId: "p-1"))
            XCTFail("断りを成功にした")
        } catch let refused as TrunkService.Refused {
            XCTAssertEqual(refused.code, "ticketNotPublic")
        } catch {
            XCTFail("\(error)")
        }
    }

    /// 端末の「わたしの乗車券」から作る1枚: 選んでいなければ無し・連絡先は載せない・サーバーの上限に収める
    func testMineFromPassSettings() {
        var settings = PassSettings()
        XCTAssertNil(TrunkTicket.mine(settings))
        settings.cardPhotoId = "p-1"
        settings.note = "連絡は https://example.com まで"
        settings.faceStyle = 4
        settings.setOrigin(.custom, text: "ふるさと")
        settings.setDestination(custom: true, text: "海")
        let ticket = TrunkTicket.mine(settings)
        XCTAssertEqual(ticket?.photoId, "p-1")
        XCTAssertEqual(ticket?.note, "", "連絡先の形を載せた")
        XCTAssertEqual(ticket?.origin, "ふるさと")
        XCTAssertEqual(ticket?.destination, "海")
        XCTAssertEqual(ticket?.face, 4)
        XCTAssertEqual(ticket?.showsFrom, false)
        XCTAssertEqual(ticket?.originChoice, .custom)
        // 家族の絵文字は1字でもコードポイントが多い。サーバーの数え方（コードポイント）で収める
        let family = "👨‍👩‍👧‍👦"
        let fitted = TrunkTicket.fit(String(repeating: family, count: 5), chars: TrunkTicket.noteChars, bytes: TrunkTicket.noteBytes)
        XCTAssertLessThanOrEqual(fitted.unicodeScalars.count, TrunkTicket.noteChars)
        XCTAssertLessThanOrEqual(fitted.utf8.count, TrunkTicket.noteBytes)
        XCTAssertEqual(fitted, String(repeating: family, count: 2), "字の途中で切った")
        settings.cardPhotoId = "bad id"
        XCTAssertNil(TrunkTicket.mine(settings))
    }

    // MARK: 見直し（2026-10-18）

    /// 見直し 2: 発・着・ひとことの3つとも、連絡先の形は送らない（電波の中身と同じ判定を共有）
    func testContactsNeverLeaveInTicket() {
        let contact = "www.ab"
        XCTAssertTrue(PassExchange.containsContact(contact), "前提: 連絡先の形")
        var settings = PassSettings()
        settings.cardPhotoId = "p-1"
        settings.originLabel = contact
        settings.destinationLabel = contact
        settings.note = "連絡は www.example.jp"
        let ticket = TrunkTicket.mine(settings)
        XCTAssertEqual(ticket?.origin, "", "発に連絡先を載せた")
        XCTAssertEqual(ticket?.destination, "", "着に連絡先を載せた")
        XCTAssertEqual(ticket?.note, "")
        XCTAssertEqual(ticket?.originChoice, .home, "発が落ちたら居住地に戻す")
        // 電波の中身も同じ判定（同じ関数を通る）
        XCTAssertEqual(PassExchange.shareable(contact), "")
        XCTAssertEqual(PassExchange.shareable("海"), "海")
    }

    /// 見直し 2: サーバーから来た字でも、連絡先の形は券に刷らない
    func testTheirTicketRouteDropsContacts() {
        let route = TheirTrunkText.ticketRoute(TrunkTicket(photoId: "p-1", note: "www.example.jp まで", origin: "www.ab",
                                                           destination: "www.cd", face: 0, showsFrom: false))
        XCTAssertEqual(route, TheirTrunkText.TicketRoute(choice: .hidden, origin: "", destination: "", note: ""))
        let plain = TheirTrunkText.ticketRoute(TrunkTicket(photoId: "p-1", note: "霧", origin: "東京", destination: "海"))
        XCTAssertEqual(plain, TheirTrunkText.TicketRoute(choice: .custom, origin: "東京", destination: "海", note: "霧"))
    }

    /// 見直し 3: トランクに入れるのは、本人がオンにし（既定はオフ）、すれちがいがオンで、乗車券を選んであるときだけ
    func testTicketIsOptIn() throws {
        var settings = PassSettings()
        settings.cardPhotoId = "p-1"
        settings.enabled = true
        XCTAssertNil(settings.ticketInTrunk, "既定はオフ")
        XCTAssertNil(TrunkTicket.wanted(settings), "選んでいないのに送る")
        settings.ticketInTrunk = true
        XCTAssertEqual(TrunkTicket.wanted(settings)?.photoId, "p-1")
        settings.enabled = false
        XCTAssertNil(TrunkTicket.wanted(settings), "すれちがいがオフでも送る")
        settings.enabled = true
        settings.cardPhotoId = nil
        XCTAssertNil(TrunkTicket.wanted(settings))
        // 前の版の設定（項目が無い）も読める・オフのまま
        let old = try JSONDecoder().decode(PassSettings.self, from: Data(#"{"enabled":true,"mode":"traveling","cardPhotoId":"p-1","note":"","showsFrom":true}"#.utf8))
        XCTAssertNil(TrunkTicket.wanted(old))
        XCTAssertTrue(TrunkPrivacyText.seenNote.contains(L("わたしの乗車券もトランクに入れる", "Put my ticket in the trunk too")),
                      "見本の説明に、乗車券は切り替えをオンにしたときだけと書いていない")
    }

    func testSyncActionTable() {
        let a = TrunkTicket(photoId: "a"), b = TrunkTicket(photoId: "b")
        XCTAssertEqual(TrunkTicketSyncRule.action(wanted: a, server: a, refused: nil), .none)
        XCTAssertEqual(TrunkTicketSyncRule.action(wanted: nil, server: nil, refused: nil), .none)
        XCTAssertEqual(TrunkTicketSyncRule.action(wanted: nil, server: a, refused: nil), .remove, "外れたのにサーバーに残す")
        XCTAssertEqual(TrunkTicketSyncRule.action(wanted: a, server: nil, refused: nil), .put(a))
        XCTAssertEqual(TrunkTicketSyncRule.action(wanted: a, server: b, refused: a), .none, "断られた中身を送り直す")
        XCTAssertEqual(TrunkTicketSyncRule.action(wanted: b, server: nil, refused: a), .put(b))
    }

    private func optedIn() -> PassSettings {
        var settings = PassSettings()
        settings.cardPhotoId = "p-1"
        settings.enabled = true
        settings.ticketInTrunk = true
        return settings
    }

    /// 見直し 3・6: 断られたら一言を返し、同じ中身では二度と送らない。外れたら null で外す
    @MainActor
    func testSyncRemembersRefusalAndRemoves() async {
        let defaults = UserDefaults(suiteName: "TheirTrunkTests.\(UUID().uuidString)")!
        let sync = TrunkTicketSync(defaults: defaults)
        StubProtocol.respond(status: 409, body: #"{"error":"公開している自分の写真を選んでください","code":"ticketNotPublic"}"#)
        let first = await sync.sync(userId: "me", settings: optedIn(), service: service(), available: true, preview: false)
        XCTAssertNotNil(first, "断りを本人に知らせない")
        XCTAssertEqual(StubProtocol.requestCount, 1)
        let again = await sync.sync(userId: "me", settings: optedIn(), service: service(), available: true, preview: false)
        XCTAssertNil(again)
        XCTAssertEqual(StubProtocol.requestCount, 1, "断られた中身で毎回送り直す")

        // 置けた1枚を覚え、切り替えを外したら null で外す
        StubProtocol.respond(status: 200, body: #"{"pocket":[],"stuck":[],"ticket":{"photoId":"p-2"}}"#)
        var other = optedIn()
        other.cardPhotoId = "p-2"
        _ = await sync.sync(userId: "me", settings: other, service: service(), available: true, preview: false)
        XCTAssertEqual(sync.known("me")?.photoId, "p-2")
        XCTAssertNil(sync.refused("me"), "置けたのに断りを覚えたまま")
        StubProtocol.respond(status: 200, body: #"{"pocket":[],"stuck":[]}"#)
        other.ticketInTrunk = nil
        _ = await sync.sync(userId: "me", settings: other, service: service(), available: true, preview: false)
        XCTAssertTrue(json(StubProtocol.lastBody)?["ticket"] is NSNull, "外したのにサーバーに残す")
        XCTAssertNil(sync.known("me"))
        // 揃っていれば送らない・口が無い人・見本は何もしない
        let count = StubProtocol.requestCount
        _ = await sync.sync(userId: "me", settings: other, service: service(), available: true, preview: false)
        _ = await sync.sync(userId: "me", settings: optedIn(), service: service(), available: false, preview: false)
        _ = await sync.sync(userId: "me", settings: optedIn(), service: service(), available: true, preview: true)
        XCTAssertEqual(StubProtocol.requestCount, count)
        TrunkTicketSyncRule.removeData(for: "me", defaults: defaults)
        XCTAssertNil(sync.known("me"))
    }

    /// 見直し 5: 入っている人が替わったら前の人の設定・数を消す
    @MainActor
    func testPrivacyModelResetsOnAccountChange() async {
        let model = TrunkPrivacyModel(preview: .sample)
        await model.load(userId: "a", service: service(), pass: PassSettings())
        XCTAssertNotNil(model.state)
        model.reset(for: "b")
        XCTAssertNil(model.state, "前の人の設定が残る")
        XCTAssertNil(model.followers)
        model.reset(for: nil)
        XCTAssertNil(model.state)
    }

    private func suite() -> UserDefaults { UserDefaults(suiteName: "TheirTrunkTests.\(UUID().uuidString)")! }

    private static let notPublic = #"{"error":"公開している自分の写真を選んでください","code":"ticketNotPublic"}"#

    /// 2回目の見直し A: 断りの訳は人ごとに覚え、起動し直しても（別の入れ物でも）設定に出す。説明も「入っていません」
    @MainActor
    func testRefusalReasonSurvivesRelaunch() async {
        let defaults = suite()
        StubProtocol.respond(status: 409, body: Self.notPublic)
        _ = await TrunkTicketSync(defaults: defaults).sync(userId: "me", settings: optedIn(), service: service(),
                                                           available: true, preview: false)
        let relaunched = TrunkTicketSync(defaults: defaults)
        let reason = relaunched.refusalReason("me", settings: optedIn())
        XCTAssertNotNil(reason, "起動し直すと断りの訳が消える")
        let detail = TrunkPrivacyText.ticketDetail(optedIn(), refusal: reason)
        XCTAssertTrue(detail.contains(L("いまは入っていません", "It isn\u{2019}t in the trunk now")), "断られたのに「入ります」のまま")
        XCTAssertTrue(detail.contains(reason ?? "-"))
        XCTAssertNil(relaunched.refusalReason("other", settings: optedIn()), "人ごとに分けていない")
        var changed = optedIn()
        changed.cardPhotoId = "p-2"
        XCTAssertNil(relaunched.refusalReason("me", settings: changed), "中身を変えたのに前の断りを出す")
    }

    /// 2回目の見直し A: 写真が公開でない、の断りのあと、設定を開いたら1回だけ送り直す。入れ直し・中身の変更でも送る。
    /// 形が違う（badTicket）は同じ中身なら送り直さない
    @MainActor
    func testNotPublicIsRetriedOnOpenAndOnChange() async {
        let defaults = suite()
        let model = TrunkPrivacyModel(preview: nil, sync: TrunkTicketSync(defaults: defaults), defaults: defaults)
        StubProtocol.respond(path: "/user/trunk/settings", status: 409, body: Self.notPublic)
        StubProtocol.respond(path: "/user/trunk", status: 200, body: #"{"pocket":[],"stuck":[]}"#)
        let puts = { StubProtocol.requests.filter { $0.hasPrefix("PUT") }.count }
        await model.load(userId: "me", service: service(), pass: optedIn())
        XCTAssertEqual(puts(), 1)
        await model.load(userId: "me", service: service(), pass: optedIn())
        XCTAssertEqual(puts(), 2, "写真を公開にしても二度と送らない")
        // 設定の変化の後ろ（開いたとき以外）では、同じ中身を送り直さない
        let sync = TrunkTicketSync(defaults: defaults)
        _ = await sync.sync(userId: "me", settings: optedIn(), service: service(), available: true, preview: false)
        XCTAssertEqual(puts(), 2, "設定が変わるたびに同じ中身を送る")
        // 切り替えを外して入れ直すと送る
        var off = optedIn()
        off.ticketInTrunk = nil
        _ = await sync.sync(userId: "me", settings: off, service: service(), available: true, preview: false)
        XCTAssertNil(sync.refusal("me"), "外しても断りを覚えたまま")
        _ = await sync.sync(userId: "me", settings: optedIn(), service: service(), available: true, preview: false)
        XCTAssertEqual(puts(), 3, "入れ直しても送らない")
        // badTicket は開いても送り直さない
        StubProtocol.reset()
        StubProtocol.respond(status: 400, body: #"{"error":"乗車券が正しくありません","code":"badTicket"}"#)
        var bad = optedIn()
        bad.cardPhotoId = "p-3"
        _ = await sync.sync(userId: "me", settings: bad, service: service(), available: true, preview: false)
        _ = await sync.sync(userId: "me", settings: bad, service: service(), available: true, preview: false,
                            retryRefused: true)
        XCTAssertEqual(StubProtocol.requestCount, 1, "形の違う中身を送り直す")
    }

    /// 2回目の見直し B: 一時的な断り（429 など）・5xx・圏外は覚えず、次の機会に送り直す
    @MainActor
    func testTransientFailuresAreNotRemembered() async {
        let sync = TrunkTicketSync(defaults: suite())
        for (status, body) in [(429, #"{"error":"少し待ってください","code":"tooMany"}"#), (429, #"{"error":"x"}"#),
                               (500, #"{"error":"x"}"#)] {
            StubProtocol.respond(status: status, body: body)
            let reason = await sync.sync(userId: "me", settings: optedIn(), service: service(), available: true, preview: false)
            XCTAssertNil(reason, "一時の断りを中身の断りとして知らせる（\(status)）")
            XCTAssertNil(sync.refusal("me"), "一時の断りを覚えた（\(status)）")
        }
        XCTAssertEqual(StubProtocol.requestCount, 3, "一時の断りのあと送り直さない")
        XCTAssertTrue(TrunkTicketSyncRule.isContentRefusal("ticketNotPublic"))
        XCTAssertTrue(TrunkTicketSyncRule.isContentRefusal("badTicket"))
        XCTAssertFalse(TrunkTicketSyncRule.isContentRefusal("tooMany"))
        XCTAssertFalse(TrunkTicketSyncRule.isContentRefusal(nil))
    }

    /// 2回目の見直し 1: 送っている途中にオフにしても、終わってから最後の望みで揃え直す（サーバーに残さない）
    @MainActor
    func testTurningOffWhileSendingConverges() async {
        let gate = Gate(holds: 1)
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: StubTokenProvider(token: "t"),
                            session: session, beforeRequest: { _ in await gate.wait() })
        let slow = TrunkService(api: api)
        StubProtocol.respondInOrder([(200, #"{"pocket":[],"stuck":[],"ticket":{"photoId":"p-1"}}"#),
                                     (200, #"{"pocket":[],"stuck":[]}"#)])
        let sync = TrunkTicketSync(defaults: suite())
        let first = Task { await sync.sync(userId: "me", settings: optedIn(), service: slow, available: true, preview: false) }
        await gate.untilWaiting(1)
        XCTAssertTrue(sync.isSending)
        var off = optedIn()
        off.ticketInTrunk = nil
        _ = await sync.sync(userId: "me", settings: off, service: slow, available: true, preview: false)
        await gate.open()
        _ = await first.value
        XCTAssertEqual(StubProtocol.requests, ["PUT /user/trunk/settings", "PUT /user/trunk/settings"], "外す送りが無い")
        XCTAssertTrue(json(StubProtocol.lastBody)?["ticket"] is NSNull, "最後の望み（外す）に揃っていない")
        XCTAssertNil(sync.known("me"))
        XCTAssertFalse(sync.isSending)
    }

    /// 2回目の見直し 2: 揃えるのは `PassStore.update` の後ろ。人ごと・ログインしていないときは呼ばない
    @MainActor
    func testPassStoreCallsTheSyncAfterUpdate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("their-trunk-\(UUID().uuidString)")
        let store = PassStore(root: root, defaults: suite(), schedule: { _, _, _ in })
        var calls: [(String, Bool?)] = []
        store.onSettingsChanged = { userId, settings in calls.append((userId, settings.ticketInTrunk)) }
        store.update { $0.ticketInTrunk = true }
        XCTAssertTrue(calls.isEmpty, "ログインしていないのに揃える")
        store.use(userId: "me")
        store.update { $0.ticketInTrunk = true }
        XCTAssertEqual(calls.map(\.0), ["me"])
        XCTAssertEqual(calls.last?.1, true)
        store.update { $0.ticketInTrunk = true }
        XCTAssertEqual(calls.count, 1, "変わっていないのに揃える")
        let app = try source("App/JourneyPhotoApp.swift")
        XCTAssertTrue(app.contains("PassStore.shared.onSettingsChanged = { userId, settings in"), "起動で揃えを付けていない")
    }

    /// 2回目の見直し 3: 自分のページは端末の控えの見せる設定を使い、控えが無いときだけ `GET /user/trunk` を読む
    @MainActor
    func testOwnProfileUsesTheCachedSetting() async {
        let defaults = suite()
        StubProtocol.respond(path: "/users/me/trunk", status: 200, body: Self.full)
        StubProtocol.respond(path: "/user/trunk", status: 200, body: #"{"pocket":[],"stuck":[],"showTrunk":false}"#)
        let model = TheirTrunkModel(preview: false, defaults: defaults)
        await model.load(userId: "me", service: service(), signedIn: true, offline: false, isSelf: true)
        XCTAssertEqual(model.phase, .hidden)
        XCTAssertEqual(StubProtocol.requests, ["GET /user/trunk"], "控えが無いのに読まない／見せない設定なのに人の口を読む")
        XCTAssertEqual(TrunkOwnSettings.showTrunk(userId: "me", defaults: defaults), false)
        // 控えがあれば読み足さない
        TrunkOwnSettings.note(showTrunk: true, userId: "me", defaults: defaults)
        StubProtocol.reset()
        StubProtocol.respond(path: "/users/me/trunk", status: 200, body: Self.full)
        await model.load(userId: "me", service: service(), signedIn: true, offline: false, isSelf: true)
        XCTAssertTrue(model.showsOnProfile(blocked: false))
        XCTAssertEqual(StubProtocol.requests, ["GET /users/me/trunk"], "自分の設定を1本多く読む")
        TrunkTicketSyncRule.removeData(for: "me", defaults: defaults)
        XCTAssertNil(TrunkOwnSettings.showTrunk(userId: "me", defaults: defaults), "退会で控えが残る")
    }

    /// 2回目の見直し 4: 設定の見本は人と同じ口の中身を描く（読めないときだけ地名なしの形）
    @MainActor
    func testSeenPreviewUsesTheirShape() async throws {
        let defaults = suite()
        StubProtocol.respond(path: "/users/me/trunk", status: 200, body: Self.full)
        StubProtocol.respond(path: "/user/trunk", status: 200, body: #"{"pocket":[],"stuck":[]}"#)
        let model = TrunkPrivacyModel(preview: nil, sync: TrunkTicketSync(defaults: defaults), defaults: defaults)
        await model.load(userId: "me", service: service(), pass: PassSettings())
        let seen = try XCTUnwrap(model.seen, "人と同じ口を読んでいない")
        let state = try XCTUnwrap(model.state)
        let figure = TheirTrunkText.seenFigure(seen: seen, own: state)
        XCTAssertEqual(figure.stuck, seen.stuck, "本当の見え方と違う絵")
        XCTAssertEqual(figure.model, .starchart)
        XCTAssertEqual(figure.stuck.first?.place.name, "京都", "地名つきで見えるラベルまで地名を落とす")
        let fallback = TheirTrunkText.seenFigure(seen: nil, own: TrunkSample.state(isPro: false))
        XCTAssertTrue(fallback.stuck.allSatisfy(TrunkLabelDesign.isSealed), "読めないときに地名を出す")
    }

    /// 見直し 9: 「ログインしていない」「見本」の枝でも回を進める（前に始まった回が後の答えを上書きしない）
    @MainActor
    func testLaterHiddenWinsOverEarlierLoad() async {
        let gate = Gate(holds: 1)
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: StubTokenProvider(token: "t"),
                            session: session, beforeRequest: { _ in await gate.wait() })
        let slow = TrunkService(api: api)
        StubProtocol.respond(status: 200, body: Self.full)
        let model = TheirTrunkModel(preview: false)
        let first = Task { await model.load(userId: "u-1", service: slow, signedIn: true, offline: false) }
        await gate.untilWaiting(1)
        await model.load(userId: "u-1", service: slow, signedIn: false, offline: false)
        await gate.open()
        await first.value
        XCTAssertEqual(model.phase, .hidden, "ログアウトのあとに前の回の中身が出る")
        XCTAssertNil(model.trunk)
    }

    /// 見直し 10: 自分のページを人の画面で開いたとき、見せる設定がオフなら段を出さない
    @MainActor
    func testOwnProfileFollowsShowTrunk() async {
        StubProtocol.respond(path: "/users/me/trunk", status: 200, body: Self.full)
        StubProtocol.respond(path: "/user/trunk", status: 200, body: #"{"pocket":[],"stuck":[],"showTrunk":false}"#)
        let defaults = suite()
        let model = TheirTrunkModel(preview: false, defaults: defaults)
        await model.load(userId: "me", service: service(), signedIn: true, offline: false, isSelf: true)
        XCTAssertEqual(model.phase, .hidden)
        XCTAssertFalse(model.showsOnProfile(blocked: false), "人に出ていない段を自分のページに出す")
        XCTAssertFalse(StubProtocol.requests.contains("GET /users/me/trunk"), "見せない設定なのに人の口を読む")
        StubProtocol.reset()
        StubProtocol.respond(path: "/users/me/trunk", status: 200, body: Self.full)
        // 設定で見せるに替えた（控えが替わった）
        TrunkOwnSettings.note(showTrunk: true, userId: "me", defaults: defaults)
        await model.load(userId: "me", service: service(), signedIn: true, offline: false, isSelf: true)
        XCTAssertTrue(model.showsOnProfile(blocked: false))
    }

    /// 見直し 8: 見本の札はほかの人から見た形（地名・日付・季節・時刻・節目を落とし、絵の種と置き場は残す）
    func testPreviewIsAsSeenByOthers() {
        let seen = TheirTrunkText.asSeenByOthers(TrunkSample.stuck)
        XCTAssertEqual(seen.map(\.id), TrunkSample.stuck.map(\.id))
        XCTAssertEqual(seen.map(\.seed), TrunkSample.stuck.map(\.seed))
        XCTAssertTrue(seen.allSatisfy { $0.place.name.isEmpty && $0.season == nil && $0.timeslot == nil && $0.milestone == nil })
        XCTAssertTrue(seen.allSatisfy(TrunkLabelDesign.isSealed), "人から見た形と違う絵になる")
        XCTAssertTrue(TrunkPrivacyText.seenNote.contains(L("地名は、公開の写真と同じ撮影地のときだけ出ます", "Place names appear only")))
    }

    /// 見直し 4: 撮影地も値も無いラベルは、自分の画面でも封の図案（画面ごとに見た目を割らない）。
    /// 自分の口のラベルと、人の口から来た同じラベルは同じ絵
    func testOwnLabelWithoutPlaceUsesTheSealedDesignToo() throws {
        let own = TrunkLabel(id: "abc-123", photoId: "abc-123", kind: .place, place: .init(name: "", latin: nil, country: nil),
                             seed: 4_242, at: "2025-09-01T10:00:00Z")
        XCTAssertTrue(TrunkLabelDesign.isSealed(own))
        let theirs = try decode(TheirTrunk.self, #"{"stuck":[{"id":"s0","kind":"place","seed":4242,"place":{"name":""},"where":null}]}"#)
        XCTAssertEqual(TrunkLabelDesign.spec(for: own), TrunkLabelDesign.spec(for: theirs.stuck[0]), "自分の画面と人の画面で絵が割れる")
        XCTAssertEqual(TrunkLabelDesign.spec(for: own).art, .postmark)
        // 地名の無い節目（10 枚目）は値があるので節目の絵のまま
        let ten = try XCTUnwrap(TrunkSample.pocket.first { $0.id == "p-ten" })
        XCTAssertFalse(TrunkLabelDesign.isSealed(ten))
    }

    // MARK: 画面のつなぎ（Linux で描けないので書き方で見る）

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    func testWiring() throws {
        let profile = try source("Features/Profile/UserProfileView.swift")
        XCTAssertTrue(profile.contains("if trunk.showsOnProfile(blocked: isBlocked), let shown = trunk.trunk {"),
                      "段の出し分けを通していない（決まりは testModelPhases が値で見る）")
        XCTAssertTrue(profile.contains(#".accessibilityIdentifier("profile.trunk")"#))
        let view = try source("Features/Trunk/TheirTrunkView.swift")
        for id in ["trunk.their.loading", "trunk.their.failed", "trunk.their.offline", "trunk.their.hidden"] {
            XCTAssertTrue(view.contains("\"\(id)\""), "\(id) が無い")
        }
        // 読むだけ: 貼る・部品箱・カプセルの機械への入口を置かない
        for forbidden in ["TrunkStickView", "TrunkPartsBoxView", "TrunkGachaView", "TrunkPocketView", "非公開", "捨て"] {
            XCTAssertFalse(view.contains(forbidden), "人のトランクに \(forbidden)")
        }
        XCTAssertTrue(view.contains("theirs: TheirTrunkInside("), "自分のふたを開ける画面を使っていない")
        let open = try source("Features/Trunk/TrunkOpenView.swift")
        XCTAssertTrue(open.contains("if phase == .loaded && contents.isEmpty && theirs == nil {"),
                      "人のトランクに「写真を投稿する」の空の案内が出る")
        XCTAssertTrue(open.contains("SupporterCardViewer(face: theirs.cardFace)"))
        let settings = try source("Features/Settings/SettingsView.swift")
        XCTAssertTrue(settings.contains("TrunkShowRow(model: trunkPrivacy, service: environment.trunk)"))
        XCTAssertTrue(settings.contains("trunkPrivacy.reset(for: auth.userId)"), "人が替わっても前の設定が残る")
        // 乗車券は本人の操作なしに送らない: 送るのは揃えの1か所だけ
        let pick = try source("Features/Pass/PassCardPickView.swift")
        XCTAssertFalse(pick.contains("setTicket("), "選び直しだけで乗車券をトランクに置く")
        // 揃えの配線は `testPassStoreCallsTheSyncAfterUpdate` が値で見る
        // 入れ物の目印は子のボタンの目印を上書きしない（`TrunkWiringTests` と同じ決まり）
        let lines = (view + open).components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        for id in ["trunk.their.loading", "trunk.their.failed", "trunk.their.offline", "trunk.their.hidden",
                   "trunk.their.screen", "trunk.their.sheet", "trunk.their.ticket"] {
            guard let k = lines.firstIndex(of: ".accessibilityIdentifier(\"\(id)\")") else { XCTFail("\(id) が無い"); continue }
            XCTAssertEqual(lines[k - 1], ".accessibilityElement(children: .contain)", "\(id) が子の目印を上書きする")
        }
    }

    func testPreviewKeyIsDebugOnlyAndScreenshotsExist() throws {
        let preview = try source("Core/Auth/PreviewSession.swift")
        XCTAssertTrue(preview.contains("static let theirTrunkKey = \"JPPreviewTheirTrunk\""))
        let block = preview.components(separatedBy: "static var theirTrunkSample: Bool {")[1].components(separatedBy: "#endif")[0]
        XCTAssertTrue(block.contains("#if DEBUG") && block.contains("#else\n        return false"), "Release で見本が効く")
        XCTAssertFalse(PreviewSession.theirTrunkSample)
        let shots = try String(contentsOf: root.appendingPathComponent("UITests/JourneyPhotoUITests/ScreenshotTests.swift"),
                               encoding: .utf8)
        for name in ["101-人のプロフィールのトランク", "101a-人のトランク", "101b-人のトランク（地名の無いラベル）",
                     "101c-人のトランクの中", "101d-人のトランクを回した", "101e-人の会員証を回す（番号なし）",
                     "101f-人の乗車券を回す"] {
            XCTAssertTrue(shots.contains("\"\(name)\""), "画面写真 \(name) が無い")
        }
    }
}
