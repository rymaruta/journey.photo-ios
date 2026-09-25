import XCTest
@testable import JourneyPhoto

/// 地図の地点を名前で拾い直すとき、**押した場所の近くの結果だけ**を採る
final class PlaceLookupTests: XCTestCase {

    private let museum = Photo.Coords(lat: 36.5610, lng: 136.6582)   // 金沢21世紀美術館

    func testPicksTheNearestWithinRange() {
        let candidates = [
            Photo.Coords(lat: 36.5700, lng: 136.6582),  // 約1km 北（範囲外）
            Photo.Coords(lat: 36.5620, lng: 136.6582),  // 約110m
            Photo.Coords(lat: 36.5612, lng: 136.6582),  // 約22m
        ]
        XCTAssertEqual(PlaceLookup.nearestIndex(of: candidates, to: museum), 2)
    }

    /// 同じ名前の別の店舗（遠い）は採らない
    func testIgnoresSameNameFarAway() {
        let candidates = [Photo.Coords(lat: 35.6812, lng: 139.7671)]  // 東京
        XCTAssertNil(PlaceLookup.nearestIndex(of: candidates, to: museum))
    }

    func testEmptyIsNil() {
        XCTAssertNil(PlaceLookup.nearestIndex(of: [], to: museum))
    }
}
