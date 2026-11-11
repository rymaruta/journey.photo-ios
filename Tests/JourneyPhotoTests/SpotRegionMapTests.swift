import XCTest
@testable import JourneyPhoto

/// 探すの「撮影スポット」の段の地図（札 #524 の続き・2026-11-11 owner「iOS 側にもこの機能欲しい」）。
/// 地方の当たり・塗る県・地図の札の中身・「写真｜地図」で段の高さが変わらないこと
final class SpotRegionMapTests: XCTestCase {

    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/JourneyPhoto/Resources")

    private func geometry() throws -> PrefectureMapGeometry {
        let data = try Data(contentsOf: Self.resources.appendingPathComponent("japan-prefectures.json"))
        let shapes = try JSONDecoder().decode([ShareCardMap.Shape].self, from: data)
        return try XCTUnwrap(PrefectureMapGeometry.build(shapes: shapes))
    }

    private func spot(_ slug: String, prefecture: String, lat: Double, lng: Double,
                      image: Bool = false) throws -> OfficialSpot {
        let picture = image
            ? ",\"image\":{\"url\":\"https://journey-photo.com/images/spots/\(slug).jpg\",\"author\":\"A\",\"license\":\"CC BY 4.0\"}"
            : ""
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(
            "{\"spotId\":\"sp_\(slug)\",\"slug\":\"\(slug)\",\"name\":\"\(slug)\",\"stage\":\"published\",\"region\":{\"prefecture\":\"\(prefecture)\"}\(picture),\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}}".utf8))
    }

    /// 北海道 5件（写真つき 2件）・東京 1件。九州には無い
    private func spots() throws -> [OfficialSpot] {
        [
            try spot("zz-sapporo", prefecture: "北海道", lat: 43.06, lng: 141.35),
            try spot("akan", prefecture: "北海道", lat: 43.45, lng: 144.10, image: true),
            try spot("asahidake", prefecture: "北海道", lat: 43.66, lng: 142.85),
            try spot("tomita", prefecture: "北海道", lat: 43.42, lng: 142.42, image: true),
            try spot("goryokaku", prefecture: "北海道", lat: 41.80, lng: 140.76),
            try spot("meiji", prefecture: "東京都", lat: 35.676, lng: 139.699),
        ]
    }

    /// 地図の上の点（地図の枠の pt）。投影 → 単位の空間 → 画面
    private func screen(_ g: PrefectureMapGeometry, _ lat: Double, _ lng: Double, container: CGSize) -> CGPoint {
        VisitedMapViewport().screenPoint(forUnit: g.projection.point(latitude: lat, longitude: lng),
                                         content: g.size, container: container)
    }

    // MARK: - 当たり

    /// 押した点の県の地方。**撮影スポットの無い地方は選ばない**（押しても何もしない）
    func testRegionAtPointPicksRegionWithSpots() throws {
        let g = try geometry()
        let groups = SpotPrefectureIndex.groups(spots: try spots())
        let size = CGSize(width: SearchSpotIndexSection.mapWidth(for: g), height: SearchSpotIndexSection.cardColumnHeight)
        XCTAssertEqual(SpotRegionMap.region(at: screen(g, 43.06, 141.35, container: size), container: size,
                                            geometry: g, groups: groups), "北海道")
        XCTAssertEqual(SpotRegionMap.region(at: screen(g, 35.69, 139.70, container: size), container: size,
                                            geometry: g, groups: groups), "関東")
        XCTAssertNil(SpotRegionMap.region(at: screen(g, 33.59, 130.40, container: size), container: size,
                                          geometry: g, groups: groups), "撮影スポットの無い九州を選んだ")
        // 海の真ん中は何も選ばない
        XCTAssertNil(SpotRegionMap.region(at: screen(g, 38.0, 133.0, container: size), container: size,
                                          geometry: g, groups: groups))
    }

    /// 塗るのは選んだ（なぞっている）地方の県だけ
    func testHighlightedIsRegionPrefectures() {
        XCTAssertEqual(SpotRegionMap.highlighted("四国"), ["徳島県", "香川県", "愛媛県", "高知県"])
        XCTAssertTrue(SpotRegionMap.highlighted(nil).isEmpty)
        XCTAssertTrue(SpotRegionMap.highlighted("存在しない").isEmpty)
    }

    // MARK: - 札

    /// 上位の名前は「代表写真がある → 台帳の並び」で 4 件。全部出せないときは「ほか」
    func testRegionCardNames() throws {
        let groups = SpotPrefectureIndex.groups(spots: try spots())
        let hokkaido = try XCTUnwrap(groups.first { $0.region.name == "北海道" })
        XCTAssertEqual(hokkaido.names, ["akan", "tomita", "zz-sapporo", "asahidake"])
        XCTAssertEqual(SpotPrefectureIndex.namesLine(hokkaido),
                       L("akan・tomita・zz-sapporo・asahidake ほか", "akan, tomita, zz-sapporo, asahidake, and more"))
        let kanto = try XCTUnwrap(groups.first { $0.region.name == "関東" })
        XCTAssertEqual(SpotPrefectureIndex.namesLine(kanto), "meiji", "全部出せたら「ほか」を付けない")
        XCTAssertEqual(SpotRegionMap.seeAll(hokkaido),
                       L("北海道の撮影スポットをすべて見る", "See all photo spots in Hokkaido"))
    }

    /// 札の「すべて見る」の先は、その地方の県だけ（北から・県の見出しつき）
    func testRegionScopeShowsOnlyThatRegion() throws {
        let sections = RegionList.sections(photos: [], spots: try spots() + [
            try spot("minatomirai", prefecture: "神奈川県", lat: 35.457, lng: 139.632),
        ], from: nil)
        let kanto = OfficialSpotIndexView.shown(sections, scope: .region("関東"))
        XCTAssertEqual(kanto.map(\.title), ["東京都", "神奈川県"])
        XCTAssertTrue(OfficialSpotIndexView.shown(sections, scope: .region("九州・沖縄")).isEmpty)
        XCTAssertFalse(OfficialSpotIndexView.isPrefecture(.region("関東")))
        XCTAssertTrue(OfficialSpotIndexView.isPrefecture(.prefecture("東京都")))
    }

    // MARK: - 段の高さ

    /// 🔴 **「写真｜地図」で段の高さが変わらない**（owner「縦に長くならないように」）。
    /// 地図も札の列と同じ高さ（`cardColumnHeight`）に収め、段ぜんたいは `bodyHeight` の枠で固定
    func testMapFitsInsideTheSameHeight() throws {
        let g = try geometry()
        XCTAssertEqual(SearchSpotIndexSection.bodyHeight, 212)
        let width = SearchSpotIndexSection.mapWidth(for: g)
        XCTAssertGreaterThan(width, 120, "地図が細すぎる")
        XCTAssertLessThan(width, 170, "地図が札の場所を取りすぎる（右の札が狭い）")
        let text = try String(contentsOf: Self.resources.deletingLastPathComponent()
            .appendingPathComponent("Features/Search/SearchSpotIndexSection.swift"), encoding: .utf8)
        XCTAssertTrue(text.contains("`bodyHeight`）\n        .frame(height: Self.bodyHeight, alignment: .top)"),
                      "段（チップ＋札の列か地図）の高さを枠で固定していない")
        XCTAssertTrue(text.contains("mapRow(selected, geometry: geometry)\n                    .frame(height: Self.cardColumnHeight)"),
                      "地図の行の高さが札の列と同じでない")
    }

    /// 「写真｜地図」の札は `ProfileTabBar` と同じ下線の札（目印つき）
    func testModeTabs() {
        XCTAssertEqual(SpotIndexMode.allCases.map(\.tabTitle), [L("写真", "Photos"), L("地図", "Map")])
        XCTAssertEqual(SpotIndexMode.map.tabIdentifier, "search.spotIndex.mode.map")
    }
}
