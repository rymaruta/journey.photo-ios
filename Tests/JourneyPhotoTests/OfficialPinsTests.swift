import XCTest
@testable import JourneyPhoto

/// 地図に置く撮影スポットのピン。
///
/// **1,417件を常時 Annotation で置かない。** 寄せたとき（緯度幅 0.5° ≈ 55km
/// 未満）だけ、枠の中を近い順に最大60本。名前で絞っているときは倍率に
/// 関係なく当たったものを出す（owner が名前で探す入口）。
final class OfficialPinsTests: XCTestCase {

    private func spot(_ slug: String, lat: Double?, lng: Double?, name: String? = nil,
                      reading: String? = nil, stage: String = "review") throws -> OfficialSpot {
        let coords = (lat != nil && lng != nil) ? ",\"coords\":{\"lat\":\(lat!),\"lng\":\(lng!)}" : ""
        let r = reading.map { ",\"reading\":\"\($0)\"" } ?? ""
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(
            "{\"spotId\":\"sp_\(slug)\",\"slug\":\"\(slug)\",\"name\":\"\(name ?? slug)\",\"stage\":\"\(stage)\"\(coords)\(r)}".utf8))
    }

    private func frame(lat: Double, lng: Double, span: Double) -> MapFraming.Frame {
        MapFraming.Frame(latitude: lat, longitude: lng, latitudeSpan: span, longitudeSpan: span)
    }

    /// 枠が届く前は何も置かない
    func testNoFrameNoPins() throws {
        let spots = [try spot("a", lat: 35.0, lng: 135.0)]
        XCTAssertTrue(OfficialPins.visible(spots, frame: nil).isEmpty)
    }

    /// **引いているときは置かない。** 日本全体では重なるだけ
    func testWideFrameShowsNothing() throws {
        let spots = [try spot("a", lat: 35.0, lng: 135.0)]
        XCTAssertTrue(OfficialPins.visible(spots, frame: frame(lat: 35.0, lng: 135.0, span: 0.6)).isEmpty)
        XCTAssertTrue(OfficialPins.visible(spots, frame: frame(lat: 35.0, lng: 135.0, span: OfficialPins.maxLatitudeSpan)).isEmpty,
                      "線の上は「引いている」側")
        XCTAssertEqual(OfficialPins.visible(spots, frame: frame(lat: 35.0, lng: 135.0, span: 0.4)).count, 1)
    }

    /// 枠の中だけ・近い順・同じ距離は slug 順
    func testInsideTheFrameNearestFirst() throws {
        let spots = [
            try spot("far", lat: 35.10, lng: 135.0),
            try spot("outside", lat: 36.0, lng: 135.0),
            try spot("near-b", lat: 35.01, lng: 135.0),
            try spot("near-a", lat: 35.01, lng: 135.0),
        ]
        let pins = OfficialPins.visible(spots, frame: frame(lat: 35.0, lng: 135.0, span: 0.4))
        XCTAssertEqual(pins.map(\.slug), ["near-a", "near-b", "far"])
    }

    func testStopsAtTheLimit() throws {
        let spots = try (0..<80).map { i in
            try spot(String(format: "s%03d", i), lat: 35.0 + Double(i) * 0.001, lng: 135.0)
        }
        let pins = OfficialPins.visible(spots, frame: frame(lat: 35.0, lng: 135.0, span: 0.4))
        XCTAssertEqual(pins.count, OfficialPins.limit)
        XCTAssertEqual(pins.first?.slug, "s000", "近い順に切っていない")
    }

    /// 座標の無い行は地図に置けない
    func testSpotsWithoutCoordinatesAreNeverPins() throws {
        let spots = [try spot("nowhere", lat: nil, lng: nil), try spot("here", lat: 35.0, lng: 135.0)]
        let pins = OfficialPins.visible(spots, frame: frame(lat: 35.0, lng: 135.0, span: 0.4))
        XCTAssertEqual(pins.map(\.slug), ["here"])
        XCTAssertEqual(OfficialPins.visible(spots, frame: nil, query: "nowhere").count, 0,
                       "名前で当たっても座標が無ければ置けない")
    }

    /// ピンは下書きかどうかを持って出る（札に「下書き」と書くため）
    func testPinCarriesTheDraftFlag() throws {
        let spots = [try spot("d", lat: 35.0, lng: 135.0), try spot("p", lat: 35.0, lng: 135.0, stage: "published")]
        let pins = OfficialPins.visible(spots, frame: frame(lat: 35.0, lng: 135.0, span: 0.4))
        XCTAssertEqual(pins.first { $0.slug == "d" }?.isDraft, true)
        XCTAssertEqual(pins.first { $0.slug == "p" }?.isDraft, false)
    }

    // MARK: - 名前で絞っているとき（倍率に関係なく出す）

    /// 名前・読みで当たったものは、引いていても・枠が無くても出る
    func testQueryMatchesRegardlessOfZoom() throws {
        let spots = [
            try spot("takaya-jinja", lat: 34.14, lng: 133.68, name: "高屋神社", reading: "たかやじんじゃ"),
            try spot("other", lat: 35.0, lng: 135.0, name: "別の場所"),
        ]
        XCTAssertEqual(OfficialPins.visible(spots, frame: nil, query: "高屋").map(\.slug), ["takaya-jinja"])
        XCTAssertEqual(OfficialPins.visible(spots, frame: frame(lat: 40, lng: 140, span: 30), query: "たかや").map(\.slug),
                       ["takaya-jinja"])
        XCTAssertTrue(OfficialPins.visible(spots, frame: frame(lat: 40, lng: 140, span: 30), query: "   ").isEmpty,
                      "空白だけは「絞っていない」")
    }

    func testQueryMatchesStopAtTheLimit() throws {
        let spots = try (0..<80).map { i in
            try spot(String(format: "s%03d", i), lat: 35.0 + Double(i) * 0.001, lng: 135.0, name: "神社 \(i)")
        }
        XCTAssertEqual(OfficialPins.visible(spots, frame: nil, query: "神社").count, OfficialPins.limit)
    }

    // MARK: - 入れ替えの判断

    /// **id の集まりで比べる。** 並びが違うだけでは入れ替えない
    /// （入れ替えるたびに描き直し → カメラの知らせ → … と回る種になる）
    func testChangedComparesTheIdSet() throws {
        let a = try spot("a", lat: 35.0, lng: 135.0)
        let b = try spot("b", lat: 35.01, lng: 135.0)
        let ab = OfficialPins.visible([a, b], frame: frame(lat: 35.0, lng: 135.0, span: 0.4))
        let ba = OfficialPins.visible([b, a], frame: frame(lat: 35.02, lng: 135.0, span: 0.4))
        XCTAssertEqual(ab.map(\.slug), ["a", "b"])
        XCTAssertEqual(ba.map(\.slug), ["b", "a"])
        XCTAssertFalse(OfficialPins.changed(ab, ba), "同じ集まりを「変わった」と言っている")
        XCTAssertTrue(OfficialPins.changed(ab, Array(ab.prefix(1))))
        XCTAssertTrue(OfficialPins.changed([], ab))
        XCTAssertFalse(OfficialPins.changed([], []))
    }
}
