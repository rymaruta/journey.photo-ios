import XCTest
@testable import JourneyPhoto

/// 地図で選んだ地点の写真（デザイン 04b）。
final class PlacePhotosTests: XCTestCase {

    private func photo(_ id: String, location: String? = nil,
                       lat: Double? = nil, lng: Double? = nil,
                       createdAt: String? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"/uploads/\(id).jpg\""]
        if let location { fields.append("\"location\":\"\(location)\"") }
        if let lat, let lng { fields.append("\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}") }
        if let createdAt { fields.append("\"createdAt\":\"\(createdAt)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// 金沢21世紀美術館のあたり（丸める前の座標）
    private let museum = Photo.Coords(lat: 36.5610, lng: 136.6582)

    /// 名前の当たった写真が先（新しい順）、続いて座標の近い写真
    func testNamedPhotosComeFirstThenNearby() throws {
        let oldNamed = try photo("old", location: "金沢21世紀美術館", createdAt: "2026-01-01")
        let newNamed = try photo("new", location: "石川 金沢21世紀美術館", createdAt: "2026-05-01")
        let near = try photo("near", lat: 36.56, lng: 136.66)
        let found = PlacePhotos.photos([near, oldNamed, newNamed], name: "金沢21世紀美術館", at: museum)
        XCTAssertEqual(found.map(\.id), ["new", "old", "near"])
    }

    /// 🔴 **丸めた座標でも落とさない。** その場所で撮った写真は、約1kmの
    /// 格子点（小数第2位）に保存されている
    func testRoundedCoordsOfThePlaceAreIncluded() throws {
        let rounded = try photo("rounded", lat: 36.56, lng: 136.66)
        XCTAssertEqual(PlacePhotos.photos([rounded], name: nil, at: museum).map(\.id), ["rounded"])
    }

    /// 遠い写真は入らない（金沢駅は約2km）
    func testFarPhotosAreExcluded() throws {
        let station = try photo("station", lat: 36.58, lng: 136.65)
        XCTAssertTrue(PlacePhotos.photos([station], name: "金沢21世紀美術館", at: museum).isEmpty)
    }

    /// 名前と座標の両方に当たっても1回だけ
    func testNoDuplicates() throws {
        let both = try photo("both", location: "金沢21世紀美術館", lat: 36.56, lng: 136.66)
        XCTAssertEqual(PlacePhotos.photos([both], name: "金沢21世紀美術館", at: museum).map(\.id), ["both"])
    }

    /// **範囲を丸めの粗さより狭くしない**
    func testRadiusIsNotFinerThanTheRounding() {
        XCTAssertGreaterThanOrEqual(PlacePhotos.radiusKm, 1)
    }
}
