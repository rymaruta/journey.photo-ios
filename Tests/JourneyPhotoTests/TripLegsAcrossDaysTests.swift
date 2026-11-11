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
        let legs = TripTravel.planLegs([[("伏見稲荷大社", fushimi, 1)], [("一乗寺 圓光寺", enkoji, 2)], []])
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
        let legs = TripTravel.planLegs([[("伏見稲荷大社", fushimi, 1)], [], [("x", nil, 2)], [("金閣寺", kinkakuji, 3)]])
        XCTAssertEqual(legs.map(\.count), [0, 0, 0, 1])
        XCTAssertEqual(legs[3][0].from.name, "伏見稲荷大社")
    }

    /// 同じ日の区間は今までどおり。日をまたぐ区間はその日の頭に1つだけ
    func testSameDayLegsStayAndCrossLegComesFirst() {
        let legs = TripTravel.planLegs([[("A", fushimi, 1), ("B", enkoji, 2)], [("C", kinkakuji, 3), ("D", fushimi, 4)]])
        XCTAssertEqual(legs[0].map(\.crossesDay), [false])
        XCTAssertEqual(legs[1].map(\.crossesDay), [true, false])
        XCTAssertEqual(legs[1][0].from.name, "B", "前の日の**最後の**場所から")
    }

    /// 同じ座標の2か所の間は出さない（日をまたいでも、同じ日でも）
    func testSameCoordinatesMakeNoLeg() {
        XCTAssertEqual(TripTravel.planLegs([[("宿", fushimi, 1)], [("伏見稲荷大社", fushimi, 2)]]).map(\.count), [0, 0])
        XCTAssertEqual(TripTravel.legs([("A", fushimi, 1), ("A'", fushimi, 2)]).count, 0)
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
}
