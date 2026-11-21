import XCTest
@testable import JourneyPhoto

/// 旅行プランの着く時刻の目安（札 #677・案A・2026-11-21）と、AI の画面の流れの区間から経路を開く口（札 #677 の続き）
final class TripTimesTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func spot(_ slug: String, name: String, category: String?, lat: Double?, lng: Double?,
                      times: [String] = []) throws -> OfficialSpot {
        var fields = ["\"spotId\":\"sp_\(slug)\"", "\"slug\":\"\(slug)\"", "\"name\":\"\(name)\"", "\"stage\":\"published\"",
                      "\"region\":{\"prefecture\":\"東京都\",\"city\":\"港区\"}"]
        if let category { fields.append("\"category\":\"\(category)\"") }
        if let lat, let lng { fields.append("\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}") }
        if !times.isEmpty { fields.append("\"times\":[" + times.map { "\"\($0)\"" }.joined(separator: ",") + "]") }
        var row = try JSONDecoder.api.decode(OfficialSpot.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
        row.isIndexOnly = true
        return row
    }

    private func stop(_ name: String, stay: Int = 60, times: [String] = []) -> TripTimes.Stop {
        TripTimes.Stop(name: name, stay: stay, times: times)
    }

    // MARK: - 滞在の目安

    /// 索引（2026-11-21 に journey-photo.com の spot-feed/index.json で数えた 73 種類）を全部、表で振り分ける
    func testStayTableCoversEveryCategoryInTheIndex() {
        let index = ["寺社", "山岳", "町並み", "史跡", "島", "教会", "建築", "遺跡", "公園", "城", "博物館", "城跡", "海岸", "湖沼",
                     "寺院", "展望台", "美術館", "滝", "橋", "渓谷", "樹木", "庭園", "温泉", "宮殿", "産業遺産", "植物園", "火山", "岬",
                     "鉄道", "神社", "鍾乳洞", "水族館", "高原", "湿原", "広場", "棚田", "灯台", "劇場", "洞窟", "駅", "動物園", "森林",
                     "市場", "自然現象", "祭り", "アート", "農村", "動物", "峡谷", "湧水", "道路", "運河", "街並み", "湖", "渓流", "ダム",
                     "並木道", "仏像", "池", "砂丘", "草原", "火口湖", "港", "古道", "湾", "遊園地", "花園", "集落", "花畑", "農場",
                     "海峡", "街", "温泉街"]
        XCTAssertEqual(index.count, 73)
        let missing = index.filter { TripTimes.stayTable[$0] == nil }
        XCTAssertEqual(missing, [], "索引の種類が表に無い")
        // 模型の表: 寺 60、公園 90、駅舎 45、分からなければ 60
        XCTAssertEqual(TripTimes.stayMinutes(category: "寺社"), 60)
        XCTAssertEqual(TripTimes.stayMinutes(category: "神社"), 60)
        XCTAssertEqual(TripTimes.stayMinutes(category: "城"), 60)
        XCTAssertEqual(TripTimes.stayMinutes(category: "町並み"), 60)
        XCTAssertEqual(TripTimes.stayMinutes(category: "公園"), 90)
        XCTAssertEqual(TripTimes.stayMinutes(category: "美術館"), 90)
        XCTAssertEqual(TripTimes.stayMinutes(category: "展望台"), 90)
        XCTAssertEqual(TripTimes.stayMinutes(category: "山岳"), 90)
        XCTAssertEqual(TripTimes.stayMinutes(category: "駅"), 45)
        XCTAssertEqual(TripTimes.stayMinutes(category: "橋"), 45)
        XCTAssertEqual(TripTimes.stayMinutes(category: "建築"), 45)
        XCTAssertEqual(TripTimes.stayMinutes(category: nil), 60, "種類の無い所（撮影地）は 60 分")
        XCTAssertEqual(TripTimes.stayMinutes(category: ""), 60)
        XCTAssertEqual(TripTimes.stayMinutes(category: "知らない種類"), 60)
        // 表に無い新しい種類は字の中の言葉で
        XCTAssertEqual(TripTimes.stayMinutes(category: "駅舎"), 45)
        XCTAssertEqual(TripTimes.stayMinutes(category: "文学館"), 90)
    }

    // MARK: - 時刻を並べる

    func testScheduleAddsStayAndMove() {
        let day = TripTimes.schedule(start: 9 * 60, stops: [stop("浅草寺", stay: 60), stop("上野恩賜公園", stay: 90), stop("駅舎", stay: 45)],
                                     moves: [0, 15, 25], light: nil)
        XCTAssertEqual(day.rows.map(\.arrive), [540, 615, 730], "着く時刻 = 前に着いた時刻 + 滞在 + 移動")
        XCTAssertEqual(day.end, 775)
        XCTAssertEqual(day.rows.map { $0.arrive.map(TripTimes.clock) }, ["9:00", "10:15", "12:10"])
        XCTAssertEqual(TripTimes.endLine(775), "12:55ごろ 終わり")
    }

    func testChangingStartShiftsEveryTime() {
        let stops = [stop("a"), stop("b"), stop("c")]
        let nine = TripTimes.schedule(start: 9 * 60, stops: stops, moves: [0, 10, 20], light: nil)
        let eleven = TripTimes.schedule(start: 11 * 60, stops: stops, moves: [0, 10, 20], light: nil)
        XCTAssertEqual(zip(nine.rows, eleven.rows).map { ($1.arrive ?? 0) - ($0.arrive ?? 0) }, [120, 120, 120])
        XCTAssertEqual(TripTimes.startChoices.map(TripTimes.clock), ["7:00", "8:00", "9:00", "10:00", "11:00", "12:00"])
        XCTAssertEqual(TripTimes.defaultStart, 9 * 60)
    }

    func testNightPlaceWaitsUntilSunset() throws {
        let light = TripTimes.Light(sunset: 16 * 60 + 32, goldenStart: 15 * 60 + 40)
        let day = TripTimes.schedule(start: 9 * 60, stops: [stop("a", stay: 300), stop("スカイツリー", stay: 90, times: ["night"])],
                                     moves: [0, 30], light: light)
        let night = day.rows[1]
        XCTAssertEqual(night.arrive, 16 * 60 + 35, "日の入り 16:32 を5分の単位に切り上げた時刻に合わせる")
        XCTAssertEqual(night.wait, 16 * 60 + 35 - (14 * 60 + 30))
        XCTAssertEqual(TripTimes.waitLine(night), "日の入り 16:32 まで 2時間5分あき")
        XCTAssertEqual(day.end, 16 * 60 + 35 + 90)
        // 日の入りより後に着くなら待たない
        let late = TripTimes.schedule(start: 12 * 60, stops: [stop("a", stay: 300), stop("夜景", times: ["dusk"])],
                                      moves: [0, 30], light: light)
        XCTAssertEqual(late.rows[1].arrive, 17 * 60 + 30)
        XCTAssertNil(TripTimes.waitLine(late.rows[1]))
    }

    func testGoldenHourPlaceWaitsUntilGoldenStart() {
        let light = TripTimes.Light(sunset: 16 * 60 + 32, goldenStart: 15 * 60 + 40)
        let day = TripTimes.schedule(start: 9 * 60, stops: [stop("a"), stop("屋島", times: ["goldenHour"])], moves: [0, 20], light: light)
        XCTAssertEqual(day.rows[1].arrive, 15 * 60 + 40)
        XCTAssertEqual(TripTimes.waitLine(day.rows[1]), "夕方の斜光 15:40 まで 5時間20分あき")
        // 日の光が分からない（座標・時刻帯が無い）ときは待たない
        let unknown = TripTimes.schedule(start: 9 * 60, stops: [stop("a"), stop("屋島", times: ["goldenHour"])], moves: [0, 20], light: nil)
        XCTAssertEqual(unknown.rows[1].arrive, 10 * 60 + 20)
    }

    func testMorningPlaceArrivingLateGetsALine() {
        let early = TripTimes.schedule(start: 9 * 60, stops: [stop("浅草寺", times: ["morning"])], moves: [0], light: nil)
        XCTAssertNil(TripTimes.lateMorningLine(early.rows[0]))
        let late = TripTimes.schedule(start: 11 * 60, stops: [stop("浅草寺", times: ["morning"])], moves: [0], light: nil)
        XCTAssertEqual(TripTimes.lateMorningLine(late.rows[0]), "朝の案内の場所ですが、着くのは11:00ごろ")
        let dawn = TripTimes.schedule(start: 11 * 60, stops: [stop("a", times: ["dawn", "morning"])], moves: [0], light: nil)
        XCTAssertEqual(TripTimes.lateMorningLine(dawn.rows[0]), "夜明けの案内の場所ですが、着くのは11:00ごろ")
        // 10:00 ちょうどは遅れていない
        let ten = TripTimes.schedule(start: 10 * 60, stops: [stop("a", times: ["morning"])], moves: [0], light: nil)
        XCTAssertNil(TripTimes.lateMorningLine(ten.rows[0]))
    }

    /// 回 1672 の絵: 朝と夕方の斜光の両方の案内がある金沢城公園を、10:20 に着くのに日の入りまで6時間待たせ、
    /// 「朝の案内の場所ですが、着くのは16:45ごろ」と言っていた
    func testPlaceWithEarlyAndLateGuidanceNeitherWaitsNorWarns() {
        let light = TripTimes.Light(sunset: 16 * 60 + 41, goldenStart: 15 * 60 + 50)
        let day = TripTimes.schedule(start: 9 * 60, stops: [stop("ひがし茶屋街"), stop("金沢城公園", times: ["morning", "goldenHour"])],
                                     moves: [0, 20], light: light)
        XCTAssertEqual(day.rows[1].arrive, 10 * 60 + 20, "朝にも向く場所を日の入りまで待たせた")
        XCTAssertNil(TripTimes.waitLine(day.rows[1]))
        let late = TripTimes.schedule(start: 12 * 60, stops: [stop("a", times: ["morning", "goldenHour"])], moves: [0], light: light)
        XCTAssertNil(TripTimes.lateMorningLine(late.rows[0]), "夕方にも向く場所に朝の一言を出した")
        let dayToo = TripTimes.schedule(start: 9 * 60, stops: [stop("a"), stop("b", times: ["day", "night"])], moves: [0, 10], light: light)
        XCTAssertEqual(dayToo.rows[1].arrive, 10 * 60 + 10, "日中にも向く場所を日の入りまで待たせた")
        // 斜光の始まりが分からない日は、日の入りに合わせない（斜光を逃す）
        let noGolden = TripTimes.Light(sunset: 16 * 60 + 41, goldenStart: nil)
        let g = TripTimes.schedule(start: 9 * 60, stops: [stop("a"), stop("屋島", times: ["goldenHour"])], moves: [0, 20], light: noGolden)
        XCTAssertEqual(g.rows[1].arrive, 10 * 60 + 20)
    }

    func testUnknownMoveStopsLaterTimes() {
        let day = TripTimes.schedule(start: 9 * 60, stops: [stop("a"), stop("b"), stop("c")], moves: [0, nil, 10], light: nil)
        XCTAssertEqual(day.rows.map(\.arrive), [540, nil, nil], "長い移動から先に作った時刻を重ねた")
        XCTAssertNil(day.end)
    }

    // MARK: - 言葉と読み上げ

    func testClockAndSpoken() {
        XCTAssertEqual(TripTimes.clock(9 * 60), "9:00")
        XCTAssertEqual(TripTimes.clock(16 * 60 + 5), "16:05")
        XCTAssertEqual(TripTimes.clock(24 * 60 + 30), "翌0:30")
        XCTAssertEqual(TripTimes.spokenClock(9 * 60), "9時")
        XCTAssertEqual(TripTimes.spokenClock(9 * 60 + 30), "9時30分")
        XCTAssertEqual(TripTimes.spokenStop(9 * 60, name: "日比谷公園"), "9時、日比谷公園")
        XCTAssertEqual(TripTimes.spokenStop(nil, name: "日比谷公園"), "日比谷公園")
        XCTAssertEqual(TripTimes.duration(115), "1時間55分")
        XCTAssertEqual(TripTimes.duration(40), "40分")
        XCTAssertEqual(TripTimes.note, "時刻は目安です（滞在は場所の種類から）")
        let row = TripTimes.Row(arrive: 9 * 60)
        XCTAssertEqual(AskPlanTimeline.spokenStop(number: 1, name: "日比谷公園", row: row), "1番目、9時、日比谷公園")
        XCTAssertEqual(TripStopLabel.spoken(number: 2, name: "東京タワー", time: 10 * 60 + 30, parts: [nil, "夜"]),
                       "2\u{2002}10時30分、東京タワー\u{2002}夜")
        // 「・」「·」で区切らない（owner の好み）
        for text in [TripTimes.note, TripTimes.endLine(600), TripTimes.waitLine(TripTimes.Row(arrive: 990, wait: 30, waitFor: ("日の入り", 990))) ?? ""] {
            XCTAssertFalse(text.contains("・") || text.contains("·"), text)
        }
    }

    // MARK: - 旅行プランの頁の移動

    func testPlanMovesUseAppleEstimatesThenRoughThenStop() {
        let a = Photo.Coords(lat: 35.674, lng: 139.756), b = Photo.Coords(lat: 35.659, lng: 139.745)
        let c = Photo.Coords(lat: 35.710, lng: 139.811)
        let stops = [TripTravel.Stop("日比谷公園", a, 1), TripTravel.Stop("撮影地", nil, 2),
                     TripTravel.Stop("東京タワー", b, 3), TripTravel.Stop("スカイツリー", c, 4)]
        let legs = TripTravel.legs(stops)
        XCTAssertEqual(legs.map(\.to.number), [3, 4])
        let apple = [TripTravel.Estimate(mode: .transit, seconds: 13 * 60 + 10)]
        let moves = TripTimes.planMoves(numbers: [1, 2, 3, 4], legs: legs, estimates: [apple, []], long: [false, false])
        XCTAssertEqual(moves[0], 0, "1か所目は出発の時刻")
        XCTAssertEqual(moves[1], 0, "座標の無い場所へは区間が無いので 0 分")
        XCTAssertEqual(moves[2], 15, "Apple の見込み 13分10秒を5分の単位に切り上げ")
        XCTAssertEqual(moves[3], TripTimes.roughMoveMinutes(b, c), "まだ返らない区間は AI の画面と同じ見積もり")
        let long = TripTimes.planMoves(numbers: [1, 2, 3, 4], legs: legs, estimates: [apple, []], long: [false, true])
        XCTAssertNil(long[3], "長い移動の区間で時刻を作った")
        // 前の日からの区間は数えない
        var cross = TripTravel.Leg(from: TripTravel.Endpoint(name: "前の日", coords: c, number: 0), to: legs[0].to)
        cross.crossesDay = true
        XCTAssertEqual(TripTimes.planMoves(numbers: [3], legs: [cross], estimates: [[]], long: [false]), [0])
    }

    // MARK: - AI の画面の流れ

    func testAskFlowTimesUseCategoryAndMoveLine() throws {
        let hibiya = try spot("hibiya", name: "日比谷公園", category: "公園", lat: 35.674, lng: 139.756)
        let tower = try spot("tower", name: "東京タワー", category: "展望台", lat: 35.659, lng: 139.745, times: ["night"])
        let move = try XCTUnwrap(AskPlanFlowText.moveMinutes(hibiya, tower))
        let day = AskPlanFlowText.times([hibiya, tower], start: 9 * 60, ymd: "2026-12-21")
        XCTAssertEqual(day.rows[0].arrive, 9 * 60)
        // 東京の 12月21日の日の入り（16:30 ごろ）まで待つ夜の場所
        let arrive = try XCTUnwrap(day.rows[1].arrive)
        XCTAssertGreaterThan(day.rows[1].wait, 0, "夜の場所が日の入りの前に着く時刻のまま")
        XCTAssertGreaterThanOrEqual(arrive, 16 * 60 + 20)
        XCTAssertLessThanOrEqual(arrive, 16 * 60 + 45)
        XCTAssertEqual(arrive - day.rows[1].wait, 9 * 60 + 90 + move, "待つ前の着く時刻 = 出発 + 公園 90 分 + 移動の目安")
        // 座標の無い場所の間は 0 分
        let nowhere = try spot("x", name: "場所", category: nil, lat: nil, lng: nil)
        let d2 = AskPlanFlowText.times([hibiya, nowhere], start: 10 * 60, ymd: "2026-12-21")
        XCTAssertEqual(d2.rows.map(\.arrive), [600, 690])
    }

    /// 区間の行は旅行プランの頁と同じ型の区間を持ち、同じ選び方で手段を決める（座標が無ければ押せない）
    func testAskMoveRowOpensRouteLikeTripPlanLeg() throws {
        let hibiya = try spot("hibiya", name: "日比谷公園", category: "公園", lat: 35.674, lng: 139.756)
        let tower = try spot("tower", name: "東京タワー", category: "展望台", lat: 35.659, lng: 139.745)
        let near = try spot("near", name: "近く", category: nil, lat: 35.676, lng: 139.757)
        let nowhere = try spot("x", name: "場所", category: nil, lat: nil, lng: nil)
        let leg = try XCTUnwrap(AskPlanFlowText.leg(hibiya, tower, numbers: (1, 2)), "座標のある2か所に経路を開く口が無い")
        XCTAssertEqual(leg.from.name, "日比谷公園")
        XCTAssertEqual(leg.to.name, "東京タワー")
        XCTAssertEqual(leg.to.country, "日本")
        XCTAssertEqual(AskPlanFlowText.mapsMode(leg), TripTravel.mapsMode([], leg: leg, settled: false))
        XCTAssertEqual(AskPlanFlowText.mapsMode(leg), .transit, "1km より遠い区間は電車など（旅行プランの頁と同じ）")
        let short = try XCTUnwrap(AskPlanFlowText.leg(hibiya, near, numbers: (1, 2)))
        XCTAssertEqual(AskPlanFlowText.mapsMode(short), .walking, "1km 以内は歩き（旅行プランの頁と同じ）")
        XCTAssertNil(AskPlanFlowText.leg(hibiya, nowhere, numbers: (1, 2)), "座標の無い場所に押せる区間を作った")
        XCTAssertNil(AskPlanFlowText.leg(nowhere, hibiya, numbers: (1, 2)))
        XCTAssertNil(AskPlanFlowText.leg(hibiya, hibiya, numbers: (1, 2)), "同じ座標の2か所に区間を作った")
    }

    func testAskMoveRowUsesTheTripPlanOpener() throws {
        let parts = try source("Sources/JourneyPhoto/Features/Search/AskAnswerParts.swift")
        XCTAssertTrue(parts.contains("await TripLeg" + "Maps.open(leg, mode: mode, search: search)"), "旅行プランの頁と別の開き方を作った")
        XCTAssertTrue(parts.contains(".accessibilityHint(TripTravel.mapsHint(mode))"))
        XCTAssertTrue(parts.contains("minHeight: WebTheme.minTapTarget"), "区間の行の当たりが 44pt でない")
        XCTAssertTrue(parts.contains("\"search.ask.moveStatic\""), "座標の無い区間の押せない形が無い")
        // 場所の札は今までどおり観光スポットの頁
        XCTAssertTrue(parts.contains("OfficialSpotView(spot: spot, spots: officialSpots"))
    }

    // MARK: - 旅行プランの頁

    func testTripPlanPageShowsTimes() throws {
        let page = try source("Sources/JourneyPhoto/Features/Trips/TripPlanDetailView.swift")
        XCTAssertTrue(page.contains("TripTimes.planMoves("))
        XCTAssertTrue(page.contains("TripStartButton(start: start, open: startOpen)"))
        XCTAssertTrue(page.contains("TripTimeNote()"))
        XCTAssertTrue(page.contains("time: showsTimes ? timeRow : nil"))
        // 区間の行は時刻の列のぶん右へ（縦の線を番号の丸にそろえる）
        XCTAssertTrue(page.contains(".padding(.leading, timesInset)"))
    }

    // MARK: - 出発の時刻を覚える

    @MainActor
    func testStartStoreRemembersPerPlanAndDay() async throws {
        let suite = "TripTimesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TripStartStore(defaults: defaults)
        XCTAssertEqual(store.minutes(planId: "p1", day: 0), 540)
        store.set(11 * 60, planId: "p1", day: 0)
        XCTAssertEqual(store.minutes(planId: "p1", day: 0), 660)
        XCTAssertEqual(store.minutes(planId: "p1", day: 1), 540, "ほかの日まで変わった")
        XCTAssertEqual(store.minutes(planId: "p2", day: 0), 540, "ほかのプランまで変わった")
        XCTAssertEqual(TripStartStore(defaults: defaults).minutes(planId: "p1", day: 0), 660, "この iPhone に覚えていない")
        store.set(9 * 60, planId: "p1", day: 0)
        XCTAssertNil((defaults.dictionary(forKey: TripStartStore.defaultsKey) as? [String: Int])?["p1#0"], "既定の 9:00 を覚えた")
        store.set(8 * 60, planId: nil, day: 0)
        XCTAssertEqual(store.minutes(planId: nil, day: 0), 540, "保存していないプランの時刻を覚えた")
    }
}
