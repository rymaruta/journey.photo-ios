import XCTest
@testable import JourneyPhoto

/// 旅行プランの1日を地図で見る（`TripDayMap`）。
///
/// 固定したいのは:
///  1. 番号は日程の順番（座標の無い場所も数える）
///  2. 経路の起点は「座標のある前の場所」。1か所目は今いる場所から（nil）
///  3. 座標の無い場所だけの日は、地図を出さない
final class TripDayMapTests: XCTestCase {

    private func spot(_ id: String, name: String, lat: Double?) throws -> OfficialSpot {
        var fields = ["\"spotId\":\"\(id)\"", "\"slug\":\"\(id)\"", "\"name\":\"\(name)\"", "\"stage\":\"published\""]
        if let lat { fields.append("\"coords\":{\"lat\":\(lat),\"lng\":135.0}") }
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    func testNumbersFollowTheDayAndRoutesStartAtThePreviousLocatedStop() throws {
        let a = try spot("sp_a", name: "A", lat: 35.0)
        let b = try spot("sp_b", name: "B", lat: nil)       // 座標なし
        let c = try spot("sp_c", name: "C", lat: 35.1)
        let day = TripDay(items: [.spot(spotId: "sp_a", note: nil), .spot(spotId: "sp_b", note: nil),
                                  .spot(spotId: "sp_c", note: nil)])
        let stops = TripDayMap.stops(of: day, index: [a, b, c], places: [])
        XCTAssertEqual(stops.map(\.number), [1, 2, 3])
        XCTAssertEqual(stops.map(\.name), ["A", "B", "C"])
        XCTAssertNil(stops[0].from)                          // 1か所目は今いる場所から
        XCTAssertEqual(stops[1].from, a.coords)
        XCTAssertNil(stops[1].coords)                        // 座標の無い場所はピンなし
        XCTAssertEqual(stops[2].from, a.coords, "座標の無い B を起点にしている")
        XCTAssertEqual(stops[2].fromName, "A")
        XCTAssertTrue(TripDayMap.hasPins(stops))
    }

    /// 索引に無い（引けない）場所は鍵のまま・座標なし。座標の無い場所だけなら地図を出さない
    func testUnknownItemsHaveNoPin() {
        let day = TripDay(items: [.spot(spotId: "sp_gone", note: nil), .location(slug: "nowhere", note: nil)])
        let stops = TripDayMap.stops(of: day, index: [], places: [])
        XCTAssertEqual(stops.map(\.name), ["sp_gone", "nowhere"])
        XCTAssertFalse(TripDayMap.hasPins(stops))
        XCTAssertFalse(TripDayMap.hasPins([]))
    }
}
