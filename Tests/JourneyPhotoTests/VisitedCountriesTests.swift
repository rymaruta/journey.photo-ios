import XCTest
@testable import JourneyPhoto

/// 訪れた国・地域（モック2-3）。
final class VisitedCountriesTests: XCTestCase {

    private func photo(_ id: String, location: String?, spotId: String? = nil) throws -> Photo {
        let l = location.map { ",\"location\":\"\($0)\"" } ?? ""
        let s = spotId.map { ",\"spotId\":\"\($0)\"" } ?? ""
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\"\(l)\(s)}".utf8))
    }

    /// 書かれていれば当たる（日本語・英語とも）
    func testCountryWrittenInTheLocationCounts() throws {
        XCTAssertEqual(VisitedCountries.country(in: "サントリーニ島, ギリシャ"), "ギリシャ")
        XCTAssertEqual(VisitedCountries.country(in: "Paris, France"), "フランス")
    }

    /// 🔴 **地名から国を推測しない。** 当て損なうと、書いていない国が
    /// 実績として並ぶ
    func testPlaceNamesAreNotGuessed() throws {
        XCTAssertNil(VisitedCountries.country(in: "山中湖"))
        XCTAssertNil(VisitedCountries.country(in: "バルセロナ"))
        XCTAssertNil(VisitedCountries.country(in: ""))
    }

    /// **同じ国は1つ。** 「パリ」「パリ, フランス」で2にならない
    func testSameCountryCountsOnce() throws {
        let photos = [try photo("a", location: "パリ, フランス"),
                      try photo("b", location: "ニース, フランス"),
                      try photo("c", location: "パリ")]
        XCTAssertEqual(VisitedCountries.count(in: photos), 1)
    }

    /// **長い名前から当てる。** 「南アフリカ」が「アフリカ」の一部に
    /// 引っぱられないこと（表に短い語を足したときの保険）
    func testLongerNamesWinFirst() {
        XCTAssertEqual(VisitedCountries.country(in: "ケープタウン, 南アフリカ"), "南アフリカ")
        XCTAssertEqual(VisitedCountries.country(in: "オークランド, ニュージーランド"), "ニュージーランド")
    }

    /// スポット台帳の国も見る（台帳は国を持っている）
    func testSpotLedgerCountryIsUsed() throws {
        let spot = try JSONDecoder.api.decode(Spot.self, from: Data(#"""
        {"spotId":"s1","slug":"takaya","name":"高屋神社","region":{"country":"日本"}}
        """#.utf8))
        let photos = [try photo("a", location: "天空の鳥居", spotId: "s1")]
        XCTAssertEqual(VisitedCountries.count(in: photos, spots: [spot]), 1)
        // 台帳が無ければ数えない（推測しない）
        XCTAssertEqual(VisitedCountries.count(in: photos), 0)
    }

    /// 表に同じ国を2行書かない（二重に数える）
    func testTableHasNoDuplicates() {
        let ja = VisitedCountries.table.map(\.ja)
        XCTAssertEqual(Set(ja).count, ja.count)
        let en = VisitedCountries.table.map(\.en)
        XCTAssertEqual(Set(en).count, en.count)
    }
}
