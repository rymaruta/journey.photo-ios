import XCTest
@testable import JourneyPhoto

/// 現在地の周りの写真（モック3-7）。
final class NearbyPhotosTests: XCTestCase {

    private func photo(_ id: String, lat: Double?, lng: Double?) throws -> Photo {
        let c = (lat != nil && lng != nil) ? ",\"coords\":{\"lat\":\(lat!),\"lng\":\(lng!)}" : ""
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\"\(c)}".utf8))
    }

    /// 東京駅のあたり
    private let here = Photo.Coords(lat: 35.68, lng: 139.77)

    /// 近い順。**遠いものは範囲で落ちる**
    func testSortedByDistanceAndClipped() throws {
        let near = try photo("near", lat: 35.69, lng: 139.77)      // 約1km
        let mid = try photo("mid", lat: 35.72, lng: 139.77)        // 約4km
        let far = try photo("far", lat: 35.45, lng: 139.63)        // 約27km
        let found = NearbyPhotos.photos([far, mid, near], near: here, withinKm: 5)
        XCTAssertEqual(found.map(\.photo.id), ["near", "mid"])
        XCTAssertLessThan(found[0].km, found[1].km)
    }

    /// **座標の無い写真は入らない。** 距離を測りようが無いものを
    /// 「近い」と言わない
    func testPhotosWithoutCoordsAreNotNearby() throws {
        let found = NearbyPhotos.photos([try photo("no", lat: nil, lng: nil)],
                                        near: here, withinKm: 50)
        XCTAssertTrue(found.isEmpty)
    }

    /// 🔴 **持っていない精度を言わない。** 座標は約1kmに丸めてあるので、
    /// 1km 未満を「0.3km」とは書かない
    func testSubKilometreIsNotSpelledOut() {
        let label = NearbyPhotos.label(km: 0.3)
        XCTAssertEqual(label, L("1km以内", "within 1 km"))
        XCTAssertFalse(label.contains("0.3"))
    }

    /// 距離には必ず「約」を付ける（丸めた座標から出した値なので）
    func testDistancesAreMarkedApproximate() {
        XCTAssertTrue(NearbyPhotos.label(km: 3.14).contains(L("約", "about")))
        XCTAssertTrue(NearbyPhotos.label(km: 42).contains(L("約", "about")))
    }

    /// **1km 未満の範囲は選ばせない**（丸めより細かい線は引けない）
    func testNoRadiusFinerThanTheRounding() {
        XCTAssertFalse(NearbyPhotos.radiusChoices.contains { $0 < 1 })
    }

    /// 見出しは**数えた件数**（「8件」のような決め打ちを置かない）
    func testHeadingCountsWhatWasFound() {
        XCTAssertTrue(NearbyPhotos.heading(radiusKm: 5, count: 0).contains("0"))
        XCTAssertTrue(NearbyPhotos.heading(radiusKm: 5, count: 12).contains("12"))
    }
}
