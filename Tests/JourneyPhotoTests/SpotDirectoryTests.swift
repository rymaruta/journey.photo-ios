import XCTest
@testable import JourneyPhoto

/// 撮影スポット台帳の引き当て。Web（`lib/utils/spots.ts`）と同じ規則を守る。
final class SpotDirectoryTests: XCTestCase {

    private func spot(_ json: String) throws -> Spot {
        try JSONDecoder.api.decode(Spot.self, from: Data(json.utf8))
    }

    private func photo(_ id: String, spotId: String? = nil, place: String? = nil,
                       likes: Int? = nil, published: Bool? = nil, date: String? = nil) throws -> Photo {
        var fields: [String] = ["\"id\":\"\(id)\"", "\"src\":\"/uploads/\(id).jpg\""]
        if let spotId { fields.append("\"spotId\":\"\(spotId)\"") }
        if let place { fields.append("\"location\":\"\(place)\"") }
        if let likes { fields.append("\"likes\":\(likes)") }
        if let published { fields.append("\"published\":\(published)") }
        if let date { fields.append("\"createdAt\":\"\(date)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func takaya() throws -> Spot {
        try spot("""
        {"spotId":"sp_a1","slug":"takaya-jinja","name":"高屋神社",
         "aliases":["天空の鳥居","Takaya Shrine"],
         "address":"香川県観音寺市高屋町2800",
         "region":{"country":"日本","prefecture":"香川県","city":"観音寺市"},
         "coords":{"lat":34.14,"lng":133.68},"category":"神社"}
        """)
    }

    func testNormalizeFoldsBracketsAndWidth() throws {
        XCTAssertEqual(SpotDirectory.normalize("オペラ・ガルニエ（パリ）"),
                       SpotDirectory.normalize("オペラ・ガルニエ (パリ)"))
        XCTAssertEqual(SpotDirectory.normalize(" Takaya  Shrine "), "takayashrine")
    }

    func testFindsByIdAndSlug() throws {
        let spots = [try takaya()]
        XCTAssertEqual(SpotDirectory.spot(id: "sp_a1", in: spots)?.name, "高屋神社")
        XCTAssertNil(SpotDirectory.spot(id: "sp_none", in: spots))
        XCTAssertNil(SpotDirectory.spot(id: nil, in: spots))
        XCTAssertEqual(SpotDirectory.spot(slug: "takaya-jinja", in: spots)?.spotId, "sp_a1")
    }

    func testSearchFindsAliases() throws {
        let spots = [try takaya()]
        XCTAssertEqual(SpotDirectory.search("天空の鳥居", in: spots).map(\.spotId), ["sp_a1"])
        XCTAssertEqual(SpotDirectory.search("takaya", in: spots).map(\.spotId), ["sp_a1"])
    }

    func testSearchRanksExactThenPrefixThenContains() throws {
        let spots = [
            try spot("{\"spotId\":\"x1\",\"slug\":\"a\",\"name\":\"海浜公園前\"}"),
            try spot("{\"spotId\":\"x2\",\"slug\":\"b\",\"name\":\"国営ひたち海浜公園\"}"),
            try spot("{\"spotId\":\"x3\",\"slug\":\"c\",\"name\":\"海浜公園\"}"),
        ]
        XCTAssertEqual(SpotDirectory.search("海浜公園", in: spots).map(\.spotId), ["x3", "x1", "x2"])
    }

    func testEmptyQueryReturnsNothing() throws {
        XCTAssertTrue(SpotDirectory.search("   ", in: [try takaya()]).isEmpty)
    }

    func testNearbyRespectsRadius() throws {
        let spots = [try takaya()]
        XCTAssertEqual(SpotDirectory.nearby(.init(lat: 34.15, lng: 133.69), in: spots, radiusKm: 5).count, 1)
        XCTAssertTrue(SpotDirectory.nearby(.init(lat: 36.40, lng: 140.59), in: spots, radiusKm: 5).isEmpty)
    }

    func testNearbySkipsSpotsWithoutCoords() throws {
        let noCoords = try spot("{\"spotId\":\"n1\",\"slug\":\"n\",\"name\":\"座標なし\"}")
        XCTAssertTrue(SpotDirectory.nearby(.init(lat: 0, lng: 0), in: [noCoords], radiusKm: 20000).isEmpty)
    }

    func testPhotosCountOnlyLinkedOnes() throws {
        let spot = try takaya()
        let photos = [
            try photo("p1", spotId: "sp_a1", date: "2026-01-01"),
            try photo("p2", spotId: "sp_a1", date: "2026-03-01"),
            try photo("p3", spotId: "sp_a1", published: false, date: "2026-02-01"),
            try photo("p4", place: "高屋神社", date: "2026-04-01"),
        ]
        // 名前が同じだけの p4 は数えない（枚数を水増ししない）
        XCTAssertEqual(SpotDirectory.photos(of: spot, in: photos).map(\.id), ["p2", "p1"])
    }

    func testCoverPrefersTheLedgerChoice() throws {
        let spot = try self.spot("""
        {"spotId":"sp_a1","slug":"s","name":"高屋神社","coverPhotoId":"p1"}
        """)
        let photos = [try photo("p1", spotId: "sp_a1", likes: 1), try photo("p2", spotId: "sp_a1", likes: 99)]
        XCTAssertEqual(SpotDirectory.cover(of: spot, in: photos)?.id, "p1")
    }

    func testCoverFallsBackToMostLikedAndIsNilWhenEmpty() throws {
        let spot = try takaya()
        let photos = [try photo("p1", spotId: "sp_a1", likes: 1), try photo("p2", spotId: "sp_a1", likes: 99)]
        XCTAssertEqual(SpotDirectory.cover(of: spot, in: photos)?.id, "p2")
        XCTAssertNil(SpotDirectory.cover(of: spot, in: []))
    }

    /// 台帳の JSON は写真と同じ静的ファイルから来る。**足りない項目で落ちない**
    func testDecodesMinimalLedgerRow() throws {
        let minimal = try spot("{\"spotId\":\"m1\",\"slug\":\"m\",\"name\":\"最小\"}")
        XCTAssertNil(minimal.coords)
        XCTAssertNil(minimal.address)
        XCTAssertEqual(minimal.region?.line, nil)
    }

    func testRegionLineSkipsEmptyLevels() throws {
        let s = try spot("{\"spotId\":\"r1\",\"slug\":\"r\",\"name\":\"x\",\"region\":{\"country\":\"フランス\",\"city\":\"パリ\"}}")
        XCTAssertEqual(s.region?.line, "フランス パリ")
    }
}
