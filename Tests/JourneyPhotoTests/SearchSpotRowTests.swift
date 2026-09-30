import XCTest
@testable import JourneyPhoto

/// 「探す」の撮影スポットの節（2026-09-30 のレビュー: 「銀山温泉」で写真0件・ガイドが案内されない）
final class SearchSpotRowTests: XCTestCase {
    private func spot(_ json: String) throws -> OfficialSpot {
        try JSONDecoder().decode(OfficialSpot.self, from: Data(json.utf8))
    }

    func testSubtitleSaysGuideAndPlace() throws {
        let ginzan = try spot(#"{"spotId":"sp_92dc681b0f47","slug":"ginzan-onsen","name":"銀山温泉","reading":"ぎんざんおんせん","stage":"published","region":{"prefecture":"山形県","city":"尾花沢市"}}"#)
        XCTAssertTrue(SearchView.spotSubtitle(ginzan).hasSuffix("山形県 尾花沢市"))
        XCTAssertEqual(OfficialSpotIndex.matches([ginzan], query: "銀山温泉").map(\.slug), ["ginzan-onsen"])
        XCTAssertEqual(OfficialSpotIndex.matches([ginzan], query: "ぎんざん").map(\.slug), ["ginzan-onsen"])
    }

    func testAbroadStartsWithCountry() throws {
        let v = try spot(#"{"spotId":"sp_000000000001","slug":"versailles","name":"ヴェルサイユ宮殿","stage":"published","region":{"city":"ヴェルサイユ","country":"フランス"}}"#)
        XCTAssertTrue(SearchView.spotSubtitle(v).hasSuffix("フランス ヴェルサイユ"))
    }

    /// 撮影スポットの節は「すべて」「撮影地」のときだけ（タグで「山」→山形県、を出さない）
    func testSpotsShowOnlyForAllAndPlaces() {
        XCTAssertTrue(SearchScope.all.showsSpots)
        XCTAssertTrue(SearchScope.places.showsSpots)
        XCTAssertFalse(SearchScope.tags.showsSpots)
        XCTAssertFalse(SearchScope.photos.showsSpots)
        XCTAssertFalse(SearchScope.people.showsSpots)
    }
}
