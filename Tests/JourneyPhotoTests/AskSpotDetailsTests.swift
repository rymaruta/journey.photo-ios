import XCTest
@testable import JourneyPhoto

/// 「AI に頼む」の答えの観光スポットにも写真の詳細を読み足す（2026-11-22・owner「画像出てこないの悲しい」）。
///
/// AI の答えの札は索引の行（`isIndexOnly`・写真なし）のままで、旅行プランの流れ（`AskPlanTimeline`）と控えから戻した会話では
/// 詳細を読む所が無く、44pt の枠が灰色のままだった（大野湊神社、兼六園、金沢21世紀美術館…）。ここでは
///   1. 出ている答え（畳んでいない往復）の場所だけを、重ねずに集める（旅行プランの日ごとの場所も）
///   2. 鍵: 同じ場所なら同じ鍵、圏外と答えのあとの読み込みの最中は空、重ねたら空（通信が止まる）
///   3. 重ねた詳細が `spotsById` に入り、写真が出る（旅行プランの流れ、控えから戻した会話）
/// を見る。
final class AskSpotDetailsTests: XCTestCase {

    @MainActor
    private func engine() -> AskEngine {
        AskEngine(history: AskHistoryStore(defaults: UserDefaults(suiteName: "AskSpotDetailsTests.\(UUID().uuidString)")!))
    }

    /// 区分（詳細）を読んだあとの行: 索引の行に写真を重ねたもの
    private func detailed(_ row: OfficialSpot) throws -> OfficialSpot {
        let json = "{\"spotId\":\"\(row.spotId)\",\"slug\":\"\(row.slug)\",\"name\":\"\(row.name)\",\"stage\":\"published\","
            + "\"image\":{\"url\":\"https://journey-photo.com/images/spots/\(row.slug).jpg\",\"author\":\"A\",\"license\":\"CC0\"}}"
        return row.merged(with: try JSONDecoder.api.decode(OfficialSpot.self, from: Data(json.utf8)))
    }

    private func planAnswer(_ days: [[String]]) -> AskAnswer {
        var a = AskAnswer(engine: .device, text: "金沢の旅行プランです。")
        a.kind = .plan
        a.spotIds = days.flatMap { $0 }
        a.plan = AskPlanAnswer(title: "金沢の旅", planId: "plan_1", days: days)
        return a
    }

