import XCTest
@testable import JourneyPhoto

/// 撮影地の欄に出す撮影スポットの候補（`PlaceSpotSuggestions`）。
///
/// 固定したいのは:
///  1. 欄が空なら写真の位置の近く（3km 以内）を近い順に。位置が無ければ出さない
///  2. 打った語は名前・読み・英語名に当てる（地域だけの一致は出さない）
///  3. 公開済み・座標のある場所だけ。数は3つまで
final class PlaceSpotSuggestionsTests: XCTestCase {

    private func spot(_ slug: String, name: String, reading: String? = nil, stage: String = "published",
                      lat: Double? = 34.0, lng: Double? = 133.0, prefecture: String? = nil) throws -> OfficialSpot {
        var fields = ["\"spotId\":\"sp_\(slug)\"", "\"slug\":\"\(slug)\"", "\"name\":\"\(name)\"", "\"stage\":\"\(stage)\""]
        if let reading { fields.append("\"reading\":\"\(reading)\"") }
        if let lat, let lng { fields.append("\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}") }
        if let prefecture { fields.append("\"region\":{\"prefecture\":\"\(prefecture)\"}") }
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private let here = Photo.Coords(lat: 34.10, lng: 133.60)

    func testEmptyQueryShowsNearbyPublishedSpots() throws {
        let near = try spot("near", name: "高屋神社", lat: 34.11, lng: 133.60)      // 約1km
        let nearer = try spot("nearer", name: "銭形砂絵", lat: 34.10, lng: 133.60)  // 0km
        let far = try spot("far", name: "遠い場所", lat: 34.50, lng: 133.60)         // 約44km
        let draft = try spot("draft", name: "下書き", stage: "review", lat: 34.10, lng: 133.60)
        let result = PlaceSpotSuggestions.suggestions(query: "  ", near: here, index: [far, near, draft, nearer])
        XCTAssertEqual(result.map(\.slug), ["nearer", "near"])
        XCTAssertTrue(PlaceSpotSuggestions.suggestions(query: "", near: nil, index: [nearer]).isEmpty)
    }

    func testQueryMatchesNameOrReadingButNotRegionOnly() throws {
        let a = try spot("takaya", name: "高屋神社", reading: "たかやじんじゃ", prefecture: "香川県")
        let b = try spot("other", name: "父母ヶ浜", prefecture: "香川県")
        XCTAssertEqual(PlaceSpotSuggestions.suggestions(query: "高屋", near: nil, index: [a, b]).map(\.slug), ["takaya"])
        XCTAssertEqual(PlaceSpotSuggestions.suggestions(query: "たかや", near: nil, index: [a, b]).map(\.slug), ["takaya"])
        XCTAssertTrue(PlaceSpotSuggestions.suggestions(query: "香川", near: nil, index: [a, b]).isEmpty)
    }

    /// 位置があれば近い順。数は3つまで。座標の無い場所・下書きは出さない
    func testMatchesAreOrderedByDistanceAndCapped() throws {
        let spots = try (0..<5).map { i in
            try spot("s\(i)", name: "滝\(i)", lat: 34.10 + Double(4 - i) * 0.1, lng: 133.60)
        }
        let noCoords = try spot("nc", name: "滝X", lat: nil, lng: nil)
        let draft = try spot("dr", name: "滝D", stage: "review", lat: 34.10, lng: 133.60)
        let result = PlaceSpotSuggestions.suggestions(query: "滝", near: here, index: spots + [noCoords, draft])
        XCTAssertEqual(result.map(\.slug), ["s4", "s3", "s2"])
    }

    /// 位置のある写真では、スポットを選んでも座標を入れない（写真の座標のまま・前の地名の座標も捨てる）
    func testPickingASpotKeepsThePhotoPosition() throws {
        let s = try spot("s", name: "高屋神社", lat: 34.12, lng: 133.63)
        XCTAssertNil(PlaceSpotSuggestions.coordsAfterPicking(s, photoHasPosition: true))
        XCTAssertEqual(PlaceSpotSuggestions.coordsAfterPicking(s, photoHasPosition: false), s.coords)
    }
}
