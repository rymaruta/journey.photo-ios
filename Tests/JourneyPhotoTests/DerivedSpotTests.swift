import XCTest
@testable import JourneyPhoto

/// 撮影スポット（モック5）。**台帳を持たず、写真から導く**。
final class DerivedSpotTests: XCTestCase {

    private func photo(_ id: String, location: String?, likes: Int = 0,
                       category: String? = nil, lat: Double? = nil, lng: Double? = nil,
                       createdAt: String = "2026-01-01T00:00:00Z") throws -> Photo {
        let l = location.map { ",\"location\":\"\($0)\"" } ?? ""
        let c = category.map { ",\"category\":\"\($0)\"" } ?? ""
        let g = (lat != nil && lng != nil) ? ",\"coords\":{\"lat\":\(lat!),\"lng\":\(lng!)}" : ""
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\",\"likes\":\(likes),\"createdAt\":\"\(createdAt)\"\(l)\(c)\(g)}".utf8))
    }

    /// **鍵は Web と同じスラッグ**（サーバーの「行きたい場所」と突き合わさる）
    func testKeyIsTheLocationSlug() throws {
        let place = try XCTUnwrap(DerivedSpot.place("フランス ヴェルサイユ", in: [
            try photo("a", location: "フランス ヴェルサイユ"),
        ]))
        XCTAssertEqual(place.slug, "フランス-ヴェルサイユ")
    }

    /// **ゆるく集める**（Web の `photosInCollection` と同じ約束）。
    /// 「パリ」に「パリ, フランス」の写真も入る
    func testGathersLooselyLikeTheWeb() throws {
        let place = try XCTUnwrap(DerivedSpot.place("パリ", in: [
            try photo("a", location: "パリ"),
            try photo("b", location: "パリ, フランス"),
            try photo("c", location: "東京"),
        ]))
        XCTAssertEqual(place.count, 2)
    }

    /// **1枚も無い撮影地は作らない**（空の地点を出さない）
    func testNoPlaceWithoutPhotos() throws {
        XCTAssertNil(DerivedSpot.place("行ったことのない場所", in: [try photo("a", location: "パリ")]))
        XCTAssertNil(DerivedSpot.place("  ", in: [try photo("a", location: "パリ")]))
    }

    /// 代表の1枚は**いちばん多く押された写真**（数えた値）
    func testCoverIsTheMostLiked() throws {
        let place = try XCTUnwrap(DerivedSpot.place("パリ", in: [
            try photo("a", location: "パリ", likes: 3),
            try photo("b", location: "パリ", likes: 30),
        ]))
        XCTAssertEqual(place.cover?.id, "b")
    }

    /// 🔴 **より広い撮影地を推測しない。** 同じ一覧に実際に在って、
    /// 含む関係にあるものだけ
    func testBroaderOnlyFromWhatExists() throws {
        let photos = [
            try photo("a", location: "パリ, フランス"),
            try photo("b", location: "パリ"),
            try photo("c", location: "フランス"),
            try photo("d", location: "東京"),
        ]
        let broader = DerivedSpot.broader(of: "パリ, フランス", in: photos)
        XCTAssertEqual(Set(broader), ["パリ", "フランス"])
        XCTAssertFalse(broader.contains("東京"))
        // 一覧に無い国名を勝手に足さない
        XCTAssertFalse(broader.contains("ヨーロッパ"))

        // 🔴 **向きを守る。** 「パリ」から見て「パリ, フランス」は
        // **狭い方**なので、広い方には入らない。
        // ⚠️ 最初この確かめが無く、「含む関係を両向きにする」変異で
        // **テストが緑のまま**だった（実測）。向きが崩れると、狭い地点が
        // 「より広い撮影地」として並ぶ
        let fromParis = DerivedSpot.broader(of: "パリ", in: photos)
        XCTAssertFalse(fromParis.contains("パリ, フランス"), "狭い方を広い方に入れている")
        XCTAssertTrue(fromParis.isEmpty, "「パリ」より広い撮影地は一覧に無い")
    }

    /// **自分自身は広い方に入れない**
    func testBroaderExcludesItself() throws {
        XCTAssertTrue(DerivedSpot.broader(of: "パリ", in: [try photo("a", location: "パリ")]).isEmpty)
    }

    /// 近くの撮影地は**座標を持っているものだけ**・近い順
    func testNearbyNeedsCoordinates() throws {
        let photos = [
            try photo("here", location: "東京", lat: 35.68, lng: 139.77),
            try photo("near", location: "横浜", lat: 35.44, lng: 139.64),
            try photo("far", location: "大阪", lat: 34.69, lng: 135.50),
            try photo("nocoords", location: "福岡"),
        ]
        let here = try XCTUnwrap(DerivedSpot.place("東京", in: photos))
        let near = DerivedSpot.nearby(here, in: photos)
        XCTAssertEqual(near.map(\.place.label), ["横浜", "大阪"])
        XCTAssertLessThan(near[0].km, near[1].km)
    }

    /// 座標が無い地点では、近くを出さない（測りようが無い）
    func testNoNearbyWithoutOwnCoordinates() throws {
        let photos = [try photo("a", location: "福岡"), try photo("b", location: "東京", lat: 35.6, lng: 139.7)]
        let here = try XCTUnwrap(DerivedSpot.place("福岡", in: photos))
        XCTAssertTrue(DerivedSpot.nearby(here, in: photos).isEmpty)
    }

    /// 一覧は**枚数の多い順**・同じ撮影地は1つ
    func testAllPlacesAreUniqueAndSorted() throws {
        let places = DerivedSpot.all(in: [
            try photo("a", location: "パリ"),
            try photo("b", location: "東京"),
            try photo("c", location: "東京"),
            try photo("d", location: nil),
        ])
        XCTAssertEqual(places.first?.label, "東京")
        XCTAssertEqual(places.count, 2, "撮影地の無い写真が地点になっている")
    }

    /// 分類のチップは**写真が持っているものだけ**（多い順）
    func testCategoriesComeFromThePhotos() throws {
        let cats = DerivedSpot.categories(of: [
            try photo("a", location: "パリ", category: "建築"),
            try photo("b", location: "パリ", category: "建築"),
            try photo("c", location: "パリ", category: "風景"),
            try photo("d", location: "パリ"),
        ])
        XCTAssertEqual(cats.first, "建築")
        XCTAssertEqual(cats.count, 2)
    }

    // MARK: - 画面を開いてよい地点か（`openable`）

    /// **1枚だけの地点には、スポットの画面を出さない。**
    /// その写真の個別ページと中身が同じになる
    func testOnePhotoPlaceDoesNotOpen() throws {
        let photos = [try photo("a", location: "三条市, 日本")]
        XCTAssertNotNil(DerivedSpot.place("三条市, 日本", in: photos))
        XCTAssertNil(DerivedSpot.openable("三条市, 日本", in: photos))
    }

    /// 2枚あれば開く（線は `minPhotosForSpotPage`）
    func testTwoPhotosOpen() throws {
        let place = try XCTUnwrap(DerivedSpot.openable("山中湖", in: [
            try photo("a", location: "山中湖"),
            try photo("b", location: "山中湖"),
        ]))
        XCTAssertEqual(place.count, 2)
    }

    /// **ゆるい一致で数える。** 「パリ」は「パリ, フランス」の1枚と
    /// 合わせて2枚なので開く——`place` と同じ数え方であること
    func testCountsLooselyLikeThePlaceItself() throws {
        XCTAssertNotNil(DerivedSpot.openable("パリ", in: [
            try photo("a", location: "パリ"),
            try photo("b", location: "パリ, フランス"),
        ]))
    }

    /// 撮影地が書かれていない写真しか無ければ開かない
    func testNoLocationDoesNotOpen() throws {
        XCTAssertNil(DerivedSpot.openable("", in: [try photo("a", location: nil)]))
        XCTAssertNil(DerivedSpot.openable("山中湖", in: [try photo("a", location: nil)]))
    }
}
