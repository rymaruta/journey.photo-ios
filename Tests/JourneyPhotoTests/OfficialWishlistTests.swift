import XCTest
@testable import JourneyPhoto

/// マイページの「行きたい」に並べる、台帳の撮影スポットの行。
///
/// 鍵（`SPOT-<slug>`・`SavedSpotKey`）を索引と突き合わせて名前を引く。
/// **索引が無くても行は出す**（押した覚えのあるものを「まだ無い」と言わない）
final class OfficialWishlistTests: XCTestCase {

    private func spot(_ slug: String, name: String, prefecture: String? = nil) throws -> OfficialSpot {
        let region = prefecture.map { ",\"region\":{\"prefecture\":\"\($0)\"}" } ?? ""
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(
            "{\"spotId\":\"sp_\(slug)\",\"slug\":\"\(slug)\",\"name\":\"\(name)\",\"stage\":\"review\"\(region)}".utf8))
    }

    /// 撮影地の鍵は入れない。索引にある鍵は名前と地域が付き、無い鍵は slug から起こした名前で行だけ
    func testRowsComeOnlyFromOfficialKeys() throws {
        let index = [try spot("takaya-jinja", name: "高屋神社", prefecture: "香川県")]
        let rows = OfficialWishlist.rows(keys: ["takaya-jinja", "SPOT-takaya-jinja", "SPOT-unknown-place"],
                                         index: index)
        XCTAssertEqual(rows.map(\.key), ["SPOT-takaya-jinja", "SPOT-unknown-place"])
        XCTAssertEqual(rows[0].name, "高屋神社")
        XCTAssertEqual(rows[0].regionLabel, "香川県")
        XCTAssertEqual(rows[0].spot?.spotId, "sp_takaya-jinja")
        XCTAssertNil(rows[1].spot, "索引に無い鍵に別の行を当てている")
        XCTAssertEqual(rows[1].name, "unknown place")
        XCTAssertNil(rows[1].regionLabel)
    }

    /// 索引が空でも（取れなかった回）、鍵のぶんは並ぶ
    func testRowsSurviveAMissingIndex() {
        let rows = OfficialWishlist.rows(keys: ["SPOT-takaya-jinja"], index: [])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].slug, "takaya-jinja")
        XCTAssertEqual(rows[0].name, "takaya jinja")
    }

    /// 壊れた鍵（`SPOT-`）も落とさない——落とすと本人が外せない
    func testBrokenKeyStillGetsARow() {
        let rows = OfficialWishlist.rows(keys: ["SPOT-"], index: [])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].name, L("名前のないスポット", "Unnamed spot"))
    }

    /// 並びは索引にあるものが先、そのあと名前順（毎回同じ並びにする）
    func testIndexedRowsFirstThenByName() throws {
        let index = [try spot("b-spot", name: "い"), try spot("a-spot", name: "あ")]
        let rows = OfficialWishlist.rows(keys: ["SPOT-zzz", "SPOT-b-spot", "SPOT-a-spot", "SPOT-aaa"], index: index)
        XCTAssertEqual(rows.map(\.key), ["SPOT-a-spot", "SPOT-b-spot", "SPOT-aaa", "SPOT-zzz"])
    }

    func testNoKeysNoRows() {
        XCTAssertTrue(OfficialWishlist.rows(keys: [], index: []).isEmpty)
        XCTAssertTrue(OfficialWishlist.rows(keys: ["paris"], index: []).isEmpty)
    }
}
