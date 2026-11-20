import XCTest
@testable import JourneyPhoto

/// サーバーの口の形（#652 のサーバーの担当のコメント 2026-11-20 10:51・11:28、journey.photo-web #694〜#697）に合わせた所。
@MainActor
final class AskServiceShapeTests: XCTestCase {

    /// history は `{"q","a"}`、sources は `kind: spot | help`（観光スポットは note に案内の文）、合わせて 8 件まで
    func testRequestShape() async throws {
        let turn = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AskService.Turn(question: "Q", answer: "A"))) as? [String: String]
        XCTAssertEqual(turn, ["q": "Q", "a": "A"])

        let rows = try AskSamples.ledger()
        let many = Array(repeating: rows[0], count: 12)
        let sources = AskService.sources(text: "ストーリーに曲を付けるには", spots: many)
        XCTAssertEqual(sources.count, 8, "サーバーは 8 件まで")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(sources)) as? [[String: Any]])
        XCTAssertEqual(json.first?["kind"] as? String, "help", "質問に合う使い方の頁を先に")
        XCTAssertEqual(json.first?["title"] as? String, "ストーリーの使い方")
        XCTAssertLessThanOrEqual((json.first?["body"] as? String)?.count ?? 0, 400)
        let spot = try XCTUnwrap(json.first { $0["kind"] as? String == "spot" })
        XCTAssertEqual(Set(spot.keys), ["kind", "name", "area", "category", "seasons", "times", "note"])
        XCTAssertEqual(spot["note"] as? String, "山上の展望台から、瀬戸内の島へ沈む夕日が見えます。")
        // 現在地、行きたい場所、旅行プランの欄は持たない
        for row in json {
            for key in ["lat", "lng", "coords", "here", "wishlist", "trips", "spotId"] { XCTAssertNil(row[key], key) }
        }
    }

    /// 返事の `refused` と `quota`（無ければ false と nil）。429 と 403 の本文
    func testReplyShape() async throws {
        let full = """
        {"answer":"この質問にはお答えできません。","general":false,"refused":true,
         "quota":{"tier":"pro","kind":"ask","day":{"used":3,"limit":20,"remaining":17},
                  "month":{"used":3,"limit":300,"remaining":297,"resetsOn":"2026-12-01"},"serverAllowed":true}}
        """
        let a = try JSONDecoder.api.decode(AskService.ServerAnswer.self, from: Data(full.utf8))
        XCTAssertTrue(a.refused)
        XCTAssertEqual(a.quota?.day.remaining, 17)
        let short = try JSONDecoder.api.decode(AskService.ServerAnswer.self, from: Data(#"{"answer":"x","general":true}"#.utf8))
        XCTAssertFalse(short.refused)
        XCTAssertNil(short.quota)

        let limit = Data(#"{"reason":"month","code":"limit","error":"x","quota":{"tier":"pro","kind":"ask","day":{"used":5,"limit":20,"remaining":15},"month":{"used":300,"limit":300,"remaining":0,"resetsOn":"2026-12-01"},"serverAllowed":true}}"#.utf8)
        XCTAssertEqual(AskService.reason(from: limit), .month)
        XCTAssertEqual(AskService.quota(from: limit)?.isPro, true, "Pro の人に Pro の案内を出さないための数")
        XCTAssertEqual(AskService.reasonText(from: Data(#"{"reason":"proOnly","code":"pro_only"}"#.utf8)), "proOnly")
    }

    /// 無料の人の via:"server"（403 proOnly）とサーバーの断り（refused）は、言葉の表と断りの1行に
    func testProOnlyAndServerRefusal() async throws {
        let rows = try AskSamples.ledger()
        let d = UserDefaults(suiteName: "AskServiceShapeTests.\(UUID().uuidString)")!
        func backend(reserve: @escaping () throws -> AskUsage, reply: AskService.ServerAnswer) -> AskEngine.Backend {
            AskEngine.Backend(signedIn: { true }, offline: { false }, deviceAI: { false },
                              library: { _ in AskLibrary(spots: rows, photos: []) },
                              reserve: { _, _ in try reserve() },
                              serverAsk: { _, _, _ in reply },
                              deviceAsk: { _, _, _ in nil }, details: { $0 }, userId: { "u1" })
        }
        let e1 = AskEngine(history: AskHistoryStore(defaults: d))
        await e1.start("おすすめの観光スポット教えて",
                       backend: backend(reserve: { throw AskService.Failure.proOnly }, reply: .init(answer: "", general: false)))
        XCTAssertEqual(e1.thread.first?.answer.engine, .table)
        XCTAssertEqual(e1.thread.first?.answer.note, AskText.noDeviceAILine)

        let pro = AskUsage(tier: "pro", kind: "ask", day: .init(used: 1, limit: 20, remaining: 19),
                           month: .init(used: 1, limit: 300, remaining: 299), serverAllowed: true)
        let e2 = AskEngine(history: AskHistoryStore(defaults: d))
        await e2.start("香川で夕日がきれいな所を教えて",
                       backend: backend(reserve: { pro }, reply: .init(answer: "断ります", general: false, refused: true, quota: pro)))
        XCTAssertEqual(e2.thread.first?.answer.engine, .refused)
        XCTAssertEqual(e2.thread.first?.answer.text, AskGuard.refusal)
        XCTAssertTrue(e2.thread.first?.answer.spotIds.isEmpty ?? false)
    }
}
