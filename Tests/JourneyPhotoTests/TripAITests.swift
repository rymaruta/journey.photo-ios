import XCTest
@testable import JourneyPhoto

/// AI で旅行プランを作る（札 #621）の、画面を持たない決まり。
/// 30件の試験（2026-11-15）で使った頼みの文から、日数と行き先の読み取りを縛る
final class TripAITests: XCTestCase {

    // MARK: - 台帳の行

    private func spot(_ slug: String, name: String? = nil, prefecture: String, city: String? = nil,
                      lat: Double = 35, lng: Double = 135, category: String = "寺社",
                      seasons: [String] = [], times: [String] = [], aliases: [String] = []) throws -> OfficialSpot {
        var fields = ["\"spotId\":\"sp_\(slug)\"", "\"slug\":\"\(slug)\"", "\"name\":\"\(name ?? slug)\"", "\"stage\":\"published\"",
                      "\"category\":\"\(category)\"", "\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}"]
        var region = ["\"prefecture\":\"\(prefecture)\""]
        if let city { region.append("\"city\":\"\(city)\"") }
        fields.append("\"region\":{\(region.joined(separator: ","))}")
        let list: ([String]) -> String = { "[" + $0.map { "\"\($0)\"" }.joined(separator: ",") + "]" }
        if !seasons.isEmpty { fields.append("\"seasons\":\(list(seasons))") }
        if !times.isEmpty { fields.append("\"times\":\(list(times))") }
        if !aliases.isEmpty { fields.append("\"aliases\":\(list(aliases))") }
        var row = try JSONDecoder.api.decode(OfficialSpot.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
        row.isIndexOnly = true
        return row
    }

    private func ledger() throws -> [OfficialSpot] {
        [
            try spot("kenrokuen", name: "兼六園", prefecture: "石川県", city: "金沢市", lat: 36.56, lng: 136.66, category: "庭園",
                     seasons: ["autumn", "winter"], times: ["morning"]),
            try spot("kanazawa-castle", name: "金沢城公園", prefecture: "石川県", city: "金沢市", lat: 36.56, lng: 136.66, category: "城跡",
                     times: ["goldenHour"]),
            try spot("higashi-chaya", name: "ひがし茶屋街", prefecture: "石川県", city: "金沢市", lat: 36.57, lng: 136.67, category: "町並み",
                     times: ["dawn", "morning"]),
            try spot("rokkozaki", name: "禄剛埼灯台", prefecture: "石川県", city: "珠洲市", lat: 37.53, lng: 137.33, category: "灯台"),
            try spot("notojima", name: "能登島", prefecture: "石川県", city: "七尾市", lat: 37.12, lng: 136.98, category: "島"),
            try spot("owakudani", name: "大涌谷", prefecture: "神奈川県", city: "足柄下郡箱根町", lat: 35.24, lng: 139.02, category: "山岳"),
            try spot("sapporo-tower", name: "さっぽろテレビ塔", prefecture: "北海道", city: "札幌市中央区", lat: 43.06, lng: 141.35, category: "展望台"),
            try spot("saiko", name: "富士五湖 西湖", prefecture: "山梨県", city: "南都留郡富士河口湖町", lat: 35.5, lng: 138.68, category: "湖沼"),
            try spot("takayama", name: "高山 古い町並", prefecture: "岐阜県", city: "高山市", lat: 36.14, lng: 137.26, category: "町並み"),
            try spot("takayama2", name: "高山陣屋", prefecture: "岐阜県", city: "高山市", lat: 36.14, lng: 137.26, category: "史跡"),
            try spot("takayama-gunma", name: "群馬の村", prefecture: "群馬県", city: "吾妻郡高山村", lat: 36.6, lng: 138.9, category: "高原"),
            try spot("koriyama", name: "開成山", prefecture: "福島県", city: "郡山市", lat: 37.4, lng: 140.36, category: "公園"),
        ]
    }

    // MARK: - 上限（owner 2026-11-15）

    func testLimitsMatchServer() {
        XCTAssertEqual(TripAILimits.free, 30)
        XCTAssertEqual(TripAILimits.pro, 300)
        XCTAssertEqual(TripAILimits.admin, 300)
        XCTAssertEqual(TripAILimits.maxCandidates, 20)
    }

    // MARK: - 日数（30件の試験の文）

    func testDaysFromTrialSentences() {
        let cases: [(String, Int?)] = [
            ("来月、金沢に1泊2日。紅葉", 2), ("今週末の日帰りで鎌倉", 1), ("秋の京都を2泊3日でゆっくり", 3),
            ("奈良で半日だけ", 1), ("雨の日でも楽しめる東京の1日", 1), ("子連れで沖縄3日間", 3), ("夏休みに北海道を4泊5日", 5),
            ("箱根に一泊して温泉", 2), ("夜景がきれいな函館に1泊", 2), ("広島と宮島を2日で", 2), ("出雲大社へ一泊二日", 2),
            ("夏に青森を2泊", 3), ("輪島と能登を3日かけて", 3), ("横浜を夕方から", nil), ("京都で写真を撮りたい。朝と夕方、2日", 2),
            ("沖縄で１０日", 7),
        ]
        for (text, want) in cases { XCTAssertEqual(TripAIDays.parse(text), want, text) }
    }

    // MARK: - 行き先

    func testCityKeys() {
        XCTAssertEqual(TripAIDestination.cityKeys("足柄下郡箱根町"), ["箱根町", "箱根"])
        XCTAssertEqual(TripAIDestination.cityKeys("札幌市中央区"), ["札幌市", "札幌"])
        // 郡の中は町と村だけ。「郡山市」の郡は名前の一部
        XCTAssertEqual(TripAIDestination.cityKeys("郡山市"), ["郡山市", "郡山"])
        XCTAssertEqual(TripAIDestination.cityKeys("大和郡山市"), ["大和郡山市", "大和郡山"])
    }

    func testDestinationReadsCitiesTownsAndSpotParts() throws {
        let rows = try ledger()
        XCTAssertEqual(TripAIDestination.match("来月、金沢に1泊2日。紅葉", spots: rows)?.prefectures, ["石川県"])
        XCTAssertEqual(TripAIDestination.match("箱根に一泊して温泉", spots: rows)?.prefectures, ["神奈川県"])
        XCTAssertEqual(TripAIDestination.match("冬の札幌に2日、雪を見たい", spots: rows)?.prefectures, ["北海道"])
        XCTAssertEqual(TripAIDestination.match("富士山が見える河口湖で1泊2日", spots: rows)?.prefectures, ["山梨県"])
        XCTAssertEqual(TripAIDestination.match("輪島と能登を3日かけて", spots: rows)?.prefectures, ["石川県"])
        XCTAssertEqual(TripAIDestination.match("郡山で1日", spots: rows)?.prefectures, ["福島県"])
        XCTAssertNil(TripAIDestination.match("どこか静かなところ", spots: rows))
    }

    /// 同じ市の名前が複数の県にあれば、台帳の件数が多い県を先に（高山 → 岐阜県）
    func testAmbiguousCityPrefersBiggerLedger() throws {
        let m = try XCTUnwrap(TripAIDestination.match("高山と白川郷を1泊2日", spots: try ledger()))
        XCTAssertEqual(m.prefectures.first, "岐阜県")
        XCTAssertTrue(m.cities.contains("高山市"))
    }

    // MARK: - 候補

    func testCandidatesStayInDestinationAndPreferCityAndSeason() throws {
        let rows = try ledger()
        let m = try XCTUnwrap(TripAIDestination.match("来月、金沢に1泊2日。紅葉", spots: rows))
        let picked = TripAICandidates.pick(text: "来月、金沢に1泊2日。紅葉", match: m, spots: rows, wishlist: [])
        XCTAssertTrue(picked.allSatisfy { $0.region?.prefecture == "石川県" })
        XCTAssertEqual(picked.first?.slug, "kenrokuen", "金沢市で秋の案内がある所が先")
        XCTAssertEqual(Set(picked.prefix(3).map(\.slug)), ["kenrokuen", "kanazawa-castle", "higashi-chaya"])
        XCTAssertLessThanOrEqual(TripAICandidates.pick(text: "金沢", match: m, spots: rows, wishlist: [], limit: 2).count, 2)
    }

    // MARK: - AI の答えを確かめる

    func testSanitizedDropsUnknownAndDuplicateNumbers() throws {
        let raw = TripAIPlan(title: " 秋の金沢 ", days: 4, stops: [.init(n: 1, day: 1), .init(n: 99, day: 1), .init(n: 1, day: 2),
                                                                 .init(n: 0, day: 1), .init(n: 3, day: 9)], reason: "朝に向く所を先に")
        let plan = try XCTUnwrap(raw.sanitized(candidateCount: 5, fixedDays: 2))
        XCTAssertEqual(plan.stops, [.init(n: 1, day: 1), .init(n: 3, day: 2)])
        XCTAssertEqual(plan.days, 2, "アプリが読んだ日数を先に使う")
        XCTAssertEqual(plan.dropped, 3)
        XCTAssertEqual(plan.title, "秋の金沢")
        XCTAssertNil(TripAIPlan(title: "", days: 1, stops: [.init(n: 9, day: 1)], reason: "").sanitized(candidateCount: 3, fixedDays: nil))
    }

    func testReasonWithOutsidePrefectureIsHidden() throws {
        let rows = Array(try ledger().prefix(3))
        let plan = TripAIPlan(title: "", days: 1, stops: [.init(n: 1, day: 1)], reason: "京都の寺を回ります")
        XCTAssertEqual(plan.reasonChecked(against: rows), "")
        let ok = TripAIPlan(title: "", days: 1, stops: [.init(n: 1, day: 1)], reason: "石川の庭園を朝に")
        XCTAssertEqual(ok.reasonChecked(against: rows), "石川の庭園を朝に")
    }

    func testDayListsKeepsAIOrderAndSkipsEmptyDays() throws {
        let rows = Array(try ledger().prefix(3))
        let plan = TripAIPlan(title: "", days: 3, stops: [.init(n: 3, day: 1), .init(n: 1, day: 1), .init(n: 2, day: 3)], reason: "")
        XCTAssertEqual(plan.dayLists(rows).map { $0.map(\.slug) }, [["higashi-chaya", "kenrokuen"], ["kanazawa-castle"]])
    }

    func testFallbackUsesOnlyCandidatesWithinDays() throws {
        let rows = try ledger().filter { $0.region?.prefecture == "石川県" }
        let plan = TripAIFallback.plan(candidates: rows, days: 2, title: "石川の2日")
        XCTAssertFalse(plan.stops.isEmpty)
        XCTAssertTrue(plan.stops.allSatisfy { (1...rows.count).contains($0.n) && (1...2).contains($0.day) })
        XCTAssertEqual(Set(plan.stops.map(\.n)).count, plan.stops.count)
    }

    // MARK: - 移動が無理な日（Apple の地図の目安の代わりに決まった分を返す）

    func testRouteCheckRemovesFarthestWhenDayIsOverFourHours() async throws {
        let rows = try ledger()
        let kanazawa = rows.filter { $0.region?.city == "金沢市" }
        let suzu = try XCTUnwrap(rows.first { $0.slug == "rokkozaki" })
        // 金沢の中は 10 分、珠洲（能登の先）とは 150 分
        let eta: TripAIRouteCheck.ETA = { a, b in
            let far = abs(a.lat - b.lat) > 0.5
            return far ? 150 : 10
        }
        let day = [kanazawa[0], suzu, kanazawa[1], kanazawa[2]]
        let result = await TripAIRouteCheck.trim([day], eta: eta)
        XCTAssertEqual(result.days.first?.map(\.slug), ["kenrokuen", "kanazawa-castle", "higashi-chaya"])
        XCTAssertEqual(result.removed.map(\.spot.slug), ["rokkozaki"])
        XCTAssertEqual(result.removed.first?.minutes, 310)

        // 4時間以内なら外さない・測れない区間は 0 分として外さない
        let calm = await TripAIRouteCheck.trim([kanazawa], eta: eta)
        XCTAssertTrue(calm.removed.isEmpty)
        let unknown = await TripAIRouteCheck.trim([day]) { _, _ in nil }
        XCTAssertTrue(unknown.removed.isEmpty)
    }

    // MARK: - 言葉

    func testRemainingLineAndReset() {
        XCTAssertEqual(TripAIText.monthDay("2026-12-01"), L("12月1日", "12/1"))
        XCTAssertTrue(TripAIText.remainingLine(remaining: 3, resetsOn: "2026-12-01").contains("3"))
        XCTAssertTrue(TripAIText.nextReset(now: Date(timeIntervalSince1970: 1_795_000_000)).hasSuffix("-01"))
        XCTAssertEqual(TripAIText.defaultTitle(prefecture: "石川県", days: 2), L("石川の2日", "2 days in 石川"))
    }

    /// 画面の文に「・」「·」の区切りと「撮りどき」を使わない（CLAUDE.md の言葉の決まり）
    func testWordingRules() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for file in ["Core/Text/TripAI.swift", "Features/Trips/AI/TripAIComposer.swift", "Features/Trips/AI/TripAICard.swift"] {
            let src = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + file), encoding: .utf8)
            let shown = src.components(separatedBy: "L(\"").dropFirst().map { $0.components(separatedBy: "\"").first ?? "" }
            for text in shown {
                XCTAssertFalse(text.contains("・") || text.contains("·"), "\(file): \(text)")
                XCTAssertFalse(text.contains("撮りどき") || text.contains("捨てる"), "\(file): \(text)")
            }
        }
    }

    // MARK: - 組む手順（見本のサーバー）

    @MainActor
    func testComposerUsesServerFixtureAndKeepsCandidateNumbers() async throws {
        UserDefaults.standard.set(true, forKey: TripAIFixture.key)
        defer { UserDefaults.standard.removeObject(forKey: TripAIFixture.key) }
        let model = TripAIComposerModel(onDevice: false)
        model.text = "来月、金沢に1泊2日。紅葉"
        let service = TripAIService(api: Self.api())
        let result = try await XCTUnwrapAsync(await model.send(index: try ledger(), wishlist: [], offline: false, service: service) { _, _ in 10 })
        XCTAssertEqual(result.title, TripAIText.defaultTitle(prefecture: "石川県", days: 2))
        XCTAssertEqual(result.days.count, 2)
        XCTAssertNil(result.fallbackNote)
        XCTAssertFalse(result.reason.isEmpty)
        XCTAssertEqual(model.phase, .idle)
    }

    @MainActor
    func testComposerOfflineWithoutDeviceAIPlansWithoutAI() async throws {
        let model = TripAIComposerModel(onDevice: false)
        model.text = "金沢で日帰り"
        let service = TripAIService(api: Self.api())
        let result = try await XCTUnwrapAsync(await model.send(index: try ledger(), wishlist: [], offline: true, service: service) { _, _ in 10 })
        XCTAssertNotNil(result.fallbackNote)
        XCTAssertEqual(result.days.count, 1)
        XCTAssertEqual(result.reason, "")
    }

    @MainActor
    func testComposerUnreadableDestinationIsNotSent() async throws {
        let model = TripAIComposerModel(onDevice: false)
        model.text = "どこか静かなところ"
        let service = TripAIService(api: Self.api())
        let result = await model.send(index: try ledger(), wishlist: [], offline: false, service: service) { _, _ in nil }
        XCTAssertNil(result)
        if case .unreadable = model.phase {} else { XCTFail("読めなかったのに \(model.phase)") }
    }

    // MARK: - Pro の案内

    func testProBenefitAndOrigin() {
        XCTAssertEqual(ProBenefit.all.first?.icon, .ai)
        XCTAssertEqual(PaywallOrigin.tripAI.leadingBenefit, .ai)
        XCTAssertTrue(ProBenefit.all.first?.body.contains("\(TripAILimits.pro)") == true)
    }

    /// 通信しない口（見本・圏外・読めない頼みの回だけで使う）
    private struct NoToken: TokenProviding {
        func idToken() async throws -> String? { nil }
        func accountGone(idToken: String) async {}
    }

    private static func api() -> APIClient {
        APIClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: NoToken())
    }

    private func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
        try XCTUnwrap(value, file: file, line: line)
    }
}
