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
        // 向きを見る（2026-10-07）: 「パリ, フランス」と打って、撮影地が広い「パリ」だけの写真は出さない
        // （撮影地のページ・Web の `photoIsInLocation` と同じ）
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(query: "パリ, フランス"))), ["p2"])
        // 全角半角・大小は区別しない
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(query: "ﾊﾟﾘ"))), ["p1", "p2", "p3"])
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(query: "helsinki"))), ["p4"])
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(query: "  "))).count, 4)
    }

    /// 🔴 2026-10-07: 地図の「福岡」で宮城県の写真（蔵王キツネ村・大字「福岡八宮」）へ飛んでいた。
    /// 撮影地は名前として当てる（`LocationMatch.photoIsIn`）。探すの「撮影地」・リストの札も同じ
    func testFukuokaDoesNotMatchFukuokaYatsumiyaInMiyagi() throws {
        let photos = [
            try photo("zao", place: "蔵王キツネ村, 南蔵王七ヶ宿線, 福岡八宮, 白石市, 宮城県, 989-0733, 日本",
                      lat: 38.0, lng: 140.5),
            try photo("hakata", place: "博多駅, 博多区, 福岡市, 福岡県, 日本", lat: 33.59, lng: 130.42),
            try photo("fukuoka", place: "福岡", lat: 33.6, lng: 130.4),
        ]
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(query: "福岡"))), ["hakata", "fukuoka"])
        XCTAssertEqual(ids(SearchScope.places.photos(photos, query: "福岡")), ["hakata", "fukuoka"])
        XCTAssertEqual(ids(RegionList.filter(photos: photos, spots: [], query: "福岡", category: nil).photos),
                       ["hakata", "fukuoka"])
        XCTAssertEqual(ids(MapSearch.photos(photos, filter: .init(query: "宮城"))), ["zao"])
    }

    /// 2026-10-07（レビュー）: 名前として当てる（`photoIsIn`）と、ふつうの部分の名前・打ちかけの語が
    /// 外れていた。字の部分一致に戻し、長い行政区分の名前の途中（東京都の「京都」）だけを外す
    func testPartialNamesAndTypingStillMatch() throws {
        func hit(_ place: String, _ query: String) throws -> Bool {
            MapSearch.matches(try photo("x", place: place, lat: 35, lng: 139), needle: query)
        }
        XCTAssertTrue(try hit("東京駅", "東京"))
        XCTAssertTrue(try hit("京都駅", "京都"))
        XCTAssertTrue(try hit("富士山", "富士"))
        XCTAssertTrue(try hit("嵐山渡月橋", "嵐山"))
        XCTAssertTrue(try hit("清水寺", "清水"))
        XCTAssertTrue(try hit("渋谷スクランブル交差点", "渋谷"))
        XCTAssertTrue(try hit("Kyoto-shi, Japan", "kyoto"))
        XCTAssertTrue(try hit("フィレンツェ, トスカーナ州, イタリア", "トスカーナ"))
        XCTAssertTrue(try hit("Tokyo", "Toky"))
        XCTAssertTrue(try hit("Helsinki, Finland", "helsin"))
        XCTAssertTrue(try hit("東京都 渋谷区", "渋谷"))
        XCTAssertTrue(try hit("博多駅, 博多区, 福岡市, 福岡県, 日本", "福岡"))
        // 長い行政区分の名前の途中は外す
        XCTAssertFalse(try hit("東京都中央区", "京都"))
        XCTAssertFalse(try hit("東京都", "京都"))
        XCTAssertFalse(try hit("銀座, 中央区, 東京都, 日本", "京都"))
        // 撮影地に都道府県の正式名が無くても、長い市の名前の途中は外す（大阪府の河内長野市は長野ではない）
        XCTAssertFalse(try hit("滝畑ダム, 河内長野市", "長野"))
        XCTAssertTrue(try hit("善光寺, 長野市", "長野"))
        // 打った県名と別の県の撮影地は外す（蔵王キツネ村・大字「福岡八宮」）
        XCTAssertFalse(try hit("蔵王キツネ村, 南蔵王七ヶ宿線, 福岡八宮, 白石市, 宮城県, 989-0733, 日本", "福岡"))
    }

    /// 🔴 2026-10-09: 直前が行政区分の字（都道府県市区町村郡）の名前が外れていた。
    /// 「東京都渋谷区」で「渋谷」、「香川県観音寺市」で「観音寺」が出なかった。
    /// 直前が行政区分の字なら、名前の切れ目として数える（`LocationMatch.nameIn` の「前」と同じ）
    func testNameRightAfterAdminSuffixMatches() throws {
        func hit(_ place: String, _ query: String) throws -> Bool {
            MapSearch.matches(try photo("x", place: place, lat: 35, lng: 139), needle: query)
        }
        XCTAssertTrue(try hit("東京都渋谷区", "渋谷"))
        XCTAssertTrue(try hit("東京都中央区", "中央区"))
        XCTAssertTrue(try hit("香川県観音寺市", "観音寺"))
        XCTAssertTrue(LocationMatch.looselyContains("東京都渋谷区", "渋谷"))
        XCTAssertEqual(ids(SearchScope.places.photos(
            [try photo("k", place: "香川県観音寺市", lat: 34.1, lng: 133.6)], query: "観音寺")), ["k"])
        // 前からの外し方はそのまま
        XCTAssertFalse(try hit("東京都中央区", "京都"))
        XCTAssertFalse(try hit("滝畑ダム, 河内長野市", "長野"))
        XCTAssertFalse(LocationMatch.looselyContains("東京都中央区", "京都"))
        XCTAssertFalse(LocationMatch.looselyContains("河内長野市", "長野"))
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
