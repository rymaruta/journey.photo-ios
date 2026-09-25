import XCTest
@testable import JourneyPhoto

/// 撮影スポットの索引を**手元で引く**（通信しない）。名前で探す・近くを出す。
final class OfficialSpotIndexTests: XCTestCase {

    private func spot(_ slug: String, name: String, nameEn: String? = nil, reading: String? = nil,
                      prefecture: String? = nil, city: String? = nil,
                      lat: Double? = nil, lng: Double? = nil) throws -> OfficialSpot {
        var json = "{\"spotId\":\"sp_\(slug)\",\"slug\":\"\(slug)\",\"name\":\"\(name)\",\"stage\":\"review\""
        if let nameEn { json += ",\"nameEn\":\"\(nameEn)\"" }
        if let reading { json += ",\"reading\":\"\(reading)\"" }
        if prefecture != nil || city != nil {
            let p = prefecture.map { "\"prefecture\":\"\($0)\"" }
            let c = city.map { "\"city\":\"\($0)\"" }
            json += ",\"region\":{\([p, c].compactMap { $0 }.joined(separator: ","))}"
        }
        if let lat, let lng { json += ",\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}" }
        json += "}"
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(json.utf8))
    }

    private func index() throws -> [OfficialSpot] {
        [
            try spot("takaya-jinja", name: "高屋神社", nameEn: "Takaya Shrine", reading: "たかやじんじゃ",
                     prefecture: "香川県", city: "観音寺市", lat: 34.14, lng: 133.68),
            try spot("abashiri-ryuhyo", name: "網走の流氷", nameEn: "Drift Ice of Abashiri", reading: "あばしりのりゅうひょう",
                     prefecture: "北海道", city: "網走市", lat: 44.02, lng: 144.28),
            try spot("kotohira", name: "金刀比羅宮", reading: "ことひらぐう", prefecture: "香川県", city: "仲多度郡琴平町",
                     lat: 34.18, lng: 133.81),
        ]
    }

    /// 空の語は何も当てない（「絞っていない」）
    func testEmptyQueryMatchesNothing() throws {
        XCTAssertTrue(OfficialSpotIndex.matches(try index(), query: "").isEmpty)
        XCTAssertTrue(OfficialSpotIndex.matches(try index(), query: "  \n").isEmpty)
    }

    /// 読み（ひらがな）で当たる
    func testMatchesByReading() throws {
        XCTAssertEqual(OfficialSpotIndex.matches(try index(), query: "たかや").map(\.slug), ["takaya-jinja"])
    }

    /// 全角半角・大小は区別しない（英語名でも）
    func testMatchesIgnoreWidthAndCase() throws {
        XCTAssertEqual(OfficialSpotIndex.matches(try index(), query: "ＴＡＫＡＹＡ").map(\.slug), ["takaya-jinja"])
        XCTAssertEqual(OfficialSpotIndex.matches(try index(), query: "drift ice").map(\.slug), ["abashiri-ryuhyo"])
    }

    /// 県名・市名でも当たる（同じ県のものが並ぶ）
    func testMatchesByPrefectureAndCity() throws {
        XCTAssertEqual(Set(OfficialSpotIndex.matches(try index(), query: "香川").map(\.slug)),
                       ["takaya-jinja", "kotohira"])
        XCTAssertEqual(OfficialSpotIndex.matches(try index(), query: "網走市").map(\.slug), ["abashiri-ryuhyo"])
    }

    /// **名前で当たったものが先。** 地域だけで当たったものはその後ろ
    func testNameMatchesComeFirst() throws {
        let spots = [
            try spot("kagawa-tower", name: "香川タワー", prefecture: "香川県"),
            try spot("a-shrine", name: "神社A", prefecture: "香川県"),
        ]
        XCTAssertEqual(OfficialSpotIndex.matches(spots, query: "香川").map(\.slug), ["kagawa-tower", "a-shrine"])
    }

    func testMatchesStopAtTheLimit() throws {
        let spots = try (0..<15).map { i in try spot("s\(i)", name: "神社\(i)") }
        XCTAssertEqual(OfficialSpotIndex.matches(spots, query: "神社", limit: 10).count, 10)
    }

    // MARK: - 近くの撮影スポット

    /// 自分を除いて近い順。座標の無い行は出ない。件数は limit まで
    func testNearbyIsNearestFirstWithoutSelf() throws {
        var spots = try index()
        spots.append(try spot("nowhere", name: "座標なし"))
        let near = OfficialSpotIndex.nearby(spots[0], in: spots)
        XCTAssertEqual(near.map(\.spot.slug), ["kotohira", "abashiri-ryuhyo"])
        XCTAssertLessThan(near[0].km, near[1].km)
        XCTAssertEqual(OfficialSpotIndex.nearby(spots[0], in: spots, limit: 1).count, 1)
    }

    /// 自分に座標が無ければ測れない
    func testNearbyNeedsCoordinates() throws {
        let nowhere = try spot("nowhere", name: "座標なし")
        XCTAssertTrue(OfficialSpotIndex.nearby(nowhere, in: try index() + [nowhere]).isEmpty)
    }
}
