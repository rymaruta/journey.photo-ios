import XCTest
@testable import JourneyPhoto

/// 「旅した距離」。**実際に移動した距離ではない**（指示書 8-3）。
/// Web（`lib/utils/journey.ts` の `haversineKm`）と同じ計算かを見張る。
final class TravelDistanceTests: XCTestCase {

    private func photo(_ id: String, date: String?, lat: Double?, lng: Double?) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\""]
        if let date { fields.append("\"date\":\"\(date)\"") }
        if let lat, let lng { fields.append("\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// 東京→大阪はおよそ 400km（大円距離）。Web と同じ式かを確かめる
    func testKnownDistance() {
        let tokyo = Photo.Coords(lat: 35.68, lng: 139.76)
        let osaka = Photo.Coords(lat: 34.69, lng: 135.50)
        let km = TravelDistance.kilometers(from: tokyo, to: osaka)
        XCTAssertEqual(km, 400, accuracy: 15)
    }

    /// 古い順につなぐ（並びが変われば距離も変わる）
    func testConnectsOldestFirst() throws {
        let photos = [
            try photo("new", date: "2026-05-03", lat: 34.69, lng: 135.50),
            try photo("old", date: "2026-05-01", lat: 35.68, lng: 139.76),
        ]
        XCTAssertEqual(TravelDistance.total(of: photos), 400, accuracy: 15)
    }

    /// **座標の無い写真は数えない**（撮っていない区間は飛ぶ）
    func testPhotosWithoutCoordsAreSkipped() throws {
        let photos = [
            try photo("a", date: "2026-05-01", lat: 35.68, lng: 139.76),
            try photo("none", date: "2026-05-02", lat: nil, lng: nil),
            try photo("b", date: "2026-05-03", lat: 34.69, lng: 135.50),
        ]
        XCTAssertEqual(TravelDistance.total(of: photos), 400, accuracy: 15)
    }

    /// **日時の読めない写真も入れない。** つなぐ順が決まらない写真を
    /// 「いちばん古い場所」として数えると、そこから1脚ぶん距離が増える
    /// （Web 側が踏んでいる穴）
    func testPhotosWithoutADateAreSkipped() throws {
        let photos = [
            try photo("a", date: "2026-05-01", lat: 35.68, lng: 139.76),
            try photo("b", date: "2026-05-02", lat: 34.69, lng: 135.50),
            try photo("undated", date: nil, lat: 60.17, lng: 24.94),
        ]
        XCTAssertEqual(TravelDistance.total(of: photos), 400, accuracy: 15)
    }

    /// 1点だけ、あるいは0点なら 0（区間が無い）
    func testFewerThanTwoPointsIsZero() throws {
        XCTAssertEqual(TravelDistance.total(of: []), 0)
        XCTAssertEqual(TravelDistance.total(of: [try photo("a", date: "2026-05-01", lat: 1, lng: 1)]), 0)
    }

    func testFormatsWithSeparators() {
        XCTAssertEqual(TravelDistance.formatted(74164.4), "74,164")
    }
}
