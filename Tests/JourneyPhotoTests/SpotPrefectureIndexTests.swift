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
        XCTAssertEqual(jumps.map(\.targetTitle), ["北海道", "東京都", "京都府", "フランス"])
    }

    /// 表紙の詳細は、表紙の無い札の「まだ索引だけで、索引が写真ありと言う行」だけを読む
    /// （写真の無い行の詳細を読んでも表紙は増えない・確かめ役の指摘 2026-11-11）
    func testCoverNeedsOnlyIndexOnlyRowsWithoutCover() throws {
        var bare = try spot("bare", prefecture: "奈良県", lat: 34.68, lng: 135.83)
        bare.isIndexOnly = true
        var pictured = try spot("pictured", prefecture: "奈良県", lat: 34.69, lng: 135.84)
        pictured.isIndexOnly = true
        pictured.hasImage = LenientFlag(true)
        let groups = SpotPrefectureIndex.groups(spots: try spots() + [bare, pictured])
        let kinki = try XCTUnwrap(groups.first { $0.region.name == "近畿" })
        XCTAssertEqual(SpotPrefectureIndex.coverNeeds(kinki).map(\.slug), ["pictured"],
                       "索引が「写真なし」と言う行（bare）は読まない")
        // 写真ありの行が無い県は何も読まない
        let onlyBare = SpotPrefectureIndex.groups(spots: [bare])
        XCTAssertTrue(SpotPrefectureIndex.coverNeeds(onlyBare.first).isEmpty)
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
        // 出典の帯（当たり 44・字は 12pt の1行）を札の下に含める。写真の無い札も同じだけ空ける
        XCTAssertEqual(SearchSpotIndexSection.creditHeight, CGFloat(CreditLink.tapHeight))
        XCTAssertEqual(SearchSpotIndexSection.creditHeight, 44)
        XCTAssertEqual(SearchSpotIndexSection.cardColumnHeight, 116 + 44)
        XCTAssertEqual(SearchSpotIndexSection.bodyHeight, 44 + 8 + 116 + 44)
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    /// 🔴 **札の写真には出典を必ず付ける**（CC BY・CC BY-SA の条件）。写真の無い札も同じ高さを空ける。
    /// 出典は札のリンクの外（押す先を重ねない）
    func testCardsCarryCreditOutsideTheLink() throws {
        let text = try source("Features/Search/SearchSpotIndexSection.swift")
        let strip = try XCTUnwrap(text.range(of: "private func strip(")).upperBound
        let rest = text[strip...]
        let card = try XCTUnwrap(rest.range(of: "prefectureCard(card)"))
        let credit = try XCTUnwrap(rest.range(of: "credit(card)"))
        let between = rest[card.upperBound..<credit.lowerBound]
        XCTAssertTrue(between.contains(".accessibilityIdentifier(\"search.spotIndex.prefecture\")"),
                      "出典は札のリンクの外・後ろ")
        let body = try XCTUnwrap(text.range(of: "private func credit(")).upperBound
        let creditBody = String(text[body...])
        for part in ["CreditLinksMenu(links: cover.creditLinks, accessibilityLabel: cover.credit",
                     "SpotPrefectureIndex.creditText(cover)", ".font(JPFont.caption)", ".lineLimit(1)",
                     ".truncationMode(.tail)", "Color.clear", ".frame(width: Self.cardWidth, height: Self.creditHeight"] {
            XCTAssertTrue(creditBody.contains(part), "\(part) が無い")
        }
        XCTAssertTrue(text.contains(".frame(height: Self.cardColumnHeight)"), "札の列の高さに出典の行を含めていない")
    }

    /// 出典の字: 開ける先があれば作者だけ（ライセンスは押した先のメニューに名前つきで出る）、無ければライセンスも
    func testCreditTextShowsAuthorAndLeavesLicenseToMenu() throws {
        let linked = try XCTUnwrap(try JSONDecoder.api.decode(LenientSpotImage.self, from: Data(
            "{\"url\":\"https://journey-photo.com/a.jpg\",\"author\":\"とても長い名前の撮影者\",\"license\":\"CC BY-SA 4.0\",\"pageUrl\":\"https://commons.wikimedia.org/wiki/File:A.jpg\",\"licenseUrl\":\"https://creativecommons.org/licenses/by-sa/4.0/\"}".utf8)).value)
        XCTAssertEqual(SpotPrefectureIndex.creditText(linked), linked.creditAuthor)
        XCTAssertTrue(linked.creditLinks.contains { $0.label.contains("CC BY-SA 4.0") }, "ライセンスがメニューに無い")
        let bare = try XCTUnwrap(try JSONDecoder.api.decode(LenientSpotImage.self, from: Data(
            "{\"url\":\"https://journey-photo.com/b.jpg\",\"author\":\"B\",\"license\":\"Public domain\"}".utf8)).value)
        XCTAssertTrue(bare.creditLinks.isEmpty)
        XCTAssertEqual(SpotPrefectureIndex.creditText(bare), bare.credit)
    }

    /// 🔴 写真が一覧を開いた後に届いたら数え直す（以前は全行 0 枚のまま）。同じ材料なら数えない
    func testPhotoCounterRecountsWhenPhotosArrive() throws {
        var counter = SpotPrefectureIndex.PhotoCounter()
        counter.refresh([], links: .empty)
        XCTAssertTrue(counter.counts.isEmpty)
        let photo = try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"p\",\"src\":\"/uploads/p.jpg\",\"spotId\":\"sp_meiji\"}".utf8))
        counter.refresh([photo], links: .empty)
        XCTAssertEqual(counter.counts, ["sp_meiji": 1])
        XCTAssertEqual(counter.builds, 2)
        counter.refresh([photo], links: .empty)
        XCTAssertEqual(counter.builds, 2, "同じ写真・結びで数え直した")
        // 一覧の画面は写真の鍵の変化で数え直す
        let text = try source("Features/Spots/OfficialSpotIndexView.swift")
        XCTAssertTrue(text.contains(".onChange(of: SpotPrefectureIndex.PhotoCounter.key(photos, links: links))"),
                      "写真が届いても数え直していない")
    }

    /// 読み上げに撮影者も入れる。区切りは英語では「, 」（`L`）
    func testSpokenCardIncludesPhotographer() throws {
        let groups = SpotPrefectureIndex.groups(spots: try spots())
        let tokyo = try XCTUnwrap(groups.flatMap(\.cards).first { $0.prefecture == "東京都" })
        let comma = L("、", ", ")
        XCTAssertEqual(SpotPrefectureIndex.spokenCard(tokyo),
                       ["東京都", L("2件", "2 spots"), L("写真: A", "Photo: A")].joined(separator: comma))
        let kanagawa = try XCTUnwrap(groups.flatMap(\.cards).first { $0.prefecture == "神奈川県" })
        XCTAssertEqual(SpotPrefectureIndex.spokenCard(kanagawa), ["神奈川県", L("1件", "1 spot")].joined(separator: comma))
    }

    // MARK: - 読み込み（引き下げ・もう一度試す・最初の読み込みが同じ口）

    private struct Offline: Error {}

    /// 🔴 失敗のあと、引き下げ（`reloadAll` → `loadSpotIndex`）で取れたら `.ready` に戻る。
    /// 以前は引き下げが索引を別に読み、段が「読み込めませんでした」のまま残った（確かめ役の指摘 2026-11-11）
    func testFailureThenReloadBecomesReady() async throws {
        var load = SpotPrefectureIndex.Load.loading
        var spots: [OfficialSpot] = []
        func apply(_ r: (spots: [OfficialSpot]?, load: SpotPrefectureIndex.Load)?) {
            guard let r else { return }
            if let s = r.spots { spots = s }
            load = r.load
        }
        apply(await SpotPrefectureIndex.loaded { throw Offline() })
        XCTAssertEqual(load, .failed)
        XCTAssertTrue(spots.isEmpty)
        let fetched = try self.spots()
        apply(await SpotPrefectureIndex.loaded { fetched })
        XCTAssertEqual(load, .ready)
        XCTAssertEqual(spots.count, fetched.count)
        // 取り消された回は段階を変えない（「読み込めませんでした」と言わない）
        let cancelled = await SpotPrefectureIndex.loaded { throw CancellationError() }
        XCTAssertNil(cancelled)
    }

    /// 探すの3か所（最初の `.task`・「もう一度試す」・引き下げ）が同じ口 `loadSpotIndex` を通る。
    /// 索引を読むのはその口だけ（別に読むと段階が付いてこない）
    func testSearchLoadsIndexThroughOnePlace() throws {
        let text = try source("Features/Search/SearchView.swift")
        XCTAssertEqual(text.components(separatedBy: "fetchIndex(").count - 1, 1, "索引を読む所が1か所でない")
        XCTAssertEqual(text.components(separatedBy: "await loadSpotIndex(force:").count - 1, 3)
        let reload = try XCTUnwrap(text.range(of: "private func reloadAll() async {")).upperBound
        let reloadBody = text[reload...].prefix(1600)
        XCTAssertTrue(reloadBody.contains("await loadSpotIndex(force: false)"), "引き下げが同じ口を通っていない")
    }

    /// 表紙の詳細を読む鍵は画面に出ている間だけ（出ていない間に捨てた回は、戻ったら鍵が変わって読み直す）
    func testCoverTaskKeyChangesWhenBackOnScreen() throws {
        var pictured = try spot("pictured", prefecture: "奈良県", lat: 34.69, lng: 135.84)
        pictured.isIndexOnly = true
        XCTAssertEqual(SpotPrefectureIndex.coverTaskKey([pictured], onScreen: false), "")
        XCTAssertNotEqual(SpotPrefectureIndex.coverTaskKey([pictured], onScreen: true), "")
        XCTAssertEqual(SpotPrefectureIndex.coverTaskKey([], onScreen: true), "")
    }

    /// 一覧の段は写真を県に振り分けずに作り、行の枚数は数えておいた表から当てる
    func testListSectionsUseCountedPhotos() throws {
        let sections = SpotPrefectureIndex.listSections(spots: try spots(), query: "", aliases: [:],
                                                        counts: ["sp_kinkakuji": 3], from: nil)
        XCTAssertEqual(sections.map(\.title), ["北海道", "東京都", "神奈川県", "京都府", "フランス"])
        XCTAssertTrue(sections.allSatisfy { $0.photos.isEmpty })
        let kyoto = try XCTUnwrap(sections.first { $0.key == .prefecture("京都府") })
        XCTAssertEqual(kyoto.spots.first { $0.spot.slug == "kinkakuji" }?.photoCount, 3)
        XCTAssertEqual(kyoto.spots.first { $0.spot.slug == "ginkakuji" }?.photoCount, 0)
        // 数え方は地図の行と同じ（`OfficialSpotList.rows` と `photoCounts` が一致する）
        let photo = try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"p\",\"src\":\"/uploads/p.jpg\",\"spotId\":\"sp_meiji\"}".utf8))
        XCTAssertEqual(OfficialSpotList.photoCounts([photo]), ["sp_meiji": 1])
        XCTAssertEqual(OfficialSpotList.rows(try spots(), photos: [photo], from: nil)
            .first { $0.spot.slug == "meiji" }?.photoCount, 1)
    }

    /// 一覧の画面は段を body のたびに作らず、入力が変わったときだけ作る（確かめ役の指摘 2026-11-11）
    func testIndexViewBuildsSectionsOnlyOnInputChange() throws {
        let text = try source("Features/Spots/OfficialSpotIndexView.swift")
        let body = try XCTUnwrap(text.range(of: "var body: some View {")).upperBound
        let bodyText = text[body...]
        let end = try XCTUnwrap(bodyText.range(of: ".webScreen()")).lowerBound
        XCTAssertFalse(bodyText[..<end].contains("RegionList.sections("), "body で毎回束ねている")
        XCTAssertFalse(bodyText[..<end].contains("listSections("), "body で毎回束ねている")
        XCTAssertTrue(text.contains(".onChange(of: inputs) { _, _ in rebuild() }"))
        XCTAssertFalse(text.contains("photos: photos, spots:"), "写真を県に振り分けている")
    }

    /// 段は探すの先頭（2026-11-12・案 第10章。前は「人気の撮影地」の次）
    func testDiscoveryPlacesSpotIndexFirst() {
        XCTAssertEqual(SearchDiscovery.sections(present: [.gear, .officialSpots, .spots]),
                       [.officialSpots, .spots, .gear])
    }

    /// 段の件数の字（英語も）
    func testCountLabel() {
        XCTAssertEqual(SpotPrefectureIndex.countLabel(3), L("3件", "3 spots"))
        XCTAssertEqual(SpotPrefectureIndex.countLabel(1), L("1件", "1 spot"))
    }
}
