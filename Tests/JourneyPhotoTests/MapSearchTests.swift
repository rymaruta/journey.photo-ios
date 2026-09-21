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

    private func takaya() throws -> Spot {
        try JSONDecoder.api.decode(Spot.self, from: Data("""
        {"spotId":"sp_a1","slug":"takaya-jinja","name":"高屋神社",
         "aliases":["天空の鳥居","Takaya Shrine"],
         "coords":{"lat":34.14,"lng":133.68}}
        """.utf8))
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
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(query: "パリ"), spots: [])), ["p1", "p2", "p3"])
        // 逆向きにも当たる（「パリ, フランス」と打って「パリ」の写真が残る）
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(query: "パリ, フランス"), spots: [])), ["p1", "p2"])
        // 全角半角・大小は区別しない
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(query: "ﾊﾟﾘ"), spots: [])), ["p1", "p2", "p3"])
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(query: "helsinki"), spots: [])), ["p4"])
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(query: "  "), spots: [])).count, 4)
    }

    /// スポットの名前・別名は台帳を通してだけ当たる。**台帳が無ければ当たらない**
    func testQueryMatchesSpotNameAndAliasThroughLedger() throws {
        let photos = [
            try photo("p1", spotId: "sp_a1", lat: 34.14, lng: 133.68),
            try photo("p2", place: "香川", lat: 34.20, lng: 133.70),
        ]
        let ledger = [try takaya()]
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(query: "天空の鳥居"), spots: ledger)), ["p1"])
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(query: "takaya"), spots: ledger)), ["p1"])
        XCTAssertTrue(MapSearch.photos(photos, filter: .init(query: "天空の鳥居"), spots: []).isEmpty)
        // 台帳の別のスポットを持つ写真は、名前が当たっても拾わない
        let other = try photo("p3", spotId: "sp_zz", lat: 34.15, lng: 133.69)
        XCTAssertEqual(ids(MapSearch.photos(photos + [other], filter: .init(query: "高屋神社"), spots: ledger)), ["p1"])
    }

    /// カテゴリは綴りではなく鍵で。nil は全件
    func testCategoryFiltersByKeyAndNilMeansAll() throws {
        let photos = [
            try photo("p1", category: "建築", lat: 1, lng: 1),
            try photo("p2", category: "architecture", lat: 2, lng: 2),
            try photo("p3", category: "風景", lat: 3, lng: 3),
        ]
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(category: nil), spots: [])), ["p1", "p2", "p3"])
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(category: "建築"), spots: [])), ["p1", "p2"])
        XCTAssertTrue(MapSearch.photos(photos, filter: .init(category: "動物"), spots: []).isEmpty)
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
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(frame: frame), spots: [])), ["in"])
    }

    /// 座標の無い写真はどの条件でも出ない（地図に置けないものをリストにも出さない）
    func testDropsPhotosWithoutCoordinates() throws {
        let photos = [
            try photo("p1", place: "パリ", category: "風景"),
            try photo("p2", place: "パリ", category: "風景", lat: 48.85, lng: 2.35),
        ]
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(), spots: [])), ["p2"])
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(query: "パリ"), spots: [])), ["p2"])
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(category: "風景"), spots: [])), ["p2"])
    }

    /// 札の「詳細を見る」は台帳に実在するスポットにだけ、重複なしで
    func testSpotsForPinAreDistinctAndOnlyFromLedger() throws {
        let photos = [
            try photo("p1", spotId: "sp_a1", lat: 34.14, lng: 133.68),
            try photo("p2", spotId: "sp_a1", lat: 34.14, lng: 133.68),
            try photo("p3", spotId: "sp_none", lat: 34.14, lng: 133.68),
            try photo("p4", lat: 34.14, lng: 133.68),
        ]
        // 台帳に他のスポットがあっても、**写真が指しているもの**だけ
        let other = try JSONDecoder.api.decode(Spot.self, from: Data(
            "{\"spotId\":\"sp_zz\",\"slug\":\"zz\",\"name\":\"別の場所\"}".utf8))
        XCTAssertEqual(MapSearch.spots(for: photos, in: [other, try takaya()]).map(\.spotId), ["sp_a1"])
        XCTAssertTrue(MapSearch.spots(for: photos, in: []).isEmpty)
    }

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
