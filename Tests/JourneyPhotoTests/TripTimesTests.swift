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
        let day = TripTimes.schedule(start: 12 * 60, stops: [stop("a"), stop("屋島", times: ["goldenHour"])], moves: [0, 20], light: light)
        XCTAssertEqual(day.rows[1].arrive, 15 * 60 + 40)
        XCTAssertEqual(TripTimes.waitLine(day.rows[1]), "夕方の斜光 15:40 まで 2時間20分あき")
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

    /// 確かめ役の指摘（2026-11-21）: 夜だけの場所の待ちに上限が無かった。4 時間を超えたら待たせず、日の入りだけ添える
    func testLongWaitIsNotScheduled() {
        let light = TripTimes.Light(sunset: 16 * 60 + 30, goldenStart: 15 * 60 + 40)
        let day = TripTimes.schedule(start: 9 * 60, stops: [stop("a"), stop("夜景", times: ["night"])], moves: [0, 20], light: light)
        XCTAssertEqual(day.rows[1].arrive, 10 * 60 + 20, "6時間待たせた")
        XCTAssertEqual(day.rows[1].wait, 0)
        XCTAssertEqual(TripTimes.cautionLine(day.rows[1]), "日の入りは 16:30")
        XCTAssertNil(TripTimes.waitLine(day.rows[1]))
        // 4 時間以内なら今までどおり待つ
        let near = TripTimes.schedule(start: 12 * 60 + 30, stops: [stop("夜景", times: ["night"])], moves: [0], light: light)
        XCTAssertEqual(near.rows[0].arrive, 16 * 60 + 30)
        XCTAssertNil(TripTimes.cautionLine(near.rows[0]))
        // 夕方の斜光
        let g = TripTimes.schedule(start: 9 * 60, stops: [stop("屋島", times: ["goldenHour"])], moves: [0], light: light)
        XCTAssertEqual(g.rows[0].arrive, 9 * 60)
        XCTAssertEqual(TripTimes.cautionLine(g.rows[0]), "夕方の斜光は 15:40 から")
        let parts = (try? source("Sources/JourneyPhoto/Features/Search/AskAnswerParts.swift")) ?? ""
        XCTAssertTrue(parts.contains("TripTimes.cautionLine(row)"), "AI の画面に日の入りの一言が出ない")
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
        XCTAssertEqual(TripTimes.clock(48 * 60 + 30), "翌々0:30", "2日またいでも「翌」が1回だけ")
        XCTAssertEqual(TripTimes.clock(72 * 60 + 5), "+3日 0:05")
        XCTAssertEqual(TripTimes.spokenClock(48 * 60), "翌々0時")
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
        let coords: [Photo.Coords?] = [a, nil, b, c]
        let moves = TripTimes.planMoves(numbers: [1, 2, 3, 4], coords: coords, legs: legs, estimates: [apple, []],
                                        long: [false, false])
        XCTAssertEqual(moves[0], 0, "1か所目は出発の時刻")
        XCTAssertNil(moves[1], "座標の無い場所への移動を 0 分として続けた")
        XCTAssertNil(moves[2], "座標の無い場所からの移動を分かる扱いにした")
        XCTAssertEqual(moves[3], TripTimes.roughMoveMinutes(b, c), "まだ返らない近い区間は AI の画面と同じ見積もり")
        let all = [TripTravel.Stop("日比谷公園", a, 1), TripTravel.Stop("東京タワー", b, 2), TripTravel.Stop("スカイツリー", c, 3)]
        let legs2 = TripTravel.legs(all)
        let m2 = TripTimes.planMoves(numbers: [1, 2, 3], coords: [a, b, c], legs: legs2, estimates: [apple, []], long: [false, false])
        XCTAssertEqual(m2, [0, 15, TripTimes.roughMoveMinutes(b, c)], "Apple の見込み 13分10秒を5分の単位に切り上げ")
        let long = TripTimes.planMoves(numbers: [1, 2, 3], coords: [a, b, c], legs: legs2, estimates: [apple, []], long: [false, true])
        XCTAssertNil(long[2], "長い移動の区間で時刻を作った")
        // 同じ座標は 0 分
        XCTAssertEqual(TripTimes.planMoves(numbers: [1, 2], coords: [a, a], legs: [], estimates: [], long: []), [0, 0])
        // 前の日からの区間は数えない
        var cross = TripTravel.Leg(from: TripTravel.Endpoint(name: "前の日", coords: c, number: 0), to: legs[0].to)
        cross.crossesDay = true
        XCTAssertEqual(TripTimes.planMoves(numbers: [3], coords: [b], legs: [cross], estimates: [[]], long: [false]), [0])
    }

    /// 確かめ役の指摘（2026-11-21）: Apple の見込みが無い区間を 500km 未満まで時速 30km で積み、東京から京都で 16 時間になった。
    /// 概算で積むのはまっすぐ 60km 以内だけ。遠い区間は nil（そこから先の時刻を出さない）。AI の画面も同じ
    func testFarLegWithoutEstimateStopsTimes() throws {
        let tokyo = Photo.Coords(lat: 35.681, lng: 139.767), kyoto = Photo.Coords(lat: 34.985, lng: 135.758)
        let yokohama = Photo.Coords(lat: 35.444, lng: 139.638)
        XCTAssertNil(TripTimes.scheduleMoveMinutes(tokyo, kyoto), "東京から京都を概算で積んだ")
        XCTAssertNotNil(TripTimes.scheduleMoveMinutes(tokyo, yokohama), "近い区間（約 28km）まで止めた")
        XCTAssertEqual(TripTimes.scheduleMoveMinutes(tokyo, tokyo), 0)
        XCTAssertNil(TripTimes.scheduleMoveMinutes(tokyo, nil))
        let legs = TripTravel.legs([TripTravel.Stop("東京駅", tokyo, 1), TripTravel.Stop("京都駅", kyoto, 2)])
        let moves = TripTimes.planMoves(numbers: [1, 2], coords: [tokyo, kyoto], legs: legs, estimates: [[]], long: [false])
        XCTAssertNil(moves[1], "見込みの無い遠い区間で時刻を作った")
        let a = try spot("tokyo", name: "東京駅", category: "駅", lat: tokyo.lat, lng: tokyo.lng)
        let b = try spot("kyoto", name: "京都駅", category: "駅", lat: kyoto.lat, lng: kyoto.lng)
        let day = AskPlanFlowText.times([a, b], start: 9 * 60, ymd: "2026-12-21")
        XCTAssertEqual(day.rows.map(\.arrive), [540, nil], "AI の画面で東京から京都の着く時刻を作った")
        XCTAssertNil(AskPlanFlowText.moveMinutes(a, b), "遠い区間に移動の目安の数を出した")
        XCTAssertEqual(AskPlanFlowText.moveText(a, b), "移動は経路で確かめる")
    }

    // MARK: - AI の画面の流れ

    func testAskFlowTimesUseCategoryAndMoveLine() throws {
        let hibiya = try spot("hibiya", name: "日比谷公園", category: "公園", lat: 35.674, lng: 139.756)
        let tower = try spot("tower", name: "東京タワー", category: "展望台", lat: 35.659, lng: 139.745, times: ["night"])
        let move = try XCTUnwrap(AskPlanFlowText.moveMinutes(hibiya, tower))
        let day = AskPlanFlowText.times([hibiya, tower], start: 12 * 60, ymd: "2026-12-21")
        XCTAssertEqual(day.rows[0].arrive, 12 * 60)
        // 東京の 12月21日の日の入り（16:30 ごろ）まで待つ夜の場所
        let arrive = try XCTUnwrap(day.rows[1].arrive)
        XCTAssertGreaterThan(day.rows[1].wait, 0, "夜の場所が日の入りの前に着く時刻のまま")
        XCTAssertGreaterThanOrEqual(arrive, 16 * 60 + 20)
        XCTAssertLessThanOrEqual(arrive, 16 * 60 + 45)
        XCTAssertEqual(arrive - day.rows[1].wait, 12 * 60 + 90 + move, "待つ前の着く時刻 = 出発 + 公園 90 分 + 移動の目安")
        // 座標の無い場所との間は分からない（0 分として続けない）。同じ座標は 0 分
        let nowhere = try spot("x", name: "場所", category: nil, lat: nil, lng: nil)
        let d2 = AskPlanFlowText.times([hibiya, nowhere], start: 10 * 60, ymd: "2026-12-21")
        XCTAssertEqual(d2.rows.map(\.arrive), [600, nil])
        XCTAssertNil(d2.end)
        let twin = try spot("twin", name: "日比谷公園の噴水", category: "公園", lat: 35.674, lng: 139.756)
        let d3 = AskPlanFlowText.times([hibiya, twin], start: 10 * 60, ymd: "2026-12-21")
        XCTAssertEqual(d3.rows.map(\.arrive), [600, 690])
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
        XCTAssertTrue(page.contains("TripStartButton(start: startMinutes, open: startOpen)"))
        XCTAssertTrue(page.contains("timeCaution: time.flatMap(TripTimes.cautionLine)"))
        XCTAssertTrue(page.contains("TripTimeNote()"))
        XCTAssertTrue(page.contains("time: showsTimes ? timeRow : nil"))
        // 区間の行は時刻の列のぶん右へ（縦の線を番号の丸にそろえる）
        XCTAssertTrue(page.contains(".padding(.leading, timesInset)"))
    }

    // MARK: - 出発の時刻を覚える

    @MainActor
    private func freshStore() throws -> (TripStartStore, UserDefaults, String) {
        let suite = "TripTimesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (TripStartStore(defaults: defaults), defaults, suite)
    }

    private func day(_ ids: String...) -> TripDay {
        TripDay(items: ids.map { .spot(spotId: $0, note: nil) })
    }

    @MainActor
    func testStartStoreRemembersPerPlanAndDay() async throws {
        let (store, defaults, suite) = try freshStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(store.minutes(planId: "p1", ymd: nil, day: 0), 540)
        store.set(11 * 60, planId: "p1", ymd: nil, day: 0)
        XCTAssertEqual(store.minutes(planId: "p1", ymd: nil, day: 0), 660)
        XCTAssertEqual(store.minutes(planId: "p1", ymd: nil, day: 1), 540, "ほかの日まで変わった")
        XCTAssertEqual(store.minutes(planId: "p2", ymd: nil, day: 0), 540, "ほかのプランまで変わった")
        XCTAssertEqual(TripStartStore(defaults: defaults).minutes(planId: "p1", ymd: nil, day: 0), 660, "この iPhone に覚えていない")
        store.set(9 * 60, planId: "p1", ymd: nil, day: 0)
        XCTAssertNil((defaults.dictionary(forKey: TripStartStore.defaultsKey) as? [String: Int])?["p1#0"], "既定の 9:00 を覚えた")
        store.set(8 * 60, planId: nil, ymd: nil, day: 0)
        XCTAssertEqual(store.minutes(planId: nil, ymd: nil, day: 0), 540, "保存していないプランの時刻を覚えた")
        // 日付のある日は日付の鍵
        store.set(7 * 60, planId: "p1", ymd: "2026-12-22", day: 1)
        XCTAssertEqual(store.minutes(planId: "p1", ymd: "2026-12-22", day: 5), 420)
        XCTAssertEqual(store.minutes(planId: "p1", ymd: nil, day: 1), 540)
    }

    /// 確かめ役の指摘（2026-11-21）: 日の番号に付けて覚えたので、日を消すと次の日に前の日の時刻が付いた
    @MainActor
    func testStartFollowsTheDayWhenADayIsRemoved() async throws {
        let (store, defaults, suite) = try freshStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        // 日付の無いプラン: 1日目 7:00、2日目 11:00。1日目を消すと、残った日（前の2日目）は 11:00
        let before = [day("a", "b"), day("c", "d")]
        store.set(7 * 60, planId: "p", ymd: nil, day: 0)
        store.set(11 * 60, planId: "p", ymd: nil, day: 1)
        let after = try XCTUnwrap(TripPlanEdit.removeDay(before, at: 0, snapshot: before))
        store.carry(from: TripStartKeys.slots(planId: "p", days: before, start: nil, end: nil),
                    to: TripStartKeys.slots(planId: "p", days: after, start: nil, end: nil))
        XCTAssertEqual(store.minutes(planId: "p", ymd: nil, day: 0), 660, "消した日の時刻が次の日に残った")
        XCTAssertEqual(store.minutes(planId: "p", ymd: nil, day: 1), 540, "無くなった日の覚えが残った")
        // 日付のあるプラン: 日付は前から順に付くので、消すと日付もずれる。中身で運ぶ
        let dated = [day("a"), day("b"), day("c")]
        store.set(8 * 60, planId: "q", ymd: "2026-12-22", day: 1)
        let datedAfter = try XCTUnwrap(TripPlanEdit.removeDay(dated, at: 0, snapshot: dated))
        store.carry(from: TripStartKeys.slots(planId: "q", days: dated, start: "2026-12-21", end: "2026-12-23"),
                    to: TripStartKeys.slots(planId: "q", days: datedAfter, start: "2026-12-21", end: "2026-12-22"))
        XCTAssertEqual(store.minutes(planId: "q", ymd: "2026-12-21", day: 0), 480, "b の日の 8:00 が b に付いていない")
        XCTAssertEqual(store.minutes(planId: "q", ymd: "2026-12-22", day: 1), 540, "c の日に b の時刻が付いた")
    }

    /// 日を入れ替えた（組み直し・仲間の変更）ときも、場所の多く重なる日へ時刻が付いていく
    @MainActor
    func testStartFollowsTheDayWhenDaysAreSwapped() async throws {
        let (store, defaults, suite) = try freshStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let before = [day("a", "b", "c"), day("d", "e")]
        store.set(7 * 60, planId: "p", ymd: nil, day: 0)
        let swapped = [day("d", "e", "x"), day("a", "c")]
        store.carry(from: TripStartKeys.slots(planId: "p", days: before, start: nil, end: nil),
                    to: TripStartKeys.slots(planId: "p", days: swapped, start: nil, end: nil))
        XCTAssertEqual(store.minutes(planId: "p", ymd: nil, day: 1), 420, "入れ替えた日に時刻が付いていかない")
        XCTAssertEqual(store.minutes(planId: "p", ymd: nil, day: 0), 540)
        // 1か所を別の日へ運んだだけなら、日の時刻は動かない
        let moved = [day("d", "e", "x"), day("a")]
        let movedTo = [day("d", "e", "x", "a"), day()]
        store.carry(from: TripStartKeys.slots(planId: "p", days: moved, start: nil, end: nil),
                    to: TripStartKeys.slots(planId: "p", days: movedTo, start: nil, end: nil))
        XCTAssertEqual(store.minutes(planId: "p", ymd: nil, day: 0), 540, "場所を1つ運んだだけで日の時刻が入れ替わった")
        XCTAssertEqual(store.minutes(planId: "p", ymd: nil, day: 1), 420, "空になった日の時刻が消えた")
        // 開いたばかり（前が空）は何もしない
        let kept = TripStartKeys.carried(["p#0": 600], from: [], to: TripStartKeys.slots(planId: "p", days: [day("z")], start: nil, end: nil))
        XCTAssertEqual(kept, ["p#0": 600])
        // 頁が変わったときに運ぶ
        let page = try source("Sources/JourneyPhoto/Features/Trips/TripPlanDetailView.swift")
        XCTAssertTrue(page.contains(".onChange(of: startSlots) { old, now in starts.carry(from: old, to: now) }"))
        XCTAssertTrue(page.contains("starts.minutes(planId: planId, ymd: ymd, day: di)"))
    }

    /// プランを消したとき・ログアウトで覚えを消す。AI の画面は覚えを共有しない
    @MainActor
    func testStartStoreIsForgottenAndNotSharedWithAsk() async throws {
        let (store, defaults, suite) = try freshStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.set(7 * 60, planId: "p1", ymd: nil, day: 0)
        store.set(8 * 60, planId: "p10", ymd: "2026-12-21", day: 0)
        store.forget(planId: "p1")
        XCTAssertEqual(store.minutes(planId: "p1", ymd: nil, day: 0), 540)
        XCTAssertEqual(store.minutes(planId: "p10", ymd: "2026-12-21", day: 0), 480, "名前の似たほかのプランまで消した")
        store.forgetAll()
        XCTAssertEqual(store.minutes(planId: "p10", ymd: "2026-12-21", day: 0), 540)
        XCTAssertNil(defaults.dictionary(forKey: TripStartStore.defaultsKey))
        XCTAssertTrue(try source("Sources/JourneyPhoto/Core/Auth/AuthStore.swift").contains("TripStartStore.shared.forgetAll()"))
        XCTAssertTrue(try source("Sources/JourneyPhoto/Services/TripPlanService.swift")
            .contains("await TripStartStore.shared.forget(planId: planId)"))
        let ask = try source("Sources/JourneyPhoto/Features/Search/AskAnswerParts.swift")
        XCTAssertFalse(ask.contains("TripStartStore"), "AI の画面が旅行プランの頁の覚えを使っている")
        // 大きな字では出発のボタンを見出しの下へ
        XCTAssertTrue(ask.contains("if timeInColumn {\n            HStack(spacing: JPSpace.xs) {"))
    }
}
