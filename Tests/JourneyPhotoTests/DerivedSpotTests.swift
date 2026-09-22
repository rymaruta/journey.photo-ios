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

    // MARK: - 「近くの撮影スポット」に同じものを2度出さない（run 55 の絵）

    /// 🔴 **広い撮影地を「近く」に出さない。** run 55 の実機の絵で
    /// 「フランス ヴェルサイユ」の近くに **「フランス」が 1km 以内**と
    /// 出ていた。広い方は見出しの下（`broader`）に既に出ているし、
    /// その写真はこの画面の一覧にも入っている
    func testBroaderPlaceIsNotAlsoNearby() throws {
        let photos = [
            try photo("v", location: "フランス ヴェルサイユ", lat: 48.80, lng: 2.13),
            try photo("f", location: "フランス", lat: 48.80, lng: 2.13),
            try photo("p", location: "パリ", lat: 48.86, lng: 2.35),
        ]
        let here = try XCTUnwrap(DerivedSpot.place("フランス ヴェルサイユ", in: photos))
        XCTAssertTrue(here.broader.contains("フランス"))
        let near = DerivedSpot.nearby(here, in: photos).map(\.place.label)
        XCTAssertFalse(near.contains("フランス"), "広い撮影地が「近く」にも出ている: \(near)")
    }

    /// **狭い方も出さない。** 「パリ」から見た「パリ, フランス」の写真は、
    /// この画面の一覧（ゆるい一致）に既に入っている
    func testNarrowerPlaceIsNotNearbyEither() throws {
        let photos = [
            try photo("a", location: "パリ", lat: 48.86, lng: 2.35),
            try photo("b", location: "パリ, フランス", lat: 48.86, lng: 2.35),
            try photo("c", location: "東京", lat: 35.68, lng: 139.77),
        ]
        let here = try XCTUnwrap(DerivedSpot.place("パリ", in: photos))
        XCTAssertEqual(DerivedSpot.nearby(here, in: photos).map(\.place.label), ["東京"])
    }

    /// 🔴 **綴り違いの2枚札を並べない。** run 55 の絵では「パリ」と
    /// 「パリ, フランス」が別々の札で、どちらも約253km と出ていた。
    /// 写真が丸ごと他方に入っている方を落とす（残るのは広い方）
    func testNearbyDropsTheSpellingThatIsSwallowed() throws {
        let photos = [
            try photo("v", location: "フランス ヴェルサイユ", lat: 48.80, lng: 2.13),
            try photo("p1", location: "パリ", lat: 48.86, lng: 2.35),
            try photo("p2", location: "パリ, フランス", lat: 48.86, lng: 2.35),
        ]
        let here = try XCTUnwrap(DerivedSpot.place("フランス ヴェルサイユ", in: photos))
        let near = DerivedSpot.nearby(here, in: photos).map(\.place.label)
        XCTAssertEqual(near, ["パリ"], "綴り違いが2つ並んでいる: \(near)")
    }

    /// **関係の無い地点は落とさない**（落としすぎの見張り）
    func testUnrelatedPlacesSurvive() throws {
        let photos = [
            try photo("a", location: "東京", lat: 35.68, lng: 139.77),
            try photo("b", location: "横浜", lat: 35.44, lng: 139.64),
            try photo("c", location: "大阪", lat: 34.69, lng: 135.50),
        ]
        let here = try XCTUnwrap(DerivedSpot.place("東京", in: photos))
        XCTAssertEqual(DerivedSpot.nearby(here, in: photos).map(\.place.label), ["横浜", "大阪"])
    }

    /// 🔴 **広い撮影地の写真を、狭いスポットに数えない**（run 55 の絵で3枚）
    func testBroadPhotoIsNotCountedInTheNarrowSpot() throws {
        let place = try XCTUnwrap(DerivedSpot.place("フランス ヴェルサイユ", in: [
            try photo("v1", location: "フランス ヴェルサイユ"),
            try photo("v2", location: "フランス ヴェルサイユ"),
            try photo("f", location: "フランス"),
        ]))
        XCTAssertEqual(place.count, 2, "撮影地が「フランス」の写真まで数えている")
        XCTAssertFalse(place.photos.contains { $0.id == "f" })
    }
}