    /// 出ている答えの場所を集める: 旅行プランの日ごとの場所も、札の場所も。重ねず、畳んだ往復は入れない、詳細つきは入れない
    func testAskedCollectsShownSpotsOnly() throws {
        let rows = try AskSamples.ledger()
        let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.spotId, $0) })
        // 旅行プランの答え（`spotIds` を持たない古い控えでも、日ごとの場所から集める）
        var plan = planAnswer([["sp_kenrokuen", "sp_yashima"], ["sp_kenrokuen"]])
        plan.spotIds = []
        let planExchange = AskExchange(question: "金沢で2日", answer: plan)
        var cards = AskAnswer(engine: .device, text: "香川です。")
        cards.spotIds = ["sp_chichibugahama", "sp_yashima", "sp_unknown"]
        let cardsExchange = AskExchange(question: "香川で夕日", answer: cards)
        let thread = [planExchange, cardsExchange]

        let all = SpotDetailNeeds.asked(thread, shown: { _ in true }, spotsById: byId)
        XCTAssertEqual(all.map(\.spotId), ["sp_kenrokuen", "sp_yashima", "sp_chichibugahama"], "出る順に重ねずに集めていない")

        let latestOnly = SpotDetailNeeds.asked(thread, shown: { $0.id == cardsExchange.id }, spotsById: byId)
        XCTAssertEqual(latestOnly.map(\.spotId), ["sp_chichibugahama", "sp_yashima"], "畳んだ答えの場所まで読む")

        var withPhoto = byId
        withPhoto["sp_kenrokuen"] = try detailed(byId["sp_kenrokuen"]!)
        let rest = SpotDetailNeeds.asked(thread, shown: { _ in true }, spotsById: withPhoto)
        XCTAssertFalse(rest.contains { $0.spotId == "sp_kenrokuen" }, "詳細つきの行をまた読む")
    }

    /// 鍵: 同じ場所なら同じ（読み直さない）、圏外と読み込みの最中は空（読まない）
    func testAskTaskKey() throws {
        let rows = Array(try AskSamples.ledger().prefix(2))
        let key = SpotDetailNeeds.askTaskKey(rows, offline: false, loading: false)
        XCTAssertEqual(key, "sp_chichibugahama,sp_yashima")
        XCTAssertEqual(SpotDetailNeeds.askTaskKey(rows.reversed(), offline: false, loading: false), key, "並びで鍵が変わった（読み直す）")
        XCTAssertEqual(SpotDetailNeeds.askTaskKey(rows, offline: true, loading: false), "", "圏外で読みに行く")
        XCTAssertEqual(SpotDetailNeeds.askTaskKey(rows, offline: false, loading: true), "", "答えのあとの読み込みと重ねて読む")
        XCTAssertEqual(SpotDetailNeeds.askTaskKey([], offline: false, loading: false), "")
    }

    /// 旅行プランの流れ: 読み足した詳細が `spotsById` に入り、写真が出る。そのあとは鍵が空になって通信が止まる
    @MainActor
    func testPlanFlowSpotsGetPhotos() async throws {
        let rows = try AskSamples.ledger()
        let kenrokuen = rows[3], yashima = rows[0]
        XCTAssertNil(kenrokuen.photo, "試験の前提: 索引の行に写真は無い")
        let e = engine()
        let q = try XCTUnwrap(e.beginPlan("金沢で2日の旅行プランにして"))
        let result = TripAIResult(title: "金沢の旅", days: [[kenrokuen], [yashima]], reason: "1日目は金沢、2日目は高松です。",
                                  removed: [], mode: .ai, candidates: [])
        e.finishPlan(q, result: result, planId: "plan_1", onDevice: true, userId: "u1")
        let shown: (AskExchange) -> Bool = { _ in true }

        let needs = SpotDetailNeeds.asked(e.thread, shown: shown, spotsById: e.spotsById)
        XCTAssertEqual(Set(needs.map(\.spotId)), ["sp_kenrokuen", "sp_yashima"], "旅行プランの流れの場所を読まない")

        // 区分に兼六園だけ写真があった（屋島は区分に無く、索引の行のまま返った）
        e.overlayDetails([try detailed(kenrokuen), yashima])
        XCTAssertNotNil(e.spotsById["sp_kenrokuen"]?.photo, "読み足した写真を札に重ねていない")
        XCTAssertNil(e.spotsById["sp_yashima"]?.photo)
        let after = SpotDetailNeeds.asked(e.thread, shown: shown, spotsById: e.spotsById)
        XCTAssertEqual(after.map(\.spotId), ["sp_yashima"])
        // 区分に無かった屋島は、同じ鍵のまま（もう一度読みに行かない）
        e.overlayDetails([yashima])
        XCTAssertEqual(SpotDetailNeeds.askTaskKey(SpotDetailNeeds.asked(e.thread, shown: shown, spotsById: e.spotsById),
                                                  offline: false, loading: false), "sp_yashima")
    }

    /// 控えから戻した会話（開き直したとき）: 札の行は索引から戻るので、読み足して写真を出す
    @MainActor
    func testRestoredConversationGetsPhotos() async throws {
        let rows = try AskSamples.ledger()
        let e = engine()
        let saved = AskExchange(question: "金沢で2日", answer: planAnswer([["sp_kenrokuen"], ["sp_eikando"]]))
        let backend = AskEngine.Backend(
            signedIn: { true }, offline: { false }, deviceAI: { true },
            library: { _ in AskLibrary(spots: rows, photos: []) },
            reserve: { _, _ in throw URLError(.notConnectedToInternet) },
            serverAsk: { _, _, _ in AskService.ServerAnswer(answer: "", general: false) },
            deviceAsk: { _, _, _ in nil },
            details: { $0 }, userId: { "u1" })
        await e.open(.init(id: "c1", thread: [saved]), backend: backend)
        XCTAssertNil(e.spotsById["sp_kenrokuen"]?.photo, "試験の前提: 戻した札は索引の行")

        let needs = SpotDetailNeeds.asked(e.thread, shown: { _ in true }, spotsById: e.spotsById)
        XCTAssertEqual(needs.map(\.spotId), ["sp_kenrokuen", "sp_eikando"])
        e.overlayDetails(try needs.map(detailed))
        XCTAssertNotNil(e.spotsById["sp_kenrokuen"]?.photo)
        XCTAssertNotNil(e.spotsById["sp_eikando"]?.photo)
        XCTAssertEqual(SpotDetailNeeds.askTaskKey(SpotDetailNeeds.asked(e.thread, shown: { _ in true }, spotsById: e.spotsById),
                                                  offline: false, loading: false), "", "重ねたのに鍵が空にならない（読み直し続ける）")
    }
    /// 答えのあとの読み込み（`loadPendingDetails`）は、写真つきの行を索引の行で上書きしない（2026-11-22 確かめ役の指摘）。
    /// 1回目で写真が入った屋島が、2回目の答えで区分に無く索引の行のまま返っても、写真は下がらない
    @MainActor
    func testPendingDetailsDoNotDowngradePhotos() async throws {
        let rows = try AskSamples.ledger()
        let e = engine()
        func backend(details: @escaping ([OfficialSpot]) async -> [OfficialSpot]) -> AskEngine.Backend {
            AskEngine.Backend(
                signedIn: { true }, offline: { false }, deviceAI: { true },
                library: { _ in AskLibrary(spots: rows, photos: []) },
                reserve: { _, _ in throw AskService.Failure.limit(.day, nil) },
                serverAsk: { _, _, _ in AskService.ServerAnswer(answer: "", general: false) },
                deviceAsk: { _, _, _ in nil },
                details: details, userId: { "u1" })
        }
        let withPhotos = backend(details: { [self] needed in needed.compactMap { try? self.detailed($0) } })
        await e.start("香川で夕日がきれいな所", backend: withPhotos)
        let first = try XCTUnwrap(e.thread.last?.answer)
        XCTAssertTrue(first.spotIds.contains("sp_yashima"), "試験の前提: 屋島が札に出ていない \(first.spotIds)")
        XCTAssertNotNil(e.spotsById["sp_yashima"]?.photo, "試験の前提: 1回目で写真が入っていない")

        // 2回目: 区分に無く、索引の行のまま返る
        await e.followUp("香川で夕日が見える所は？", backend: backend(details: { $0 }))
        XCTAssertTrue(e.thread.last?.answer.spotIds.contains("sp_yashima") == true, "試験の前提: 2回目にも屋島が出ていない")
        XCTAssertNotNil(e.spotsById["sp_yashima"]?.photo, "写真つきの行を索引の行で上書きした（写真が下がった）")
    }

    /// 古い形で保存した旅行プランの答え（`spotIds` が空で日ごとの場所だけ）を開き直しても、場所が出て写真を読み足せる
    /// （`open` → `refill` → `remember` の道・2026-11-22 確かめ役の指摘）
    @MainActor
    func testReopenedOldPlanAnswerRemembersDaySpots() async throws {
        let rows = try AskSamples.ledger()
        let e = engine()
        var old = planAnswer([["sp_kenrokuen"], ["sp_eikando"]])
        old.spotIds = []
        let backend = AskEngine.Backend(
            signedIn: { true }, offline: { false }, deviceAI: { true },
            library: { _ in AskLibrary(spots: rows, photos: []) },
            reserve: { _, _ in throw URLError(.notConnectedToInternet) },
            serverAsk: { _, _, _ in AskService.ServerAnswer(answer: "", general: false) },
            deviceAsk: { _, _, _ in nil },
            details: { $0 }, userId: { "u1" })
        await e.open(.init(id: "old", thread: [AskExchange(question: "金沢で2日", answer: old)]), backend: backend)
        XCTAssertNotNil(e.spotsById["sp_kenrokuen"], "古い形の旅行プランの場所を覚えていない（流れが空になる）")
        XCTAssertNotNil(e.spotsById["sp_eikando"])
        let needs = SpotDetailNeeds.asked(e.thread, shown: { _ in true }, spotsById: e.spotsById)
        XCTAssertEqual(needs.map(\.spotId), ["sp_kenrokuen", "sp_eikando"])
        e.overlayDetails(try needs.map(detailed))
        XCTAssertNotNil(e.spotsById["sp_kenrokuen"]?.photo)
    }
}
