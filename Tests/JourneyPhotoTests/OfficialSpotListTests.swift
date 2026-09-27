import XCTest
@testable import JourneyPhoto

/// 地図の「スポット」の札（板 04c 案A）
final class OfficialSpotListTests: XCTestCase {

    private func spot(_ slug: String, lat: Double?, lng: Double?, name: String? = nil,
                      stage: String = "published") throws -> OfficialSpot {
        let coords = (lat != nil && lng != nil) ? ",\"coords\":{\"lat\":\(lat!),\"lng\":\(lng!)}" : ""
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(
            "{\"spotId\":\"sp_\(slug)\",\"slug\":\"\(slug)\",\"name\":\"\(name ?? slug)\",\"stage\":\"\(stage)\"\(coords)}".utf8))
    }

    private func photo(_ id: String, spot: String?) throws -> Photo {
        let s = spot.map { ",\"spotId\":\"sp_\($0)\"" } ?? ""
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\"\(s)}".utf8))
    }

    /// 金沢駅のあたり
    private let here = Photo.Coords(lat: 36.58, lng: 136.65)

    /// 近い順（板「撮影スポット · 近い順」）
    func testNearestFirst() throws {
        let far = try spot("far", lat: 36.56, lng: 136.66)      // 約2.5km
        let near = try spot("near", lat: 36.57, lng: 136.65)    // 約1.1km
        let rows = OfficialSpotList.rows([far, near], photos: [], from: here)
        XCTAssertEqual(rows.map(\.spot.slug), ["near", "far"])
        XCTAssertLessThan(rows[0].km ?? .infinity, rows[1].km ?? 0)
    }

    /// **下書きと座標の無い行は出さない**
    func testOnlyPublishedWithCoords() throws {
        let rows = OfficialSpotList.rows([
            try spot("draft", lat: 36.57, lng: 136.65, stage: "review"),
            try spot("nocoords", lat: nil, lng: nil),
            try spot("ok", lat: 36.57, lng: 136.65),
        ], photos: [], from: here)
        XCTAssertEqual(rows.map(\.spot.slug), ["ok"])
    }

    /// 写真の数は、その撮影スポットを付けて投稿された写真
    func testCountsLinkedPhotos() throws {
        let rows = OfficialSpotList.rows([try spot("a", lat: 36.57, lng: 136.65)],
                                         photos: [try photo("1", spot: "a"), try photo("2", spot: "a"),
                                                  try photo("3", spot: "b"), try photo("4", spot: nil)],
                                         from: here)
        XCTAssertEqual(rows.first?.photoCount, 2)
    }

    /// 起点が無ければ名前の順・距離は出さない
    func testNoCenterSortsByName() throws {
        // 入力は名前の逆順（並べ替えを外すと落ちる）
        let rows = OfficialSpotList.rows([try spot("b", lat: 36.0, lng: 136.0, name: "b-spot"),
                                          try spot("a", lat: 35.0, lng: 135.0, name: "a-spot")],
                                         photos: [], from: nil)
        XCTAssertEqual(rows.map(\.spot.name), ["a-spot", "b-spot"])
        XCTAssertNil(rows.first?.km)
    }
}
