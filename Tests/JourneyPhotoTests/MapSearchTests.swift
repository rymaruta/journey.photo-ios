import XCTest
@testable import JourneyPhoto

/// 撮影地マップの絞り込み。**地図とリストが同じ答えから描かれること**と、
/// 数えていない一致を作らないことを縛る。
final class MapSearchTests: XCTestCase {

    private func photo(_ id: String, place: String? = nil, spotId: String? = nil,
                       category: String? = nil, lat: Double? = nil, lng: Double? = nil) throws -> Photo {
        var fields: [String] = ["\"id\":\"\(id)\"", "\"src\":\"/uploads/\(id).jpg\""]
        if let place { fields.append("\"location\":\"\(place)\"") }
        if let spotId { fields.append("\"spotId\":\"\(spotId)\"") }
        if let category { fields.append("\"category\":\"\(category)\"") }
        if let lat, let lng { fields.append("\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }


    private func ids(_ photos: [Photo]) -> [String] { photos.map(\.id) }

    /// 撮影地の文字列は `PhotoQuery.photos(in: .location)` と同じゆるさで当てる。
    /// 空の条件は全件。
    func testQueryMatchesLocationLoosely() throws {
        let photos = [
            try photo("p1", place: "パリ", lat: 48.85, lng: 2.35),
            try photo("p2", place: "パリ, フランス", lat: 48.86, lng: 2.36),
            try photo("p3", place: "オペラ・ガルニエ（パリ）", lat: 48.87, lng: 2.33),
            try photo("p4", place: "Helsinki", lat: 60.17, lng: 24.94),
        ]
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(query: "パリ"))), ["p1", "p2", "p3"])
        // 逆向きにも当たる（「パリ, フランス」と打って「パリ」の写真が残る）
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(query: "パリ, フランス"))), ["p1", "p2"])
        // 全角半角・大小は区別しない
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(query: "ﾊﾟﾘ"))), ["p1", "p2", "p3"])
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(query: "helsinki"))), ["p4"])
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(query: "  "))).count, 4)
    }

    /// スポットの名前・別名は台帳を通してだけ当たる。**台帳が無ければ当たらない**
    /// ⚠️ **スポットの名前・別名では引けなくなった。** 本番が
    /// 「台帳を持たない」と決めた（`photo-gallery/docs/spot-master.md`）ので、
    /// 引く先が無い。当たるのは**撮影地の文字列だけ**
    func testQueryMatchesOnlyTheLocationText() throws {
        let photos = [try photo("p1", place: "香川県 観音寺市 高屋神社", lat: 34.1, lng: 133.6)]
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(query: "高屋神社"))), ["p1"])
        XCTAssertTrue(MapSearch.photos(photos, filter: .init(query: "天空の鳥居")).isEmpty)
    }

    /// カテゴリは綴りではなく鍵で。nil は全件
    func testCategoryFiltersByKeyAndNilMeansAll() throws {
        let photos = [
            try photo("p1", category: "建築", lat: 1, lng: 1),
            try photo("p2", category: "architecture", lat: 2, lng: 2),
            try photo("p3", category: "風景", lat: 3, lng: 3),
        ]
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(category: nil))), ["p1", "p2", "p3"])
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(category: "建築"))), ["p1", "p2"])
        XCTAssertTrue(MapSearch.photos(photos, filter: .init(category: "動物")).isEmpty)
    }

    /// 範囲は幅の**半分**で切る。緯度と経度を別々に
    func testFrameContainsOnlyPointsInside() {
        let frame = MapFraming.Frame(latitude: 35.68, longitude: 139.76, latitudeSpan: 0.10, longitudeSpan: 0.10)
        XCTAssertTrue(MapSearch.contains(frame, latitude: 35.68, longitude: 139.76))
        XCTAssertTrue(MapSearch.contains(frame, latitude: 35.73, longitude: 139.76))
        XCTAssertTrue(MapSearch.contains(frame, latitude: 35.68, longitude: 139.71))
        XCTAssertFalse(MapSearch.contains(frame, latitude: 35.74, longitude: 139.76))
        XCTAssertFalse(MapSearch.contains(frame, latitude: 35.68, longitude: 139.82))
    }

    /// 「このエリアを検索」は範囲の中の写真だけ
    func testFrameFilterKeepsOnlyPhotosInside() throws {
        let photos = [
            try photo("in", lat: 35.68, lng: 139.76),
            try photo("out", lat: 36.50, lng: 139.76),
        ]
        let frame = MapFraming.Frame(latitude: 35.68, longitude: 139.76, latitudeSpan: 0.10, longitudeSpan: 0.10)
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(frame: frame))), ["in"])
    }

    /// 座標の無い写真はどの条件でも出ない（地図に置けないものをリストにも出さない）
    func testDropsPhotosWithoutCoordinates() throws {
        let photos = [
            try photo("p1", place: "パリ", category: "風景"),
            try photo("p2", place: "パリ", category: "風景", lat: 48.85, lng: 2.35),
        ]
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init())), ["p2"])
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(query: "パリ"))), ["p2"])
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(category: "風景"))), ["p2"])
    }

    /// 札の「詳細を見る」は台帳に実在するスポットにだけ、重複なしで

    /// チップに出す種類は `all` の並びで、実際にある語だけ
    func testPresentCategoriesFollowChoiceOrder() throws {
        let photos = [
            try photo("p1", category: "food"),
            try photo("p2", category: "建築"),
            try photo("p3", category: "写真"),
        ]
        XCTAssertEqual(CategoryChoices.present(in: photos), ["建築", "食べ物"])
    }
}
