import XCTest
@testable import JourneyPhoto

/// 地図の「スポット」「リスト」の行の2行目。写真を読み込む前に「写真 0枚」と言わない
final class MapSpotSublineTests: XCTestCase {
    private func row(km: Double?, count: Int) throws -> OfficialSpotList.Row {
        let spot = try JSONDecoder().decode(OfficialSpot.self, from: Data(#"{"spotId":"sp_000000000001","slug":"ginzan-onsen","name":"銀山温泉","stage":"published"}"#.utf8))
        return OfficialSpotList.Row(spot: spot, km: km, photoCount: count)
    }

    func testBeforeLoadOmitsCount() throws {
        XCTAssertEqual(PhotoMapView.spotSubline(try row(km: 0.8, count: 0), loaded: false),
                       NearbyPhotos.label(km: 0.8))
        XCTAssertEqual(PhotoMapView.spotSubline(try row(km: nil, count: 0), loaded: false), "")
    }

    func testAfterLoadSaysCount() throws {
        let photos = L("写真 0枚", "0 photos")
        XCTAssertEqual(PhotoMapView.spotSubline(try row(km: 0.8, count: 0), loaded: true),
                       "\(NearbyPhotos.label(km: 0.8)) · \(photos)")
        XCTAssertEqual(PhotoMapView.spotSubline(try row(km: nil, count: 0), loaded: true), photos)
    }
}
