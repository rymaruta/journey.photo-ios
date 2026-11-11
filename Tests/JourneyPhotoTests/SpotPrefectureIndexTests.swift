import XCTest
@testable import JourneyPhoto

/// 探すの「撮影スポット」の段と一覧（札 #524・`SpotPrefectureIndex`・`OfficialSpotIndexView.shown`）
final class SpotPrefectureIndexTests: XCTestCase {

    private func spot(_ slug: String, prefecture: String?, lat: Double, lng: Double,
                      stage: String = "published", country: String? = nil, image: Bool = false,
                      name: String? = nil) throws -> OfficialSpot {
        var fields: [String] = []
        if let prefecture { fields.append("\"prefecture\":\"\(prefecture)\"") }
        if let country { fields.append("\"country\":\"\(country)\"") }
        let region = fields.isEmpty ? "" : ",\"region\":{\(fields.joined(separator: ","))}"
        let picture = image
            ? ",\"image\":{\"url\":\"https://journey-photo.com/images/spots/\(slug).jpg\",\"author\":\"A\",\"license\":\"CC BY 4.0\"}"
            : ""
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(
            "{\"spotId\":\"sp_\(slug)\",\"slug\":\"\(slug)\",\"name\":\"\(name ?? slug)\",\"stage\":\"\(stage)\"\(region)\(picture),\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}}".utf8))
    }

    private func spots() throws -> [OfficialSpot] {
        [
            try spot("zojoji", prefecture: "東京都", lat: 35.657, lng: 139.748, image: true),
            try spot("meiji", prefecture: "東京都", lat: 35.676, lng: 139.699),
            try spot("minatomirai", prefecture: "神奈川県", lat: 35.457, lng: 139.632),
            try spot("kinkakuji", prefecture: "京都府", lat: 35.039, lng: 135.729, image: true),
            try spot("ginkakuji", prefecture: "京都府", lat: 35.027, lng: 135.798),
            try spot("kiyomizu", prefecture: "京都府", lat: 34.995, lng: 135.785),
            try spot("sapporo", prefecture: "北海道", lat: 43.06, lng: 141.35),
            // 下書きは数えない（地図の一覧と同じ）
            try spot("draft", prefecture: "沖縄県", lat: 26.2, lng: 127.7, stage: "draft"),
            // 🔴 フランスの「県」。県の札にしない
            try spot("versailles", prefecture: "イヴリーヌ県", lat: 48.80, lng: 2.12, country: "フランス"),
        ]
    }

    // MARK: - 地方ごとの束ね

    /// 地方は北から、県は北から（JIS の順）。**0件の県・地方は出さない**。下書き・海外は県の札にしない
    func testGroupsByRegionNorthToSouthAndSkipsEmpty() throws {
        let groups = SpotPrefectureIndex.groups(spots: try spots())
        XCTAssertEqual(groups.map(\.region.name), ["北海道", "関東", "近畿"])
        XCTAssertEqual(groups[1].cards.map(\.prefecture), ["東京都", "神奈川県"])
        XCTAssertEqual(groups[1].cards.map(\.count), [2, 1])
        XCTAssertEqual(groups[2].cards.map(\.prefecture), ["京都府"])
        XCTAssertEqual(groups[2].count, 3)
        let all = groups.flatMap(\.cards).map(\.prefecture)
        XCTAssertFalse(all.contains("沖縄県"), "下書きしか無い県は出さない")
        XCTAssertFalse(all.contains("イヴリーヌ県"))
        XCTAssertTrue(groups.allSatisfy { !$0.cards.isEmpty })
    }

    /// 表紙は写真を持つ撮影スポットから。持たない県は nil（画面は真鍮のピン）
    func testCoverComesFromSpotWithPhoto() throws {
        let groups = SpotPrefectureIndex.groups(spots: try spots())
        let tokyo = try XCTUnwrap(groups.flatMap(\.cards).first { $0.prefecture == "東京都" })
        XCTAssertEqual(tokyo.cover?.url.lastPathComponent, "zojoji.jpg")
        let kanagawa = try XCTUnwrap(groups.flatMap(\.cards).first { $0.prefecture == "神奈川県" })
        XCTAssertNil(kanagawa.cover)
    }

    /// 表紙は写真の多い撮影スポットを先に（同じなら名前の順）
    func testCoverPrefersSpotWithMorePhotos() throws {
        let a = try spot("a", prefecture: "京都府", lat: 35, lng: 135.7, image: true)
        let b = try spot("b", prefecture: "京都府", lat: 35, lng: 135.8, image: true)
        let rows = [OfficialSpotList.Row(spot: a, km: nil, photoCount: 1),
                    OfficialSpotList.Row(spot: b, km: nil, photoCount: 4)]
        XCTAssertEqual(SpotPrefectureIndex.cover(rows)?.url.lastPathComponent, "b.jpg")
        let tie = [OfficialSpotList.Row(spot: b, km: nil, photoCount: 0),
                   OfficialSpotList.Row(spot: a, km: nil, photoCount: 0)]
        XCTAssertEqual(SpotPrefectureIndex.cover(tie)?.url.lastPathComponent, "a.jpg")
    }

    /// 最初に選ぶ地方は撮影スポットのいちばん多い地方。前に選んだ地方が残っていればそれ。消えていれば多い方へ
    func testSelectedRegionDefaultsToLargest() throws {
        // 関東 3件・近畿 4件（京都 3・奈良 1）
        let groups = SpotPrefectureIndex.groups(spots: try spots() + [try spot("todaiji", prefecture: "奈良県", lat: 34.689, lng: 135.84)])
        XCTAssertEqual(SpotPrefectureIndex.selected(nil, in: groups)?.region.name, "近畿")
        XCTAssertEqual(SpotPrefectureIndex.selected("北海道", in: groups)?.region.name, "北海道")
        XCTAssertEqual(SpotPrefectureIndex.selected("九州・沖縄", in: groups)?.region.name, "近畿")
        XCTAssertNil(SpotPrefectureIndex.selected(nil, in: []))
    }

    /// 同じ件数なら北の地方
    func testSelectedRegionTieGoesNorth() throws {
        let groups = SpotPrefectureIndex.groups(spots: [
            try spot("s", prefecture: "北海道", lat: 43.06, lng: 141.35),
            try spot("k", prefecture: "京都府", lat: 35.0, lng: 135.7),
        ])
        XCTAssertEqual(SpotPrefectureIndex.selected(nil, in: groups)?.region.name, "北海道")
    }

    // MARK: - 一覧

    /// 全国の一覧は県を北から、国はその後。写真だけの段は出さない
    func testNationalSectionsOrder() throws {
        let photo = try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"p\",\"src\":\"/uploads/p.jpg\",\"location\":\"沖縄県那覇市\"}".utf8))
        let sections = RegionList.sections(photos: [photo], spots: try spots(),
                                           from: Photo.Coords(lat: 35.0, lng: 135.7))
        let national = SpotPrefectureIndex.nationalSections(sections)
        XCTAssertEqual(national.map(\.title), ["北海道", "東京都", "神奈川県", "京都府", "フランス"],
                       "起点（京都）があっても県の順は北から")
        XCTAssertFalse(national.contains { $0.key == .prefecture("沖縄県") }, "写真だけの段は出さない")
    }

    /// 県の一覧はその県だけ。行は起点から近い順（`OfficialSpotList.rows`）
    func testPrefectureScopeShowsOnlyThatPrefectureNearestFirst() throws {
        let sections = RegionList.sections(photos: [], spots: try spots(),
                                           from: Photo.Coords(lat: 34.99, lng: 135.78))
        let shown = OfficialSpotIndexView.shown(sections, scope: .prefecture("京都府"))
        XCTAssertEqual(shown.count, 1)
        XCTAssertEqual(shown[0].spots.map(\.spot.slug), ["kiyomizu", "ginkakuji", "kinkakuji"])
    }

    /// 一覧の探す欄は名前と別名で絞る（地図・探すと同じ当て方）
    func testFilterByNameAndAlias() throws {
        let byName = RegionList.sections(photos: [], spots: try spots(), query: "銀閣",
                                         aliases: ["ginkakuji": ["銀閣寺"]], from: nil)
        XCTAssertEqual(OfficialSpotIndexView.shown(byName, scope: .all).flatMap(\.spots).map(\.spot.slug), ["ginkakuji"])
        let none = RegionList.sections(photos: [], spots: try spots(), query: "存在しない", from: nil)
        XCTAssertTrue(OfficialSpotIndexView.shown(none, scope: .all).isEmpty)
        let scoped = RegionList.sections(photos: [], spots: try spots(), query: "meiji", from: nil)
        XCTAssertTrue(OfficialSpotIndexView.shown(scoped, scope: .prefecture("京都府")).isEmpty)
    }

    /// 跳ぶチップは段のある地方だけ（北から）と「海外」。行き先はその地方で最初の段
    func testJumpsPointAtFirstSectionOfRegion() throws {
        let national = SpotPrefectureIndex.nationalSections(
            RegionList.sections(photos: [], spots: try spots(), from: nil))
        let jumps = SpotPrefectureIndex.jumps(national)
        XCTAssertEqual(jumps.map(\.id), ["北海道", "関東", "近畿", "abroad"])
        XCTAssertEqual(jumps.map(\.target), ["pref:北海道", "pref:東京都", "pref:京都府", "country:フランス"])
        XCTAssertEqual(jumps.last?.title, L("海外", "Outside Japan"))
    }

    /// 表紙の詳細は、表紙の無い札の「まだ索引だけの行」だけを読む
    func testCoverNeedsOnlyIndexOnlyRowsWithoutCover() throws {
        var bare = try spot("bare", prefecture: "奈良県", lat: 34.68, lng: 135.83)
        bare.isIndexOnly = true
        let groups = SpotPrefectureIndex.groups(spots: try spots() + [bare])
        let kinki = try XCTUnwrap(groups.first { $0.region.name == "近畿" })
        XCTAssertEqual(SpotPrefectureIndex.coverNeeds(kinki).map(\.slug), ["bare"])
        XCTAssertTrue(SpotPrefectureIndex.coverNeeds(groups.first { $0.region.name == "関東" }).isEmpty,
                      "東京は表紙あり・神奈川は詳細つきの行だけ（読んでも写真は増えない）")
        XCTAssertTrue(SpotPrefectureIndex.coverNeeds(nil).isEmpty)
    }

    // MARK: - 段の高さ

    /// **段の高さは地方によらず決まっている**（2026-11-11 owner「縦長になる」）。
    /// チップ（34＋押せる余白 5×2）＋すき間 8＋札 116。札は「人気の撮影地」の札と同じ大きさ
    func testStripHeightIsFixed() {
        XCTAssertEqual(SearchSpotIndexSection.chipRowHeight, WebTheme.minTapTarget)
        XCTAssertEqual(SearchSpotIndexSection.cardHeight, 116)
        XCTAssertEqual(SearchSpotIndexSection.cardWidth, 156)
        XCTAssertEqual(SearchSpotIndexSection.bodyHeight, 44 + 8 + 116)
    }

    /// 段は「人気の撮影地」の次（板 Search の並び）
    func testDiscoveryPlacesSpotIndexAfterPopularPlaces() {
        XCTAssertEqual(SearchDiscovery.sections(present: [.gear, .officialSpots, .spots]),
                       [.spots, .officialSpots, .gear])
    }

    /// 段の件数の字（英語も）
    func testCountLabel() {
        XCTAssertEqual(SpotPrefectureIndex.countLabel(3), L("3件", "3 spots"))
        XCTAssertEqual(SpotPrefectureIndex.countLabel(1), L("1件", "1 spot"))
    }
}
