import XCTest
@testable import JourneyPhoto

/// 日をまたぐ区間（2026-11-11 owner の実機「バスとか出てこないよ」・札 #521 の続き）。
/// 1 日目 伏見稲荷大社だけ・2 日目 一乗寺 圓光寺だけ・3 日目 空、のプランで移動の目安が1つも出なかった
final class TripLegsAcrossDaysTests: XCTestCase {

    private let fushimi = Photo.Coords(lat: 34.97, lng: 135.77)
    private let enkoji = Photo.Coords(lat: 35.05, lng: 135.80)
    private let kinkakuji = Photo.Coords(lat: 35.04, lng: 135.73)

    /// 1 日 1 か所 × 2 日（＋空の日）→ 2 日目の最初の上に「前の日の伏見稲荷大社から」の区間が1つ
    func testOnePlacePerDayMakesOneLegAcrossDays() {
        let legs = TripTravel.planLegs([[.init("伏見稲荷大社", fushimi, 1)], [.init("一乗寺 圓光寺", enkoji, 2)], []])
        XCTAssertEqual(legs.map(\.count), [0, 1, 0])
        let leg = legs[1][0]
        XCTAssertTrue(leg.crossesDay)
        XCTAssertEqual(leg.from.number, 1)
        XCTAssertEqual(leg.to.number, 2)
        XCTAssertEqual(TripTravel.crossDayLabel(leg), "前の日の伏見稲荷大社から")
        XCTAssertEqual(TripLegRow.spoken(leg: leg, estimates: [], offline: false), "前の日の伏見稲荷大社から一乗寺 圓光寺")
    }

    /// 空の日・座標の無い日は飛ばし、その前の場所から
    func testSkipsEmptyAndUnlocatedDays() {
        let legs = TripTravel.planLegs([[.init("伏見稲荷大社", fushimi, 1)], [], [.init("x", nil, 2)], [.init("金閣寺", kinkakuji, 3)]])
        XCTAssertEqual(legs.map(\.count), [0, 0, 0, 1])
        XCTAssertEqual(legs[3][0].from.name, "伏見稲荷大社")
    }

    /// 同じ日の区間は今までどおり。日をまたぐ区間はその日の頭に1つだけ
    func testSameDayLegsStayAndCrossLegComesFirst() {
        let legs = TripTravel.planLegs([[.init("A", fushimi, 1), .init("B", enkoji, 2)], [.init("C", kinkakuji, 3), .init("D", fushimi, 4)]])
        XCTAssertEqual(legs[0].map(\.crossesDay), [false])
        XCTAssertEqual(legs[1].map(\.crossesDay), [true, false])
        XCTAssertEqual(legs[1][0].from.name, "B", "前の日の**最後の**場所から")
    }

    /// 同じ座標の2か所の間は出さない（日をまたいでも、同じ日でも）
    func testSameCoordinatesMakeNoLeg() {
        XCTAssertEqual(TripTravel.planLegs([[.init("宿", fushimi, 1)], [.init("伏見稲荷大社", fushimi, 2)]]).map(\.count), [0, 0])
        XCTAssertEqual(TripTravel.legs([.init("A", fushimi, 1), .init("A'", fushimi, 2)]).count, 0)
    }

    /// 場所が1か所だけのときだけ、出ない理由の1行
    func testSinglePlaceHint() {
        XCTAssertNotNil(TripTravel.singlePlaceHint(locatedPlaces: 1))
        XCTAssertNil(TripTravel.singlePlaceHint(locatedPlaces: 0), "0 か所は日の「まだ何も入っていません」が言う")
        XCTAssertNil(TripTravel.singlePlaceHint(locatedPlaces: 2))
    }

