import XCTest
@testable import JourneyPhoto

/// 「行きたい場所」を地図で見る（`SavedSpotsMap`）。
///
/// どれを地図に置き、どれを下の一覧に残すか。枠は**全部が入る範囲**（地図のタブの
/// 「いちばん重い塊」とは違う）で、日付変更線をまたいでも狭く囲む
final class SavedSpotsMapTests: XCTestCase {

    private func spot(_ slug: String, name: String, coords: (Double, Double)? = nil,
                      stage: String = "published") throws -> OfficialSpot {
        let c = coords.map { ",\"coords\":{\"lat\":\($0.0),\"lng\":\($0.1)}" } ?? ""
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(
            "{\"spotId\":\"sp_\(slug)\",\"slug\":\"\(slug)\",\"name\":\"\(name)\",\"stage\":\"\(stage)\",\"region\":{\"prefecture\":\"京都府\"}\(c)}".utf8))
    }

    private func place(_ slug: String, coords: Photo.Coords?) -> DerivedSpot.Place {
        DerivedSpot.Place(label: slug.capitalized, slug: slug, photos: [], broader: ["日本"],
                          categories: [], coords: coords)
    }

    // MARK: - どれを地図に出すか

    /// 座標のあるものは地図へ、無いもの（索引に無い鍵・座標の無い行・撮影地の座標なし）は一覧へ。
    /// 並びは一覧と同じ（撮影地が先・スポットが後）
    func testSplitsByCoordinates() throws {
        let index = [try spot("fushimi-inari-taisha", name: "伏見稲荷大社", coords: (34.97, 135.77)),
                     try spot("no-coords", name: "座標なし")]
        let rows = OfficialWishlist.rows(keys: ["SPOT-fushimi-inari-taisha", "SPOT-no-coords", "SPOT-gone"],
                                         index: index)
        let places = [place("kyoto", coords: Photo.Coords(lat: 35.0, lng: 135.76)),
                      place("nowhere", coords: nil)]
        let split = SavedSpotsMap.split(places: places, officialRows: rows)

        XCTAssertEqual(split.pinned.map(\.key), ["kyoto", "SPOT-fushimi-inari-taisha"])
        XCTAssertEqual(Set(split.unplaced.map(\.key)), ["nowhere", "SPOT-no-coords", "SPOT-gone"])
        XCTAssertEqual(split.count, 5)
        XCTAssertFalse(split.isEmpty)

        let gone = try XCTUnwrap(split.unplaced.first { $0.key == "SPOT-gone" })
        XCTAssertFalse(gone.canOpen, "索引に無い鍵は開く先が無い")
        let noCoords = try XCTUnwrap(split.unplaced.first { $0.key == "SPOT-no-coords" })
        XCTAssertTrue(noCoords.canOpen, "座標が無くても索引にあれば画面は開ける")
        XCTAssertTrue(split.pinned.allSatisfy(\.canOpen), "地図に置いたピンは必ず開ける")
    }

    /// 壊れた座標（範囲の外・数でない）は地図に置かず、一覧に残す
    func testBrokenCoordinatesGoToTheList() {
        let places = [place("far", coords: Photo.Coords(lat: 91, lng: 0)),
                      place("nan", coords: Photo.Coords(lat: .nan, lng: 10)),
                      place("ok", coords: Photo.Coords(lat: -33.86, lng: 151.21))]
        let split = SavedSpotsMap.split(places: places, officialRows: [])
        XCTAssertEqual(split.pinned.map(\.key), ["ok"])
        XCTAssertEqual(split.unplaced.map(\.key), ["far", "nan"])
    }

    /// 同じ鍵は1つのピンに（重ねて置かない）
    func testDuplicateKeysAreDropped() {
        let a = place("kyoto", coords: Photo.Coords(lat: 35, lng: 135))
        let split = SavedSpotsMap.split(places: [a, a], officialRows: [])
        XCTAssertEqual(split.pinned.count, 1)
    }

    /// 0件は空（画面は「撮影スポットを探す」を出す）
    func testEmpty() {
        let split = SavedSpotsMap.split(places: [], officialRows: [])
        XCTAssertTrue(split.isEmpty)
        XCTAssertNil(SavedSpotsMap.frame(for: split.pinned.compactMap(\.coords)))
    }

    /// 撮影スポットのピンは Commons の写真、無ければ nil（真鍮の丸）。地域は副題に
    func testOfficialItemCarriesRegionAndDraft() throws {
        let rows = OfficialWishlist.rows(keys: ["SPOT-a"],
                                         index: [try spot("a", name: "A寺", coords: (35, 135), stage: "review")])
        let item = try XCTUnwrap(SavedSpotsMap.split(places: [], officialRows: rows).pinned.first)
        XCTAssertEqual(item.subtitle, "京都府")
        XCTAssertNil(item.imageURL)
        XCTAssertTrue(item.isDraft)
        XCTAssertTrue(SavedSpotsMap.spokenLabel(item).contains("A寺"))
    }

    // MARK: - 枠

    /// 全部が入る（離れた1か所も外に出さない）。余白つき
    func testFrameContainsEveryPoint() throws {
        let points = [Photo.Coords(lat: 35.0, lng: 135.7),   // 京都
                      Photo.Coords(lat: 34.9, lng: 135.8),
                      Photo.Coords(lat: 43.06, lng: 141.35)] // 札幌（離れた1か所）
        let frame = try XCTUnwrap(SavedSpotsMap.frame(for: points))
        for p in points {
            XCTAssertLessThanOrEqual(abs(p.lat - frame.latitude), frame.latitudeSpan / 2 + 1e-9)
            XCTAssertLessThanOrEqual(abs(p.lng - frame.longitude), frame.longitudeSpan / 2 + 1e-9)
        }
        XCTAssertEqual(frame.latitudeSpan, (43.06 - 34.9) * MapFraming.padding, accuracy: 1e-9)
    }

    /// 1か所だけでも寄りすぎない（いちばん狭い幅）
    func testSinglePointUsesMinimumSpan() throws {
        let frame = try XCTUnwrap(SavedSpotsMap.frame(for: [Photo.Coords(lat: 35, lng: 135)]))
        XCTAssertEqual(frame.latitude, 35)
        XCTAssertEqual(frame.longitude, 135)
        XCTAssertEqual(frame.latitudeSpan, MapFraming.minimumSpan)
        XCTAssertEqual(frame.longitudeSpan, MapFraming.minimumSpan)
    }

    /// 日付変更線をまたぐ（日本とハワイ）なら太平洋側で狭く囲む——地球を1周近く回らない
    func testFrameWrapsAcrossTheDateLine() throws {
        let frame = try XCTUnwrap(SavedSpotsMap.frame(for: [Photo.Coords(lat: 35, lng: 139.7),
                                                            Photo.Coords(lat: 21.3, lng: -157.8)]))
        let width = (180 - 139.7) + (180 - 157.8)   // 62.5°
        XCTAssertEqual(frame.longitudeSpan, width * MapFraming.padding, accuracy: 1e-9)
        // 中心は線の近く（東経 171° あたり）
        XCTAssertEqual(frame.longitude, 139.7 + width / 2, accuracy: 1e-9)
    }

    /// 中心が西経側に来たら -180〜180 に戻す
    func testWrappedCenterIsNormalized() throws {
        let frame = try XCTUnwrap(SavedSpotsMap.frame(for: [Photo.Coords(lat: 0, lng: 170),
                                                            Photo.Coords(lat: 0, lng: -150)]))
        XCTAssertEqual(frame.longitude, -170, accuracy: 1e-9)
        XCTAssertEqual(frame.longitudeSpan, 40 * MapFraming.padding, accuracy: 1e-9)
    }

    /// 南北に広い並びでも、枠が極を越えない（越えた枠は地図が受け付けない）。点の広がりより狭くはしない
    func testLatitudeSpanStaysInsideThePoles() throws {
        let frame = try XCTUnwrap(SavedSpotsMap.frame(for: [Photo.Coords(lat: 80, lng: 0),
                                                            Photo.Coords(lat: -10, lng: 0)]))
        XCTAssertLessThanOrEqual(frame.latitude + frame.latitudeSpan / 2, 90 + 1e-9)
        XCTAssertGreaterThanOrEqual(frame.latitudeSpan, 90)
    }

    /// 極のすぐそばの1点でも寄りすぎない（幅は縮めず、中心を極から離す）。点は枠の中
    func testNearPoleSinglePointShiftsTheCenter() throws {
        let frame = try XCTUnwrap(SavedSpotsMap.frame(for: [Photo.Coords(lat: 89.99, lng: 0)]))
        XCTAssertEqual(frame.latitudeSpan, MapFraming.minimumSpan, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(frame.latitude + frame.latitudeSpan / 2, 90 + 1e-9)
        XCTAssertLessThanOrEqual(abs(89.99 - frame.latitude), frame.latitudeSpan / 2 + 1e-9)
        let south = try XCTUnwrap(SavedSpotsMap.frame(for: [Photo.Coords(lat: -89.99, lng: 0)]))
        XCTAssertGreaterThanOrEqual(south.latitude - south.latitudeSpan / 2, -90 - 1e-9)
    }

    /// 開く先のヒントは撮影地と撮影スポットで言い分ける
    func testOpenHintDependsOnTarget() throws {
        let rows = OfficialWishlist.rows(keys: ["SPOT-a"], index: [try spot("a", name: "A寺", coords: (35, 135))])
        let official = try XCTUnwrap(SavedSpotsMap.split(places: [], officialRows: rows).pinned.first)
        XCTAssertEqual(SavedSpotsMap.openHint(official), "撮影スポットの画面を開きます")
        let placeItem = SavedSpotsMap.item(place("kyoto", coords: Photo.Coords(lat: 35, lng: 135)))
        XCTAssertEqual(SavedSpotsMap.openHint(placeItem), "撮影地の画面を開きます")
    }

    /// 経度の幅は1周（360°）を越えない
    func testLongitudeSpanIsCapped() throws {
        let points = stride(from: -180.0, to: 180.0, by: 30).map { Photo.Coords(lat: 0, lng: $0) }
        let frame = try XCTUnwrap(SavedSpotsMap.frame(for: points))
        XCTAssertLessThanOrEqual(frame.longitudeSpan, 360)
    }

    /// 壊れた座標は枠に入れない
    func testFrameIgnoresBrokenCoordinates() throws {
        let frame = try XCTUnwrap(SavedSpotsMap.frame(for: [Photo.Coords(lat: 35, lng: 135),
                                                            Photo.Coords(lat: 200, lng: 135)]))
        XCTAssertEqual(frame.latitude, 35)
    }

    // MARK: - 文言

    func testSummary() {
        let a = place("a", coords: Photo.Coords(lat: 1, lng: 1))
        let b = place("b", coords: nil)
        XCTAssertEqual(SavedSpotsMap.summary(SavedSpotsMap.split(places: [a], officialRows: [])), "地図に 1 か所")
        XCTAssertEqual(SavedSpotsMap.summary(SavedSpotsMap.split(places: [a, b], officialRows: [])),
                       "地図に 1 か所 · 場所の分からないもの 1 か所")
    }
}
