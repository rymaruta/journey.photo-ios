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
        XCTAssertEqual(TripAIText.defaultTitle(place: "金沢", days: 2), L("金沢の旅", "金沢 trip"))
        XCTAssertEqual(TripAIText.defaultTitle(place: "金沢", days: 1), L("金沢の日帰り", "金沢 day trip"))
    }

    /// 画面の文に「・」「·」の区切りと「撮りどき」「捨てる」を使わない（CLAUDE.md の言葉の決まり）
    func testWordingRules() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for file in ["Core/Text/TripAI.swift", "Core/Text/TripAIAsk.swift", "Features/Trips/AI/TripAIViews.swift",
                     "Features/Trips/AI/TripAICard.swift", "Features/Trips/AI/TripAIJobs.swift", "Features/Trips/AI/TripAIRunner.swift"] {
            let src = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + file), encoding: .utf8)
            let shown = src.components(separatedBy: "L(\"").dropFirst().map { $0.components(separatedBy: "\"").first ?? "" }
            XCTAssertFalse(shown.isEmpty, file)
            for text in shown {
                XCTAssertFalse(text.contains("・") || text.contains("·"), "\(file): \(text)")
                XCTAssertFalse(text.contains("撮りどき") || text.contains("捨てる"), "\(file): \(text)")
            }
        }
    }

    // MARK: - 頼む札（行き先・日数・好み）

    func testAskReadsSlotsAndLeavesMissingOnesEmpty() throws {
        let rows = try ledger()
        let a = TripAIAsk.reading("来月、金沢に1泊2日。紅葉", spots: rows)
        XCTAssertEqual(a.place, "金沢")
        XCTAssertEqual(a.prefectures, ["石川県"])
        XCTAssertEqual(a.days, 2)
        XCTAssertEqual(a.preference, "紅葉")
        XCTAssertTrue(a.isComplete)
        // 読めなかった札は空（光らせて選ばせる）。この回は AI を呼ばない
        let b = TripAIAsk.reading("どこか静かなところ", spots: rows)
        XCTAssertFalse(b.hasPlace)
        XCTAssertNil(b.days)
        XCTAssertFalse(b.isComplete)
        XCTAssertEqual(TripAIAsk.daysLabel(1), L("日帰り", "Day trip"))
        XCTAssertEqual(TripAIAsk.daysLabel(2), L("1泊2日", "2 days"))
        var c = a
        c.extra = "ゆっくり"
        XCTAssertEqual(c.requestText, L("金沢、1泊2日、紅葉、ゆっくり", "金沢、2 days、紅葉、ゆっくり"))
    }

    // MARK: - 一覧の札（決まった手順・AI は使わない）

    func testSuggestionsComeFromWishlistPrefectureWithThreeOrMore() throws {
        let rows = try ledger()
        let wished: Set<String> = ["sp_kenrokuen", "sp_kanazawa-castle", "sp_higashi-chaya", "sp_owakudani"]
        let november = Date(timeIntervalSince1970: 1_794_700_000)   // 2026-11
        let cards = TripAISuggestion.make(spots: rows, wishlist: wished, now: november)
        let first = try XCTUnwrap(cards.first)
        XCTAssertEqual(first.kind, .wishlist)
        XCTAssertEqual(first.ask.prefectures, ["石川県"])
        XCTAssertEqual(first.ask.place, "金沢", "半分以上が同じ市なら市の名前")
        XCTAssertEqual(Set(first.ask.mustSpotIds), ["sp_kenrokuen", "sp_kanazawa-castle", "sp_higashi-chaya"])
        XCTAssertFalse(first.title.contains("・"))
        // 神奈川は1か所だけなので札にしない
        XCTAssertFalse(cards.contains { $0.ask.prefectures == ["神奈川県"] && $0.kind == .wishlist })
        XCTAssertLessThanOrEqual(cards.count, 2)
        XCTAssertTrue(TripAISuggestion.make(spots: rows, wishlist: [], now: november).allSatisfy { $0.kind == .season })
    }

    // MARK: - 行き先はおまかせ（2026-11-23 owner「めんどいから行き先指定なしでも作れるようにして」）

    /// 決め方の順: 頼みの文の地名 → 行きたい場所の多い県 → 今の季節の案内が多い県 → 載っている数が多い県
    func testAutoPlaceOrder() throws {
        let november = Date(timeIntervalSince1970: 1_794_700_000)   // 2026-11
        let rows = [
            try spot("a1", prefecture: "石川県", seasons: ["autumn"]),
            try spot("b1", prefecture: "香川県"), try spot("b2", prefecture: "香川県"),
            try spot("c1", prefecture: "長野県"), try spot("c2", prefecture: "長野県"), try spot("c3", prefecture: "長野県"),
            try spot("d1", prefecture: "京都府", seasons: ["spring"]),
        ]
        // 1. 頼みの文に地名があればそれ（行きたい場所より先）
        let text = try XCTUnwrap(TripAIAutoPlace.choose(text: "香川でうどん", spots: rows, wishlist: ["sp_c1"], now: november))
        XCTAssertEqual(text.source, .text)
        XCTAssertEqual(text.prefectures, ["香川県"])
        // 2. 行きたい場所の多い県
        let wished = try XCTUnwrap(TripAIAutoPlace.choose(text: "", spots: rows, wishlist: ["sp_b1", "sp_b2", "sp_a1"], now: november))
        XCTAssertEqual(wished.source, .wishlist)
        XCTAssertEqual(wished.prefectures, ["香川県"])
        XCTAssertEqual(wished.place, "香川")
        // 3. 今の季節（11月は秋）の案内がある観光スポットが多い県（春の京都は数えない）
        let season = try XCTUnwrap(TripAIAutoPlace.choose(text: "", spots: rows, wishlist: [], now: november))
        XCTAssertEqual(season.source, .season)
        XCTAssertEqual(season.prefectures, ["石川県"])
        // 4. どれも無ければ、載っている数が多い県
        let plain = rows.filter { $0.seasonKeys.isEmpty }
        let popular = try XCTUnwrap(TripAIAutoPlace.choose(text: "", spots: plain, wishlist: [], now: november))
        XCTAssertEqual(popular.source, .popular)
        XCTAssertEqual(popular.prefectures, ["長野県"])
        // 台帳が空なら決めない（行き先の札を開く）
        XCTAssertNil(TripAIAutoPlace.choose(text: "", spots: [], wishlist: [], now: november))
    }

    /// 行き先なしで押せる: 行き先が空でも日数があれば、アプリが行き先を埋めて作れる形になる。選んだ行き先は替えない
    func testAskWithoutPlaceBecomesComplete() throws {
        let november = Date(timeIntervalSince1970: 1_794_700_000)
        let rows = [try spot("c1", prefecture: "長野県"), try spot("b1", prefecture: "香川県", seasons: ["autumn"])]
        let empty = TripAIAsk(place: "", prefectures: [], cities: [], days: 2, preference: nil)
        XCTAssertFalse(empty.isComplete)
        let made = empty.withAutoPlace(spots: rows, wishlist: [], now: november)
        XCTAssertTrue(made.isComplete)
        XCTAssertTrue(made.autoPlaced)
        XCTAssertEqual(made.prefectures, ["香川県"])
        XCTAssertTrue(made.requestText.hasPrefix("香川"), "AI に渡す文に行き先が入っていない（サーバーの道）")
        let chosen = TripAIAsk(place: "長野", prefectures: ["長野県"], cities: [], days: 2, preference: nil)
        let kept = chosen.withAutoPlace(spots: rows, wishlist: [], now: november)
        XCTAssertEqual(kept, chosen)
        XCTAssertFalse(kept.autoPlaced)
    }

    /// 作ったプランの上の1行
    func testAutoPlaceLine() {
        XCTAssertEqual(TripAIAutoPlace.line(place: "香川"), L("行き先はおまかせで、香川にしました", "No place chosen, so we picked 香川"))
        XCTAssertFalse(TripAIAutoPlace.line(place: "香川").contains("・"))
        XCTAssertEqual(TripAIAutoPlace.slotLabel, L("おまかせ", "Any"))
    }

    /// 頼みのシート: 行き先の札は既定で「おまかせ」（真鍮で光らせない）、押したら行き先を埋めてから作る。
    /// 作った行き先は控え（`TripAINote.autoPlace`）に残り、作っている画面とできたプランの上に1行出す
    func testAskSheetStartsWithoutPlace() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let read: (String) throws -> String = { try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }
        let views = try read("Sources/JourneyPhoto/Features/Trips/AI/TripAIViews.swift")
        XCTAssertTrue(views.contains("ask.hasPlace ? ask.place : TripAIAutoPlace.slotLabel"))
        XCTAssertTrue(views.contains("let made = ask.withAutoPlace(spots: index, wishlist: wishlist)"))
        XCTAssertTrue(views.contains("start(made)"))
        XCTAssertFalse(views.contains("if !ask.hasPlace { editing = .place }"), "開いたときに行き先を選ばせている")
        XCTAssertTrue(views.contains("if job.ask.autoPlaced {"))
        let jobs = try read("Sources/JourneyPhoto/Features/Trips/AI/TripAIJobs.swift")
        XCTAssertTrue(jobs.contains("autoPlace: job.ask.autoPlaced ? job.ask.place : nil"))
        let detail = try read("Sources/JourneyPhoto/Features/Trips/TripPlanDetailView.swift")
        XCTAssertTrue(detail.contains("if let place = aiNotes.note(planId)?.autoPlace {"))
        XCTAssertTrue(detail.contains("autoPlace: note.autoPlace"), "組み直しで1行が消える")
        // 行きたい場所を両方の入口から渡す
        XCTAssertTrue(try read("Sources/JourneyPhoto/Features/Trips/TripPlansView.swift").contains("wishlist: wishlist.spotIds)"))
        XCTAssertTrue(try read("Sources/JourneyPhoto/Features/Search/AskScreen.swift").contains("index: index, wishlist: wishlist.spotIds)"))
    }

    // MARK: - 替える（AI を使わない）

    func testSwapOffersNearestUnusedCandidates() throws {
        let rows = try ledger()
        let ken = try XCTUnwrap(rows.first { $0.slug == "kenrokuen" })
        let pool = rows.filter { $0.region?.prefecture == "石川県" }
        let choices = TripAISwap.choices(for: ken, candidates: pool, used: ["sp_kenrokuen", "sp_kanazawa-castle"])
        XCTAssertEqual(choices.first?.slug, "higashi-chaya", "いちばん近い残り")
        XCTAssertFalse(choices.contains { $0.slug == "kanazawa-castle" }, "日程に入っている所は出さない")
        XCTAssertLessThanOrEqual(choices.count, 3)
    }

    // MARK: - 組む手順（見本のサーバー・1日目から順に出す）

    @MainActor
    func testRunnerFillsDaysInOrderAndLogsTimes() async throws {
        UserDefaults.standard.set(true, forKey: TripAIFixture.key)
        UserDefaults.standard.set(0.0, forKey: TripAIFixture.delayKey)
        defer {
            UserDefaults.standard.removeObject(forKey: TripAIFixture.key)
            UserDefaults.standard.removeObject(forKey: TripAIFixture.delayKey)
        }
        let runner = TripAIRunner(onDevice: false)
        let ask = TripAIAsk.reading("金沢に1泊2日", spots: try ledger())
        let index = try ledger()
        let built = await runner.build(ask, index: index, wishlist: [], offline: false,
                                       service: TripAIService(api: Self.api())) { _, _ in 10 }
        let result = try XCTUnwrap(built)
        XCTAssertEqual(result.mode, .ai)
        XCTAssertEqual(result.days.count, 2)
        XCTAssertEqual(runner.readyDays.count, 2, "できた日を1日目から出している")
        XCTAssertNotNil(runner.firstDaySeconds)
        XCTAssertNotNil(runner.allDaysSeconds)
        XCTAssertLessThanOrEqual(runner.firstDaySeconds ?? 99, runner.allDaysSeconds ?? 0)
        XCTAssertEqual(runner.step, .done)
        XCTAssertFalse(result.candidates.isEmpty)
    }

    @MainActor
    func testRunnerWithoutAIWhenUsedUpOrSilent() async throws {
        let rows = try ledger()
        let ask = TripAIAsk.reading("金沢で日帰り", spots: rows)
        // 使い切った: AI を呼ばずに AI なしで組む（行き止まりにしない）
        let used = TripAIRunner(onDevice: false)
        used.setUsage(.init(tier: "free", used: 30, limit: 30, remaining: 0, resetsOn: "2026-12-01", countsDevice: true))
        let b1 = await used.build(ask, index: rows, wishlist: [], offline: false, service: TripAIService(api: Self.api())) { _, _ in 10 }
        let r1 = try XCTUnwrap(b1)
        XCTAssertEqual(r1.mode, .usedUp)
        XCTAssertEqual(r1.days.count, 1)
        XCTAssertFalse(r1.reason.isEmpty, "AI なしの1文を出す")
        // 圏外で端末の AI も無い: AI なし
        let off = TripAIRunner(onDevice: false)
        let b2 = await off.build(ask, index: rows, wishlist: [], offline: true, service: TripAIService(api: Self.api())) { _, _ in 10 }
        let r2 = try XCTUnwrap(b2)
        XCTAssertEqual(r2.mode, .offline)
        // 行き先の無い頼みは組まない（回数に数えない）
        let none = TripAIRunner(onDevice: false)
        let b3 = await none.build(TripAIAsk.reading("どこか静かなところ", spots: rows), index: rows, wishlist: [], offline: false,
                                  service: TripAIService(api: Self.api())) { _, _ in nil }
        XCTAssertNil(b3)
    }

    func testFailureLines() {
        XCTAssertTrue(TripAIJobText.failureLine(.offline, title: "金沢の旅").contains("電波"))
        XCTAssertFalse(TripAIJobText.failureLine(.save("x"), title: "金沢の旅").contains("・"))
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