    /// 画面: 日程は日ごとの区間をプラン全体から作り、日をまたぐ区間は最初の場所の上に出す
    func testDetailUsesPlanLegs() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let detail = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Trips/TripPlanDetailView.swift"),
                                encoding: .utf8)
        XCTAssertTrue(detail.contains("TripTravel.planLegs(planStops)"))
        XCTAssertTrue(detail.contains("ii > 0 || leg.crossesDay"))
        XCTAssertTrue(detail.contains("TripTravel.singlePlaceHint(locatedPlaces: 1)"))
    }

    // MARK: - 長い移動（2026-11-11 owner「日本からブラジルとか無理じゃん」）

    private func leg(_ a: Photo.Coords, _ b: Photo.Coords, _ ca: String? = nil, _ cb: String? = nil,
                     crossesDay: Bool = true) -> TripTravel.Leg {
        TripTravel.Leg(from: .init(name: "A", coords: a, number: 1, country: ca, place: "京都市"),
                       to: .init(name: "B", coords: b, number: 2, country: cb, place: "サンパウロ"), crossesDay: crossesDay)
    }

    private let tokyo = Photo.Coords(lat: 35.68, lng: 139.77)
    private let sapporo = Photo.Coords(lat: 43.06, lng: 141.35)
    private let saoPaulo = Photo.Coords(lat: -23.55, lng: -46.63)
    private let busan = Photo.Coords(lat: 35.10, lng: 129.04)
    private let tsushima = Photo.Coords(lat: 34.20, lng: 129.29)

    /// 国が違う → 近くても聞かない（対馬 → 釜山 約 100km）。遠ければもちろん（京都 → サンパウロ）
    func testDifferentCountriesAreLong() {
        let near = leg(tsushima, busan, "日本", "韓国")
        XCTAssertTrue(TripTravel.skipsDirections(near))
        XCTAssertTrue(TripTravel.showsAsLong(near, estimates: [], settled: false))
        let brazil = leg(fushimi, saoPaulo, "日本", "ブラジル")
        XCTAssertTrue(TripTravel.skipsDirections(brazil))
        XCTAssertTrue(TripTravel.longLine(brazil).hasPrefix("飛行機などの長い移動・約 18,"))
        XCTAssertEqual(TripLegRow.state(leg: brazil, estimates: [], settled: false, offline: true, throttled: false), .long,
                       "圏外でも長い移動の形（聞かないので）")
    }

    /// 国が分からない（行きたい場所・撮影地）→ まっすぐの距離 500km の前後で決める
    func testThresholdWithoutCountries() {
        let base = Photo.Coords(lat: 30, lng: 135)
        let under = leg(base, Photo.Coords(lat: 34.48, lng: 135))    // 約 498km
        let over = leg(base, Photo.Coords(lat: 34.52, lng: 135))     // 約 503km
        XCTAssertLessThan(under.kilometers, TripTravel.longKm)
        XCTAssertGreaterThan(over.kilometers, TripTravel.longKm)
        XCTAssertFalse(TripTravel.skipsDirections(under))
        XCTAssertTrue(TripTravel.skipsDirections(over))
    }

    /// 日本の中の長い区間（東京 → 札幌 約 830km）: 聞く。返れば見込み、聞き終えて返らなければ長い移動に倒す
    func testLongDomesticFallsBackOnlyWhenNothingReturns() {
        let domestic = leg(tokyo, sapporo, "日本", "日本")
        XCTAssertFalse(TripTravel.skipsDirections(domestic))
        XCTAssertFalse(TripTravel.showsAsLong(domestic, estimates: [], settled: false), "聞いている間は長い移動にしない")
        XCTAssertTrue(TripTravel.showsAsLong(domestic, estimates: [], settled: true), "返らなければ長い移動")
        let returned = [TripTravel.Estimate(mode: .transit, seconds: 8 * 3600)]
        XCTAssertFalse(TripTravel.showsAsLong(domestic, estimates: returned, settled: true), "返ったら見込みを出す")
        XCTAssertEqual(TripLegRow.state(leg: domestic, estimates: returned, settled: true, offline: false, throttled: false),
                       .estimates)
        // 500km 未満の返らない区間は今までどおり「経路を地図で開く」
        let short = leg(fushimi, enkoji, "日本", "日本")
        XCTAssertEqual(TripLegRow.state(leg: short, estimates: [], settled: true, offline: false, throttled: false),
                       .unavailable)
        XCTAssertEqual(TripLegRow.state(leg: short, estimates: [], settled: false, offline: false, throttled: false),
                       .loading)
    }

    /// 長い移動のシート: Google フライト（鍵の要らない URL・都市名・日付）
    func testGoogleFlightsURL() throws {
        let url = try XCTUnwrap(TripTravel.googleFlightsURL(leg(fushimi, saoPaulo, "日本", "ブラジル"), date: "2026-12-25"))
        let c = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(c.host, "www.google.com")
        XCTAssertEqual(c.path, "/travel/flights")
        XCTAssertEqual(c.queryItems?.first { $0.name == "q" }?.value, "Flights from 京都市 to サンパウロ on 2026-12-25")
        XCTAssertFalse(url.absoluteString.contains("key="))
        let noDate = try XCTUnwrap(TripTravel.googleFlightsURL(leg(fushimi, saoPaulo), date: nil))
        XCTAssertFalse(noDate.absoluteString.contains("on%20"), "日付が無ければ渡さない")
        XCTAssertEqual(TripTravel.roughDistance(18_553), "約 18,600km")
        XCTAssertEqual(TripTravel.roughDistance(831), "約 830km")
    }

    /// 聞かない区間は Apple に聞かない（`TravelEstimator.request`）・シートは長い移動の形
    func testLongLegsAreNotAskedAndSheetShowsFlights() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func read(_ p: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + p), encoding: .utf8)
        }
        XCTAssertTrue(try read("Services/TravelEstimator.swift").contains("for leg in legs where !TripTravel.skipsDirections(leg)"))
        let sheet = try read("Features/Trips/TripLegViews.swift")
        XCTAssertTrue(sheet.contains("TripTravel.googleFlightsURL(leg, date: date)"))
        XCTAssertTrue(sheet.contains("if long {\n            longBody"))
    }
}
