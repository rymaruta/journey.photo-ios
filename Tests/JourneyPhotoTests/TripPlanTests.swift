import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 旅行プラン（キャンバス 17・17b・17c ／ Web の `/trips`）。
///
/// 見張るのは Web と揃えた約束: **読めた分だけ採る**・**日付は「2026年12月24日」**・
/// **足せるのは保存済みの行きたい場所だけ**・**変えた項目だけ送る**・
/// **書き込みの応答（書いたあとの一覧）をそのまま映す**。
final class TripPlanTests: XCTestCase {

    // MARK: - 読む

    private func plans(_ json: String) throws -> [TripPlan] {
        try JSONDecoder.api.decode(TripPlanList.self, from: Data(json.utf8)).plans
    }

    /// 形どおりの行は全部の欄が読める
    func testDecodesAWholePlan() throws {
        let list = try plans(#"""
        {"plans":[{"planId":"p1","title":"冬","startDate":"2026-12-24","endDate":"2026-12-25",
          "days":[{"date":"2026-12-24","items":[{"kind":"spot","spotId":"sp_1","note":"朝"},{"kind":"location","slug":"金沢"}]},{"items":[]}]}]}
        """#)
        XCTAssertEqual(list.count, 1)
        let p = list[0]
        XCTAssertEqual(p.title, "冬")
        XCTAssertEqual(p.startDate, "2026-12-24")
        XCTAssertEqual(p.days.count, 2)
        XCTAssertEqual(p.days[0].items, [.spot(spotId: "sp_1", note: "朝"), .location(slug: "金沢", note: nil)])
        XCTAssertEqual(p.itemCount, 2)
    }

    /// **壊れた項目・壊れた行は、その分だけ落とす**（プランごと・一覧ごと消さない）
    func testDropsOnlyTheBrokenParts() throws {
        let list = try plans(#"""
        {"plans":[
          {"planId":"p1","title":"a","days":[{"items":[{"kind":"spot"},{"kind":"bus","slug":"x"},{"kind":"location","slug":"ok"}]}]},
          {"title":"ID が無い"},
          {"planId":"","title":"ID が空"},
          {"planId":"p2","days":"壊れた日程"}
        ]}
        """#)
        XCTAssertEqual(list.map(\.planId), ["p1", "p2"])
        XCTAssertEqual(list[0].days[0].items, [.location(slug: "ok", note: nil)])
        XCTAssertEqual(list[1].title, "", "題が無い行も落とさない")
        XCTAssertEqual(list[1].days, [])
    }

    /// **読めない日は空の日として残す**（Web の `usableTripPlan` と同じ）。
    /// 落とすと3日目以降の「N 日目」がずれ、次の保存で空の日が消える
    func testUnreadableDaysStayAsEmptyDays() throws {
        let list = try plans(#"{"plans":[{"planId":"p","days":[{"items":[{"kind":"location","slug":"a"}]},null,7,{"items":[]}]}]}"#)
        XCTAssertEqual(list[0].days.count, 4)
        XCTAssertEqual(list[0].days[1], TripDay())
        XCTAssertEqual(list[0].days[2], TripDay())
    }

    /// **`plans` の無い応答は「0件」ではなく失敗**（通信に失敗しただけの人に「まだ無い」と言わない）
    func testMissingPlansIsAnErrorNotEmpty() {
        XCTAssertThrowsError(try plans(#"{"error":"x"}"#))
        XCTAssertEqual(try plans(#"{"plans":[]}"#), [])
    }

    /// 送る形はサーバーが読む形（`kind` と鍵）。**無い欄は送らない**
    func testEncodesItemsTheWayTheServerReads() throws {
        let day = TripDay(items: [.spot(spotId: "sp_1", note: nil), .location(slug: "パリ", note: "夜")])
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder.api.encode(day)) as? [String: Any])
        XCTAssertNil(json["date"], "無い日付を null で送っている")
        let items = try XCTUnwrap(json["items"] as? [[String: String]])
        XCTAssertEqual(items[0], ["kind": "spot", "spotId": "sp_1"])
        XCTAssertEqual(items[1], ["kind": "location", "slug": "パリ", "note": "夜"])
    }

    // MARK: - 日付

    /// Web と同じ「2026年12月24日 〜 2026年12月25日」。片方だけならその1つ、無ければ nil
    func testPeriod() {
        XCTAssertEqual(TripPlanText.period(start: "2026-12-24", end: "2026-12-25"), "2026年12月24日 〜 2026年12月25日")
        XCTAssertEqual(TripPlanText.period(start: "2026-12-24", end: nil), "2026年12月24日")
        XCTAssertEqual(TripPlanText.period(start: nil, end: "2026-12-25"), "2026年12月25日")
        XCTAssertNil(TripPlanText.period(start: nil, end: nil))
        XCTAssertNil(TripPlanText.period(start: "壊れた値", end: ""), "読めない値を生のまま出している")
    }

    /// 日の見出し。**その日の日付 → 出発日から数える → 出さない** の順
    func testDayHeading() {
        let empty = TripDay()
        XCTAssertEqual(TripPlanText.dayHeading(index: 0, day: empty, start: "2026-12-24", end: "2026-12-25"),
                       "1 日目・2026年12月24日")
        XCTAssertEqual(TripPlanText.dayHeading(index: 1, day: empty, start: "2026-12-31", end: nil),
                       "2 日目・2027年1月1日", "年をまたいで数えられていない")
        XCTAssertEqual(TripPlanText.dayHeading(index: 2, day: empty, start: "2026-12-24", end: "2026-12-25"),
                       "3 日目", "帰着日を越えた日に日付を付けている")
        XCTAssertEqual(TripPlanText.dayHeading(index: 1, day: empty, start: "2026-12-24", end: "2026-12-25"),
                       "2 日目・2026年12月25日", "帰着日そのものに日付を付けていない")
        XCTAssertEqual(TripPlanText.dayHeading(index: 0, day: empty, start: nil, end: nil), "1 日目")
        XCTAssertEqual(TripPlanText.dayHeading(index: 0, day: TripDay(date: "2026-02-31"), start: nil, end: nil),
                       "1 日目", "実在しない日を出している")
        XCTAssertEqual(TripPlanText.dayHeading(index: 0, day: TripDay(date: "2026-11-03"), start: "2026-12-24", end: nil),
                       "1 日目・2026年11月3日", "その日が持っている日付より数えた日付を優先している")
    }

    /// 実在しない日は日付にしない（2月30日を3月2日に繰り上げない）
    func testImpossibleDateIsNotADate() {
        XCTAssertNil(TripPlanText.date(fromYMD: "2026-02-30"))
        XCTAssertNil(TripPlanText.pickerDate(fromYMD: "2026-02-30", in: TimeZone(identifier: "Asia/Tokyo")!),
                     "ピッカーに3月2日として渡している")
        XCTAssertNotNil(TripPlanText.date(fromYMD: "2028-02-29"))
    }

    /// **ピッカーの日は端末のゾーンで読む。** 東京の朝に選んだ 12月24日を、
    /// UTC で読んで 12月23日として送らない
    func testPickedDateKeepsTheLocalDay() throws {
        let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let picked = try XCTUnwrap(TripPlanText.pickerDate(fromYMD: "2026-12-24", in: tokyo))
        XCTAssertEqual(TripPlanText.ymd(pickedIn: tokyo, picked), "2026-12-24")
        // 東京 12月24日 06:00 は UTC では 12月23日
        var c = Calendar(identifier: .gregorian); c.timeZone = tokyo
        let morning = try XCTUnwrap(c.date(from: DateComponents(year: 2026, month: 12, day: 24, hour: 6)))
        XCTAssertEqual(TripPlanText.ymd(pickedIn: tokyo, morning), "2026-12-24")
    }

    // MARK: - 数

    /// 副文は**聞けたときだけ数**。聞けていなければ説明文
    func testListSubtitle() {
        XCTAssertEqual(TripPlanText.listSubtitle(count: 4), "旅行プラン 4 件")
        XCTAssertEqual(TripPlanText.listSubtitle(count: nil), "行きたい場所を、いつ・どの順で回るかに並べる。")
    }

    // MARK: - 行きたい場所から選ぶ

    private func spot(_ slug: String, name: String, prefecture: String? = nil) throws -> OfficialSpot {
        let region = prefecture.map { ",\"region\":{\"prefecture\":\"\($0)\"}" } ?? ""
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(
            "{\"spotId\":\"sp_\(slug)\",\"slug\":\"\(slug)\",\"name\":\"\(name)\",\"stage\":\"review\"\(region)}".utf8))
    }

    private func photo(_ id: String, location: String) throws -> Photo {
        try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\",\"location\":\"\(location)\",\"createdAt\":\"2026-01-01T00:00:00Z\"}".utf8))
    }

    /// 候補は**保存済みの行きたい場所だけ**。スポットは索引で `spotId` を引けたものだけ、
    /// 撮影地はいまの写真に在る地点だけ。スポットが先
    func testChoicesComeOnlyFromTheWishlist() throws {
        let index = [try spot("takaya-jinja", name: "高屋神社", prefecture: "香川県"),
                     try spot("not-saved", name: "保存していない")]
        let places = DerivedSpot.all(in: [try photo("a", location: "金沢"), try photo("b", location: "福井")])
        let kanazawa = try XCTUnwrap(places.first { $0.label == "金沢" })
        let keys: Set<String> = ["SPOT-takaya-jinja", "SPOT-missing-from-index", kanazawa.slug, "写真に無い地点"]

        let choices = TripPlanText.choices(wishlistKeys: keys, places: places, index: index)
        XCTAssertEqual(choices.map(\.name), ["高屋神社", "金沢"])
        XCTAssertEqual(choices[0].item, .spot(spotId: "sp_takaya-jinja", note: nil), "slug ではなく台帳の鍵で入れる")
        XCTAssertEqual(choices[0].regionLabel, "香川県")
        XCTAssertTrue(choices[0].isOfficial)
        XCTAssertEqual(choices[1].item, .location(slug: kanazawa.slug, note: nil))
        XCTAssertFalse(choices[1].isOfficial)
    }

    /// **同じスラッグの撮影地は1件**（綴りの揺れで2つの地点が同じ鍵になる）
    func testSameSlugAppearsOnce() throws {
        let places = DerivedSpot.all(in: [try photo("a", location: "Paris, France"),
                                          try photo("b", location: "Paris,  France")])
        let slugs = Set(places.map(\.slug))
        XCTAssertEqual(slugs.count, 1, "前提: 2つの綴りが同じスラッグになる")
        XCTAssertEqual(places.count, 2, "前提: 地点は2つある")
        let choices = TripPlanText.choices(wishlistKeys: slugs, places: places, index: [])
        XCTAssertEqual(choices.count, 1)
        XCTAssertEqual(Set(choices.map(\.id)).count, choices.count, "同じ id が2つ（ForEach で行が重なる）")
    }

    /// 何も保存していなければ候補は0（画面は「先に保存してください」を出す）
    func testNoWishlistNoChoices() throws {
        let places = DerivedSpot.all(in: [try photo("a", location: "金沢")])
        XCTAssertTrue(TripPlanText.choices(wishlistKeys: [], places: places, index: []).isEmpty)
    }

    /// 項目の名前。**引けなければ鍵をそのまま**（「不明な場所」を作らない）
    func testItemLabel() throws {
        let index = [try spot("takaya-jinja", name: "高屋神社")]
        let places = DerivedSpot.all(in: [try photo("a", location: "金沢")])
        let kanazawa = try XCTUnwrap(places.first)
        XCTAssertEqual(TripPlanText.label(for: .spot(spotId: "sp_takaya-jinja", note: nil), index: index, places: places), "高屋神社")
        XCTAssertEqual(TripPlanText.label(for: .spot(spotId: "sp_gone", note: nil), index: index, places: places), "sp_gone")
        XCTAssertEqual(TripPlanText.label(for: .location(slug: kanazawa.slug, note: nil), index: index, places: places), "金沢")
        XCTAssertEqual(TripPlanText.label(for: .location(slug: "%E3%83%91%E3%83%AA", note: nil), index: [], places: []), "パリ")
    }

    // MARK: - 保存

    private let base = TripPlan(planId: "p1", title: "冬", startDate: "2026-12-24", endDate: nil,
                                days: [TripDay(items: [.location(slug: "金沢", note: nil)])])

    /// 変えていなければ押させない。**空の日付と無い日付は同じ**
    func testDirty() {
        XCTAssertFalse(TripPlanText.isDirty(plan: base, days: base.days, start: "2026-12-24", end: ""))
        XCTAssertTrue(TripPlanText.isDirty(plan: base, days: base.days + [TripDay()], start: "2026-12-24", end: nil))
        XCTAssertTrue(TripPlanText.isDirty(plan: base, days: base.days, start: nil, end: nil))
    }

    /// **変えた項目だけ送る。** 日付を消したときは空文字（サーバーが消す）
    func testPatchSendsOnlyWhatChanged() {
        XCTAssertEqual(TripPlanText.patch(plan: base, days: base.days, start: "2026-12-24", end: nil),
                       TripPlanService.Patch())
        XCTAssertEqual(TripPlanText.patch(plan: base, days: base.days, start: nil, end: "2026-12-26"),
                       TripPlanService.Patch(startDate: "", endDate: "2026-12-26"))
        let more = base.days + [TripDay()]
        XCTAssertEqual(TripPlanText.patch(plan: base, days: more, start: "2026-12-24", end: nil),
                       TripPlanService.Patch(days: more))
    }

    // MARK: - 通信

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

    private func service() -> TripPlanService {
        TripPlanService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                       tokenProvider: StubTokenProvider(token: "T"), session: session))
    }

    /// 道と方法が Web と同じ。**書き込みの応答（書いたあとの一覧）をそのまま返す**
    func testServiceUsesTheWebEndpoints() async throws {
        let after = #"{"plans":[{"planId":"4f0c2b1e-8a3d-4c5e-9f10-2b3c4d5e6f70","title":"冬","days":[]}]}"#
        StubProtocol.respond(status: 200, body: after)

        _ = try await service().list()
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/user/trips")

        let created = try await service().create(title: "冬")
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/user/trips")
        XCTAssertEqual(created.map(\.planId), ["4f0c2b1e-8a3d-4c5e-9f10-2b3c4d5e6f70"])

        // プランの ID はサーバーが `randomUUID()` で作る（記号を含まない）
        _ = try await service().update(planId: "4f0c2b1e-8a3d-4c5e-9f10-2b3c4d5e6f70", TripPlanService.Patch(endDate: ""))
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "PUT")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.absoluteString, "https://api.example.test/user/trips/4f0c2b1e-8a3d-4c5e-9f10-2b3c4d5e6f70")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(StubProtocol.lastBody)) as? [String: Any])
        XCTAssertEqual(body.keys.sorted(), ["endDate"], "変えていない項目まで送っている")

        _ = try await service().delete(planId: "4f0c2b1e-8a3d-4c5e-9f10-2b3c4d5e6f70")
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/user/trips/4f0c2b1e-8a3d-4c5e-9f10-2b3c4d5e6f70")
    }

    /// **上限で断られたら、サーバーの言い分をそのまま出す**（「保存に失敗しました」に潰さない）
    func testLimitRefusalKeepsTheServerMessage() async {
        // サーバーは上限を **403** で返す（`tripPlans.ts` の `jsonError(403, e.reason)`）
        StubProtocol.respond(status: 403, body: #"{"error":"この旅程はこれ以上増やせません"}"#)
        do {
            _ = try await service().update(planId: "p1", TripPlanService.Patch(days: []))
            XCTFail("投げるはず")
        } catch {
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "この旅程はこれ以上増やせません",
                           "上限の断り文を「権限がありません」に置き換えている")
        }
        // 作るときも同じ（51件目）
        StubProtocol.respond(status: 403, body: #"{"error":"旅行プランは50個までです"}"#)
        do {
            _ = try await service().create(title: "x")
            XCTFail("投げるはず")
        } catch {
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "旅行プランは50個までです")
        }
    }

    /// **本文の無い 403**（API Gateway の門前払い）は今まで通り権限の文
    func testBare403StaysAPermissionError() async {
        StubProtocol.respond(status: 403, body: #"{"message":"Forbidden"}"#)
        do {
            _ = try await service().create(title: "x")
            XCTFail("投げるはず")
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 403, message: ""))
        }
    }
}
