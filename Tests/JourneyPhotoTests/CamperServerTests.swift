import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JourneyPhoto

/// とおまわり号の第2段（2026-10-19）: 要サーバーの部品の口・分母 131・端末の数え方へ戻る・届いた画面の並び・
/// 友達の車（訪ねる・贈る・薪）・写真の保存の `camper.added`・断りの言葉
@MainActor
final class CamperServerTests: XCTestCase {

    private func defaults() -> UserDefaults {
        let name = "camper.server.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return d
    }

    private lazy var session: URLSession = {
        ScriptedProtocol.reset()
        addTeardownBlock { ScriptedProtocol.reset() }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        return URLSession(configuration: config)
    }()

    private var service: CamperService {
        CamperService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                     tokenProvider: StubTokenProvider(token: "t"), session: session))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.api.decode(T.self, from: Data(json.utf8))
    }

    /// サーバーの `GET /user/camper` の形（photo-gallery `readMyCamper` の戻り値）
    private let mineJSON = #"""
    {"launched":true,
     "parts":[{"id":"sticker_edge.signed","at":"2026-10-19T09:00:00.000Z","from":{"userId":"u-mio","name":"mio"}},
              {"id":"flag.swallowtail","at":"2026-10-19T08:00:00.000Z"},
              {"id":"unknown.part","at":"2026-10-19T08:00:00.000Z"},
              {"id":"flag.swallowtail","at":"2026-10-19T07:00:00.000Z"},
              {"oops":1}],
     "trips":3,"progress":{"trips":3,"giftsFrom":1,"visits":2,"wood":4,"tripFriends":0},
     "recounted":true,"added":["flag.swallowtail","nope.nope"]}
    """#

    // MARK: 決まり（サーバーの表の写し）

    /// 要サーバーの 33 個は図鑑の `.server` と同じ（記録 20・写真 13）。キャンプ場の焚き火は入らない
    func testRulesMatchTheCatalog() async {
        let server = Set(CamperCatalog.dex.filter(\.unlock.isServer).map(\.id))
        XCTAssertEqual(server.count, 33)
        XCTAssertEqual(CamperServerRule.all, server)
        XCTAssertEqual(CamperServerRule.needs.count, 20)
        XCTAssertEqual(CamperServerRule.photoParts.count, 13)
        XCTAssertTrue(CamperServerRule.photoParts.isDisjoint(with: Set(CamperServerRule.needs.keys)))
        XCTAssertFalse(CamperServerRule.all.contains("fire_pit.stone_ring"))
        // 旅の数は図鑑の条件の数と同じ（「旅を公開で N 回投稿」）
        for (id, need) in CamperServerRule.needs where need.metric == .trips {
            let part = CamperCatalog.part(id)!
            XCTAssertEqual(part.unlock.condition, L("旅を公開で \(need.count) 回投稿", "Post \(need.count) public trips"), id)
        }
    }

    /// 分母: 読めて配り始めている間は 131、読めない・始まっていない間は 98（端末の数え方）
    func testDenominatorIs131OnlyWhenServerIsOpen() async throws {
        XCTAssertEqual(CamperCatalog.dexCount([], serverOpen: true).total, 131)
        XCTAssertEqual(CamperCatalog.dexCount([], serverOpen: false).total, 98)
        XCTAssertEqual(CamperCatalog.dexCount([]).total, 98)
        XCTAssertEqual(CamperText.dexNote(serverOpen: true), L("図鑑 132 · 近日 1", "Dex 132 · 1 soon"))
        XCTAssertEqual(CamperText.dexNote(serverOpen: false), L("図鑑 132 · 近日 34", "Dex 132 · 34 soon"))

        let state = try decode(CamperServerState.self, mineJSON)
        let open = CamperServerParts(state: state)
        XCTAssertTrue(open.open)
        let owned = CamperCatalog.owned(CamperStats(), server: open)
        XCTAssertTrue(owned.contains("flag.swallowtail"))
        XCTAssertTrue(owned.contains("sticker_edge.signed"))
        XCTAssertEqual(CamperCatalog.dexCount(owned, serverOpen: true).have, CamperCatalog.dexCount(CamperCatalog.owned(CamperStats())).have + 2)

        // 始まっていない（launched: false）・読めない（nil）は何も足さない
        let notYet = CamperServerParts(state: try decode(CamperServerState.self, #"{"launched":false,"parts":[{"id":"flag.swallowtail","at":"x"}]}"#))
        XCTAssertFalse(notYet.open)
        XCTAssertFalse(CamperCatalog.owned(CamperStats(), server: notYet).contains("flag.swallowtail"))
        XCTAssertFalse(CamperCatalog.owned(CamperStats(), server: .closed).contains("flag.swallowtail"))
        // `launched` の無い応答は始まっていない扱い
        XCTAssertFalse(CamperServerParts(state: try decode(CamperServerState.self, #"{"parts":[]}"#)).open)
    }

    /// 応答は包みで読む: 図鑑に無い id・重なり・形の違う要素を落とす。贈った人の名前を読む
    func testDecodesServerShapeLeniently() async throws {
        let state = try decode(CamperServerState.self, mineJSON)
        XCTAssertEqual(state.parts.map(\.id), ["sticker_edge.signed", "flag.swallowtail"])
        XCTAssertEqual(state.giver(of: "sticker_edge.signed"), .init(userId: "u-mio", name: "mio"))
        XCTAssertNil(state.giver(of: "flag.swallowtail"))
        XCTAssertEqual(state.added, ["flag.swallowtail"])
        XCTAssertEqual(state.progress, .init(trips: 3, giftsFrom: 1, visits: 2, wood: 4, tripFriends: 0))
        XCTAssertTrue(state.recounted)
        let parts = CamperServerParts(state: state)
        XCTAssertEqual(parts.giverName("sticker_edge.signed"), "mio")
        XCTAssertNil(parts.giverName("flag.swallowtail"))

        let visit = try decode(CamperVisitState.self,
                               #"{"userId":"u-mio","launched":true,"parts":["roof_cargo.canoe","bad"],"visit":{"counted":true,"added":["ladder.wood_rungs"]}}"#)
        XCTAssertEqual(visit.parts, ["roof_cargo.canoe"])
        XCTAssertEqual(visit.visit, .init(counted: true, added: ["ladder.wood_rungs"]))
        XCTAssertEqual(try decode(CamperGiftResult.self, #"{"given":true,"part":"rug.kilim"}"#), .init(given: true, part: "rug.kilim"))
        XCTAssertEqual(try decode(CamperGiftResult.self, #"{"given":true}"#), .init(given: true))
        XCTAssertEqual(try decode(CamperFirewoodResult.self, #"{"added":true,"count":10,"part":"fire_pit.tripod_kettle"}"#),
                       .init(added: true, count: 10, part: "fire_pit.tripod_kettle"))
    }

    /// 進み具合: 記録で決まる部品だけ数を出す（写真で決まる部品は「届いた／まだ」だけ）
    func testProgressOnlyForRecordParts() async {
        let p = CamperServerState.Progress(trips: 5, giftsFrom: 1, visits: 2, wood: 12, tripFriends: 0)
        XCTAssertEqual(CamperServerRule.progress("wheel.brass_spoke", p)?.have, 5)
        XCTAssertEqual(CamperServerRule.progress("wheel.brass_spoke", p)?.need, 20)
        XCTAssertEqual(CamperServerRule.progress("mirror.brass_oval", p)?.need, 2)
        XCTAssertEqual(CamperServerRule.progress("fire_pit.tripod_kettle", p)?.have, 10, "要る数で止める")
        XCTAssertNil(CamperServerRule.progress("roof_cargo.canoe", p))
        XCTAssertNil(CamperServerRule.progress("tire_tread.mud_block", p))
        let canoe = CamperCatalog.part("roof_cargo.canoe")!
        let open = CamperServerParts(state: CamperServerState(launched: true, parts: [], progress: p))
        XCTAssertEqual(canoe.unlock.how(serverOpen: true), L("水辺のスポットで撮ると届きます", "Arrives with: Shoot at a waterside spot"))
        XCTAssertTrue(canoe.unlock.how.hasPrefix(L("近日", "Coming soon")))
        XCTAssertFalse(CamperText.partLabel(canoe, owned: false, stats: CamperStats(), server: open).contains(L("近日", "Coming soon")))
        let spoke = CamperCatalog.part("wheel.brass_spoke")!
        XCTAssertTrue(CamperText.partLabel(spoke, owned: false, stats: CamperStats(), server: open).contains(L("いま 5 / 20", "5 of 20")))
    }

    // MARK: 写真の保存の応答

    /// `camper.added` を読む（無い・形が違う応答は空のまま投稿は成功）
    func testTrunkDealtReadsCamperAdded() async {
        let dealt = TrunkDealt.read(Data(#"{"success":true,"coin":1,"camper":{"added":["bumper.wood_beam","x.y"]}}"#.utf8))
        XCTAssertEqual(dealt.camperAdded, ["bumper.wood_beam"])
        XCTAssertEqual(dealt.coin, 1)
        XCTAssertEqual(TrunkDealt.read(Data(#"{"success":true}"#.utf8)).camperAdded, [])
        XCTAssertEqual(TrunkDealt.read(Data(#"{"success":true,"camper":"oops"}"#.utf8)).camperAdded, [])
        // 控え: 人ごと・図鑑に在る id だけ・足していく
        let d = defaults()
        CamperStore.receive(["bumper.wood_beam", "nope"], userId: "me", defaults: d)
        CamperStore.receive(["flag.windsock", "bumper.wood_beam"], userId: "me", defaults: d)
        CamperStore.receive(["flag.windsock"], userId: nil, defaults: d)
        XCTAssertEqual(CamperStore(userId: "me", defaults: d).inbox, ["bumper.wood_beam", "flag.windsock"])
        XCTAssertEqual(CamperStore(userId: "other", defaults: d).inbox, [])
        CamperStore.removeData(for: "me", defaults: d)
        XCTAssertEqual(CamperStore(userId: "me", defaults: d).inbox, [], "退会で控えを消す")
    }

    // MARK: 自分の車を読む

    /// 読めない・断り・始まっていないは端末の数え方のまま。写真の保存で届いた部品は持っている扱い
    func testServerModelFallsBackToDevice() async throws {
        let d = defaults()
        let store = CamperStore(userId: "me", defaults: d)
        store.receive(["bumper.wood_beam"])
        let model = CamperServerModel()
        struct Down: Error {}
        await model.load(userId: "me", store: store) { throw Down() }
        XCTAssertEqual(model.phase, .failed)
        XCTAssertTrue(model.settled)
        XCTAssertFalse(model.parts.open)
        XCTAssertEqual(CamperCatalog.dexCount(CamperCatalog.owned(CamperStats(), server: model.parts), serverOpen: model.parts.open).total, 98)
        XCTAssertTrue(CamperCatalog.owned(CamperStats(), server: model.parts).contains("bumper.wood_beam"))

        let state = try decode(CamperServerState.self, mineJSON)
        await model.load(userId: "me", store: store) { state }
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertTrue(model.parts.open)
        XCTAssertEqual(model.parts.freshFirst, ["bumper.wood_beam", "flag.swallowtail"], "写真の保存で届いた分・この回に届いた分を先に")
        // 読めたら、戻るたびには読まない
        var calls = 0
        await model.load(userId: "me", store: store) { calls += 1; return state }
        XCTAssertEqual(calls, 0)
        // 人が替わったら読み直す（前の人の部品は捨てる）
        await model.load(userId: "other", store: CamperStore(userId: "other", defaults: d)) { throw Down() }
        XCTAssertFalse(model.parts.open)
        XCTAssertFalse(model.parts.ownedIds.contains("bumper.wood_beam"))
    }

    /// 口の道と断り: GET /user/camper・POST …/gift・…/firewood。断りは `code` の日本語／英語
    func testServicePathsAndRefusals() async throws {
        // 先に口を作る（`session` を作るときに台本を空にするので）
        let s = service
        ScriptedProtocol.script = [
            .init(match: "/user/camper", status: 200, body: mineJSON, once: true),
            .init(match: "/users/u-mio/camper/gift", status: 429, body: #"{"error":"贈れるのは1日1回です","code":"daily"}"#, once: true),
            .init(match: "/users/u-mio/camper/firewood", status: 200, body: #"{"added":true,"count":3}"#, once: true),
            .init(match: "/users/u-ken/camper", status: 403, body: #"{"error":"x","code":"notFriend"}"#, once: true),
        ]
        let mine = try await s.mine()
        XCTAssertEqual(mine.parts.count, 2)
        do {
            _ = try await s.gift("u-mio")
            XCTFail("断りが投げられない")
        } catch let refused as CamperService.Refused {
            XCTAssertEqual(refused.code, "daily")
            XCTAssertEqual(refused.status, 429)
            XCTAssertEqual(refused.errorDescription, L("贈れるのは1日1回です。また明日どうぞ。", "You can give one gift a day. Try again tomorrow."))
        }
        let wood = try await s.firewood("u-mio")
        XCTAssertEqual(wood, .init(added: true, count: 3))
        do {
            _ = try await s.visit("u-ken")
            XCTFail("断りが投げられない")
        } catch let refused as CamperService.Refused {
            XCTAssertEqual(refused.code, "notFriend")
        }
        let methods = ScriptedProtocol.calls.map { "\($0.method) \($0.path)" }
        XCTAssertEqual(methods, ["GET /user/camper", "POST /users/u-mio/camper/gift", "POST /users/u-mio/camper/firewood",
                                 "GET /users/u-ken/camper"])
        // 人の id の形でない値は要求を出さない
        do {
            _ = try await s.visit("../x")
            XCTFail("形の違う id で投げない")
        } catch let refused as CamperService.Refused {
            XCTAssertEqual(refused.code, "notFound")
        }
        XCTAssertEqual(ScriptedProtocol.calls.count, 4)
    }

    /// 断りの言葉: 印ごとに日本語と英語がある（印の無い 429・410 も言い分けられる）
    func testRefusalTexts() async {
        let codes = ["self", "notFriend", "blocked", "newAccount", "noPost", "notFound", "tombstone", "already", "notLaunched",
                     "storage", "deleted", "daily", "busy"]
        var seen = Set<String>()
        for code in codes {
            let text = CamperText.refusal(code: code, status: 400, fallback: "fallback")
            XCTAssertNotEqual(text, "fallback", code)
            XCTAssertTrue(seen.insert(text).inserted, "\(code) の言葉が他と同じ")
        }
        XCTAssertEqual(CamperText.refusal(code: nil, status: 429, fallback: ""),
                       L("今日はもうできません。また明日どうぞ。", "You can\u{2019}t do this again today. Try tomorrow."))
        XCTAssertEqual(CamperText.refusal(code: "x", status: 418, fallback: "サーバーの言い分"), "サーバーの言い分")
        XCTAssertEqual(CamperText.failure(APIError.server(status: 503, message: "x")), CamperText.refusal(code: "busy", status: 503, fallback: ""))
    }

    // MARK: 届いた画面

    /// 一度に 3 個まで。この回に届いた分を先に。見せなかった分は次に開いたときに。はじめて開いたときは全部に印
    func testArrivalsAtMostThreeAndFreshFirst() async {
        let d = defaults()
        let store = CamperStore(userId: "me", defaults: d)
        let base = CamperCatalog.owned(CamperStats())
        // はじめて開いた: 全部に印（前から持っていた部品を何度にも分けない）
        let firstOpen = store.openArrivals(owned: base.union(["flag.swallowtail"]), photosLoaded: true, limit: 3)
        XCTAssertLessThanOrEqual(firstOpen.count, 3)
        XCTAssertTrue(store.seen?.contains("flag.swallowtail") == true)

        let five: Set<String> = ["mudflap.checker", "roof_tent.popup_canvas", "cushion.tasseled", "grille.honeycomb", "wheel.brass_spoke"]
        let owned = base.union(["flag.swallowtail"]).union(five)
        let shown = store.openArrivals(owned: owned, photosLoaded: true, first: ["grille.honeycomb", "cushion.tasseled"], limit: 3)
        XCTAssertEqual(shown.count, 3)
        XCTAssertEqual(shown.prefix(2).map(\.id), ["grille.honeycomb", "cushion.tasseled"], "この回に届いた分を先に")
        XCTAssertEqual(shown[2].id, "wheel.brass_spoke", "残りは珍しい順")
        let next = store.openArrivals(owned: owned, photosLoaded: true, limit: 3)
        XCTAssertEqual(Set(next.map(\.id)), ["mudflap.checker", "roof_tent.popup_canvas"], "見せなかった分は次に開いたとき")
        XCTAssertTrue(store.openArrivals(owned: owned, photosLoaded: true, limit: 3).isEmpty)
        XCTAssertEqual(CamperArrivals(parts: CamperCatalog.dex).parts.count, 3)
    }

    /// 贈り物で届いた部品は贈ってくれた人の名前で言う（名前の無い人は「友達から」）
    func testBecauseNamesTheGiver() async {
        let signed = CamperCatalog.part("sticker_edge.signed")!
        XCTAssertEqual(CamperText.because(signed, giver: "mio"), L("mioから贈られました", "A gift from mio"))
        XCTAssertEqual(CamperText.because(signed, giver: ""), L("友達から贈られました", "A gift from a friend"))
        XCTAssertEqual(CamperText.because(signed, giver: nil), signed.unlock.because)
    }

    // MARK: 友達の車

    private func calls(visit: @escaping (String) async throws -> CamperVisitState = { CamperServerSample.visit(userId: $0) },
                       gift: @escaping (String) async throws -> CamperGiftResult = { _ in .init(given: true) },
                       firewood: @escaping (String) async throws -> CamperFirewoodResult = { _ in .init(added: true, count: 1) })
        -> CamperVisitModel.Calls {
        .init(visit: visit, gift: gift, firewood: firewood)
    }

    /// 訪ねた記録が数えられたら控えめに知らせ、訪ねて自分に届いた部品は自分の控えへ
    func testVisitCountsAndReceives() async {
        let d = defaults()
        let store = CamperStore(userId: "me", defaults: d)
        let model = CamperVisitModel()
        await model.load(userId: "u-mio", signedIn: true, calls: calls(visit: { id in
            CamperVisitState(userId: id, launched: true, parts: ["roof_cargo.canoe"], visit: .init(counted: true, added: ["ladder.wood_rungs"]))
        }), store: store)
        guard case .loaded(let state) = model.phase else { return XCTFail("読めていない") }
        XCTAssertEqual(state.parts, ["roof_cargo.canoe"])
        XCTAssertEqual(model.visitNotice, CamperText.visitCounted(added: 1))
        XCTAssertEqual(store.inbox, ["ladder.wood_rungs"])
        // 今日2回目（数えない）は何も言わない
        let again = CamperVisitModel()
        await again.load(userId: "u-mio", signedIn: true, calls: calls(visit: { id in
            CamperVisitState(userId: id, launched: true, parts: [], visit: .init(counted: false))
        }), store: store)
        XCTAssertNil(again.visitNotice)
        // 断り（互いのフォローでない）は日本語の一言
        let refused = CamperVisitModel()
        await refused.load(userId: "u-ken", signedIn: true, calls: calls(visit: { _ in
            throw CamperService.Refused(status: 403, message: "x", code: "notFriend")
        }), store: store)
        XCTAssertEqual(refused.phase, .failed(CamperText.refusal(code: "notFriend", status: 403, fallback: "")))
    }

    /// 贈る: 届いた部品は相手の名前で言う。もう贈ってあった（already）はボタンを止める
    func testGiftAndFirewood() async {
        let d = defaults()
        let store = CamperStore(userId: "me", defaults: d)
        let model = CamperVisitModel()
        await model.load(userId: "u-mio", signedIn: true, calls: calls(), store: store)
        await model.gift(calls: calls(gift: { _ in .init(given: true, part: "mirror.brass_oval") }), ownerName: "mio")
        XCTAssertTrue(model.gifted)
        XCTAssertEqual(model.message, .init(text: CamperText.gifted(part: CamperCatalog.part("mirror.brass_oval"), to: "mio"), isError: false))

        let second = CamperVisitModel()
        await second.load(userId: "u-mio", signedIn: true, calls: calls(), store: store)
        await second.gift(calls: calls(gift: { _ in throw CamperService.Refused(status: 409, message: "", code: "already") }), ownerName: "mio")
        XCTAssertTrue(second.gifted, "もう贈ってあったらボタンを止める")
        XCTAssertEqual(second.message?.isError, true)

        await second.firewood(calls: calls(firewood: { _ in .init(added: true, count: 10, part: "fire_pit.tripod_kettle") }), store: store)
        XCTAssertEqual(second.woodCount, 10)
        XCTAssertTrue(store.inbox.contains("fire_pit.tripod_kettle"), "10 回で自分に届いた部品は自分の控えへ")
        XCTAssertTrue(second.message?.text.contains(CamperCatalog.part("fire_pit.tripod_kettle")!.name) == true)
    }

    /// 友達の車の見せ方: 相手の要サーバーの部品を分類ごとに付け、オーニングの部品があれば広げる
    func testVisitingLoadout() async {
        let l = CamperLoadout.visiting(["roof_cargo.canoe", "awning.rust_stripe", "wheel.brass_spoke"])
        XCTAssertEqual(l.key(.roofCargo), "canoe")
        XCTAssertEqual(l.key(.wheel), "brass_spoke")
        XCTAssertEqual(l.key(.awning), "rust_stripe")
        XCTAssertTrue(l.awningOpen)
        XCTAssertEqual(CamperLoadout.visiting([]), .standard)
    }

    /// 画面のつなぎ: 人のプロフィールから友達の車へ・車の画面は口を読む・見本はサーバーに送らない
    func testScreensAreWired() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let read = { (path: String) in try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
        let profile = try read("Sources/JourneyPhoto/Features/Profile/UserProfileView.swift")
        XCTAssertTrue(profile.contains("CamperVisitView(userId: userId, ownerName: model.shownName)"))
        XCTAssertTrue(profile.contains("if canAct, model.isFollowing"))
        let garage = try read("Sources/JourneyPhoto/Features/Camper/CamperGarageView.swift")
        XCTAssertTrue(garage.contains("return try await service.mine()"))
        XCTAssertTrue(garage.contains("CamperCatalog.owned(stats, server: server.parts)"))
        XCTAssertTrue(garage.contains("guard photosLoaded, server.settled, !arrivalChecked"))
        let env = try read("Sources/JourneyPhoto/App/AppEnvironment.swift")
        XCTAssertTrue(env.contains("self.camper = CamperService(api: api)"))
        let upload = try read("Sources/JourneyPhoto/Features/Upload/UploadViewModel.swift")
        XCTAssertTrue(upload.contains("CamperStore.receive(camperAdded, userId: savedPhotoOwner ?? draftOwner)"))
    }
}
