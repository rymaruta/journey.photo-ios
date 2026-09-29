import XCTest
@testable import JourneyPhoto

/// 地図の「リスト」の札を都道府県ごとにまとめる（owner の提案・2026-09-28）
final class RegionListTests: XCTestCase {

    private func spot(_ slug: String, prefecture: String?, lat: Double, lng: Double,
                      stage: String = "published", country: String? = nil) throws -> OfficialSpot {
        var fields: [String] = []
        if let prefecture { fields.append("\"prefecture\":\"\(prefecture)\"") }
        if let country { fields.append("\"country\":\"\(country)\"") }
        let region = fields.isEmpty ? "" : ",\"region\":{\(fields.joined(separator: ","))}"
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(
            "{\"spotId\":\"sp_\(slug)\",\"slug\":\"\(slug)\",\"name\":\"\(slug)\",\"stage\":\"\(stage)\"\(region),\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}}".utf8))
    }

    private func photo(_ id: String, location: String? = nil, lat: Double? = nil, lng: Double? = nil,
                       category: String? = nil) throws -> Photo {
        var extra = ""
        if let location { extra += ",\"location\":\"\(location)\"" }
        if let lat, let lng { extra += ",\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}" }
        if let category { extra += ",\"category\":\"\(category)\"" }
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\"\(extra)}".utf8))
    }

    private let tokyo = Photo.Coords(lat: 35.68, lng: 139.76)

    private func spots() throws -> [OfficialSpot] {
        [
            try spot("zojoji", prefecture: "東京都", lat: 35.657, lng: 139.748),
            try spot("meiji", prefecture: "東京都", lat: 35.676, lng: 139.699),
            try spot("minatomirai", prefecture: "神奈川県", lat: 35.457, lng: 139.632),
            try spot("kinkakuji", prefecture: "京都府", lat: 35.039, lng: 135.729),
            try spot("sapporo", prefecture: "北海道", lat: 43.06, lng: 141.35),
            // 🔴 フランスの「県」。都道府県で終わるかでは見分けられない（本番の台帳にある）
            try spot("versailles", prefecture: "イヴリーヌ県", lat: 48.80, lng: 2.12),
        ]
    }

    // MARK: - 県の決め方

    /// 撮影地の文字は**正式名だけ**を見る。「東京都」の中の「京都」を京都府にしない
    func testPrefectureFromText() {
        XCTAssertEqual(RegionList.prefecture(inText: "東京都中央区"), "東京都")
        XCTAssertEqual(RegionList.prefecture(inText: "兵庫県神戸市"), "兵庫県")
        XCTAssertEqual(RegionList.prefecture(inText: "蔵王キツネ村, 白石市, 宮城県, 989-0733, 日本"), "宮城県")
        XCTAssertEqual(RegionList.prefecture(inText: "大阪府から京都府へ"), "大阪府", "都道府県の並びではなく、文字の先に出てくる方")
        XCTAssertNil(RegionList.prefecture(inText: "三条市, 日本"))
        XCTAssertNil(RegionList.prefecture(inText: "イヴリーヌ県"))
        XCTAssertNil(RegionList.prefecture(inText: nil))
    }

    func testJapanBox() {
        XCTAssertTrue(RegionList.isInJapan(tokyo))
        XCTAssertTrue(RegionList.isInJapan(.init(lat: 26.21, lng: 127.68)), "那覇")
        XCTAssertTrue(RegionList.isInJapan(.init(lat: 43.06, lng: 141.35)), "札幌")
        XCTAssertTrue(RegionList.isInJapan(.init(lat: 27.09, lng: 142.19)), "父島（東京都）")
        XCTAssertTrue(RegionList.isInJapan(.init(lat: 34.2, lng: 129.29)), "対馬（長崎県）")
        XCTAssertFalse(RegionList.isInJapan(.init(lat: 25.03, lng: 121.56)), "台北")
        XCTAssertFalse(RegionList.isInJapan(.init(lat: 60.17, lng: 24.94)), "ヘルシンキ")
    }

    /// スポットは台帳の県。47都道府県以外は「海外」
    func testSpotsGoToTheirPrefectureOrAbroad() throws {
        let sections = RegionList.sections(photos: [], spots: try spots(), from: nil)
        let byKey = Dictionary(uniqueKeysWithValues: sections.map { ($0.key, $0.spots.map(\.spot.slug)) })
        XCTAssertEqual(byKey[.prefecture("東京都")], ["meiji", "zojoji"], "起点が無ければ名前の順")
        XCTAssertEqual(byKey[.abroad], ["versailles"])
        XCTAssertNil(byKey[.prefecture("イヴリーヌ県")])
    }

    /// 写真: 文字 → 座標（日本なら一番近いスポットの県・外なら海外）→ 場所が分からない
    func testPhotosAreAssigned() throws {
        let photos = [
            try photo("text", location: "東京都中央区"),
            try photo("coords", location: "中央区, 日本", lat: 35.68, lng: 139.77),
            try photo("yokohama", lat: 35.45, lng: 139.63),
            try photo("helsinki", location: "Helsinki", lat: 60.17, lng: 24.94),
            try photo("none", location: "三条市, 日本"),
            try photo("bare"),
        ]
        let sections = RegionList.sections(photos: photos, spots: try spots(), from: nil)
        let byKey = Dictionary(uniqueKeysWithValues: sections.map { ($0.key, $0.photos.map(\.id)) })
        XCTAssertEqual(byKey[.prefecture("東京都")], ["text", "coords"])
        XCTAssertEqual(byKey[.prefecture("神奈川県")], ["yokohama"])
        XCTAssertEqual(byKey[.abroad], ["helsinki"])
        XCTAssertEqual(byKey[.unknown], ["none", "bare"])
    }

    /// 🔴 箱は粗い（ウラジオストク・釜山も入る）。**近くに撮影スポットが無ければ県を当てない**。
    /// 撮影地の文字が日本を指していなければ「海外」、座標しか無ければ「場所が分からない」。
    /// 父島のように箱の中でスポットが遠い日本の場所も「場所が分からない」（海外にしない）
    func testFarFromSpotsIsNotGuessed() throws {
        let photos = [
            try photo("vladivostok", location: "Vladivostok", lat: 43.12, lng: 131.89),
            try photo("busan", lat: 35.18, lng: 129.07),
            try photo("chichijima", location: "父島, 日本", lat: 27.09, lng: 142.19),
        ]
        let sections = RegionList.sections(photos: photos, spots: try spots(), from: nil)
        XCTAssertEqual(sections.first { $0.key == .abroad }?.photos.map(\.id), ["vladivostok"])
        XCTAssertEqual(sections.first { $0.key == .unknown }?.photos.map(\.id), ["busan", "chichijima"])
        XCTAssertTrue(sections.filter { if case .prefecture = $0.key { return true } else { return false } }
                        .allSatisfy { $0.photos.isEmpty }, "北海道などに入れていない")
        // 起点も同じ: スポットの遠い所では「いまいる県」を作らない（那覇 → 何百km先の県にしない）
        let naha = RegionList.sections(photos: [], spots: try spots(), from: .init(lat: 26.21, lng: 127.68))
        XCTAssertFalse(naha.contains(where: \.isCurrent))
    }

    /// 🔴 近くにスポットが無いだけで、日本の写真を「海外」にしない。
    /// 台帳が空（404・失敗）の回は、ローマ字の地名でも箱の中は海外にしない
    func testJapanesePlaceFarFromSpotsIsNotAbroad() throws {
        let photos = [
            try photo("yamanaka", location: "山中湖", lat: 35.42, lng: 138.87),
            try photo("vladivostok", location: "Vladivostok", lat: 43.12, lng: 131.89),
        ]
        let noSpots = RegionList.sections(photos: photos, spots: [], from: nil)
        XCTAssertEqual(noSpots.map(\.key), [.unknown])
        let farSpots = RegionList.sections(photos: photos, spots: [try spot("sapporo", prefecture: "北海道", lat: 43.06, lng: 141.35)], from: nil)
        XCTAssertEqual(farSpots.first { $0.key == .unknown }?.photos.map(\.id), ["yamanaka"])
        XCTAssertEqual(farSpots.first { $0.key == .abroad }?.photos.map(\.id), ["vladivostok"])
    }

    func testNamesAPlaceOutsideJapan() {
        XCTAssertTrue(RegionList.namesAPlaceOutsideJapan("Vladivostok"))
        XCTAssertTrue(RegionList.namesAPlaceOutsideJapan("Busan, Korea"))
        XCTAssertFalse(RegionList.namesAPlaceOutsideJapan("山中湖"), "かな・漢字の地名は日本とみなす")
        XCTAssertFalse(RegionList.namesAPlaceOutsideJapan("たかや神社"))
        XCTAssertFalse(RegionList.namesAPlaceOutsideJapan("父島, 日本"))
        XCTAssertFalse(RegionList.namesAPlaceOutsideJapan("Ogasawara, Japan"))
        XCTAssertFalse(RegionList.namesAPlaceOutsideJapan("東京都"))
        XCTAssertFalse(RegionList.namesAPlaceOutsideJapan(" "))
        XCTAssertFalse(RegionList.namesAPlaceOutsideJapan(nil))
    }

    /// 「場所が分からない」に撮影スポットが入った回は、見出しで「写真」と言わない
    func testUnknownTitleWithSpots() throws {
        // 台帳の県名が47都道府県に無く、座標は日本の範囲で、近くに手がかりの無いスポット
        let odd = try spot("odd", prefecture: "不明", lat: 27.09, lng: 142.19)
        let withSpot = RegionList.sections(photos: [], spots: [odd], from: nil)
        XCTAssertEqual(withSpot.map(\.key), [.unknown])
        XCTAssertEqual(withSpot[0].title, L("場所が分からないもの", "Without a place"))
        let photoOnly = RegionList.sections(photos: [try photo("p")], spots: [], from: nil)
        XCTAssertEqual(photoOnly[0].title, L("場所が分からない写真", "Photos without a place"))
    }

    // MARK: - 並び

    /// いまいる県が先頭。ほかは近い順。海外・場所が分からないは最後
    func testCurrentPrefectureFirstThenNearest() throws {
        let sections = RegionList.sections(photos: [try photo("x")], spots: try spots(), from: tokyo)
        XCTAssertEqual(sections.map(\.key), [
            .prefecture("東京都"), .prefecture("神奈川県"), .prefecture("京都府"), .prefecture("北海道"),
            .abroad, .unknown,
        ])
        XCTAssertEqual(sections.filter(\.isCurrent).map(\.key), [.prefecture("東京都")])
        XCTAssertEqual(sections[0].spots.map(\.spot.slug), ["zojoji", "meiji"], "県の中は近い順")
    }

    /// 「いまいる県」は距離の順より先。神奈川県と書かれた写真が起点のすぐ近くにあっても、
    /// 起点に一番近いスポットが東京都なら東京都が先頭
    func testCurrentBeatsDistance() throws {
        let near = try photo("near", location: "神奈川県", lat: 35.6801, lng: 139.7601)
        let sections = RegionList.sections(photos: [near], spots: try spots(), from: tokyo)
        XCTAssertEqual(sections.prefix(2).map(\.key), [.prefecture("東京都"), .prefecture("神奈川県")])
    }

    /// 起点が無ければ北から（47都道府県の並び）。いまいる県は無い
    func testNoCenterIsNorthToSouth() throws {
        let sections = RegionList.sections(photos: [], spots: try spots(), from: nil)
        XCTAssertEqual(sections.map(\.key), [
            .prefecture("北海道"), .prefecture("東京都"), .prefecture("神奈川県"), .prefecture("京都府"), .abroad,
        ])
        XCTAssertFalse(sections.contains(where: \.isCurrent))
    }

    /// 海外にいるときは「いまいる県」を作らない
    func testNoCurrentWhenAbroad() throws {
        let sections = RegionList.sections(photos: [], spots: try spots(), from: .init(lat: 48.85, lng: 2.35))
        XCTAssertFalse(sections.contains(where: \.isCurrent))
    }

    /// 下書きは出さない（「スポット」の札と同じ行）
    func testDraftsAreLeftOut() throws {
        let sections = RegionList.sections(
            photos: [], spots: [try spot("draft", prefecture: "東京都", lat: 35.6, lng: 139.7, stage: "review")], from: tokyo)
        XCTAssertTrue(sections.isEmpty)
    }

    // MARK: - 絞り込み

    /// 上の欄は写真の撮影地とスポットの名前・地域に当てる。カテゴリは写真だけに効く。
    /// **座標の無い写真も残す**（地図と違う）
    func testFilter() throws {
        let photos = [
            try photo("a", location: "東京都中央区", category: "nature"),
            try photo("b", location: "京都府", category: "city"),
            try photo("c", location: "北海道", category: "city"),
        ]
        let byQuery = RegionList.filter(photos: photos, spots: try spots(), query: "京都", category: nil)
        XCTAssertEqual(byQuery.photos.map(\.id), ["a", "b"], "東京都も『京都』を含む（地図の検索と同じゆるい当て方）")
        XCTAssertTrue(byQuery.spots.map(\.slug).contains("kinkakuji"))
        let byCategory = RegionList.filter(photos: photos, spots: try spots(), query: "", category: "city")
        XCTAssertEqual(byCategory.photos.map(\.id), ["b", "c"])
        XCTAssertEqual(byCategory.spots.count, 6, "カテゴリは撮影スポットに効かせない")
    }

    /// 🔴 **語で絞っても、写真の県は変わらない**（県を当てる手がかりは絞る前の全スポット）。
    /// 絞った後で作ると、語がスポット名に当たらないだけで写真が「場所が分からない」に落ちた
    func testSearchKeepsPrefecture() throws {
        let unkai = try photo("unkai", location: "雲海", lat: 35.66, lng: 139.75)
        let sections = RegionList.sections(photos: [unkai], spots: try spots(), query: "雲海", from: tokyo)
        XCTAssertEqual(sections.map(\.key), [.prefecture("東京都")])
        XCTAssertTrue(sections[0].isCurrent, "語を打っても起点の県はそのまま")
        XCTAssertTrue(sections[0].spots.isEmpty, "スポットは語で絞られる")
    }

    /// 「写真 N枚」は絞る前の全部から数える（「スポット」の札・スポットの画面と同じ数）
    func testPhotoCountIgnoresFilter() throws {
        let linked = try JSONDecoder.api.decode(Photo.self, from: Data(
            #"{"id":"l","src":"/uploads/l.jpg","spotId":"sp_zojoji","category":"nature"}"#.utf8))
        let sections = RegionList.sections(photos: [linked], spots: try spots(), category: "city", from: tokyo)
        let zojoji = sections.flatMap(\.spots).first { $0.spot.slug == "zojoji" }
        XCTAssertEqual(zojoji?.photoCount, 1)
    }

    func testCountLabel() throws {
        let s = RegionList.sections(photos: [try photo("p", location: "東京都")], spots: try spots(), from: tokyo)
        XCTAssertEqual(RegionList.countLabel(s[0]), L("2件 · 写真 1枚", "2 spots · 1 photo"))
        XCTAssertEqual(RegionList.countLabel(s[1]), L("1件", "1 spot"))
    }

    // MARK: - 海外は国ごと（owner の要求変更・2026-09-29）

    private func abroadSpots() throws -> [OfficialSpot] {
        [
            try spot("versailles", prefecture: "イヴリーヌ県", lat: 48.80, lng: 2.12, country: "フランス"),
            try spot("mont", prefecture: "ノルマンディー", lat: 48.636, lng: -1.511, country: "フランス"),
            try spot("sagrada", prefecture: "カタルーニャ州", lat: 41.40, lng: 2.17, country: "スペイン"),
            // 国の載っていない古い索引の行
            try spot("helsinki", prefecture: nil, lat: 60.17, lng: 24.94),
            try spot("zojoji", prefecture: "東京都", lat: 35.657, lng: 139.748),
        ]
    }

    /// 撮影スポットは台帳の国で段を作る。国の無い海外の行は「海外（その他）」
    func testAbroadSpotsAreGroupedByCountry() throws {
        let sections = RegionList.sections(photos: [], spots: try abroadSpots(), from: nil)
        let byKey = Dictionary(uniqueKeysWithValues: sections.map { ($0.key, $0.spots.map(\.spot.slug).sorted()) })
        XCTAssertEqual(byKey[.country("フランス")], ["mont", "versailles"])
        XCTAssertEqual(byKey[.country("スペイン")], ["sagrada"])
        XCTAssertEqual(byKey[.abroad], ["helsinki"])
        XCTAssertEqual(sections.first { $0.key == .country("フランス") }?.title, "フランス")
    }

    /// 並び: 県 → 国（起点から近い順）→ 海外（その他）→ 場所が分からない
    func testCountriesComeAfterPrefecturesNearestFirst() throws {
        let paris = Photo.Coords(lat: 48.85, lng: 2.35)
        let barcelona = Photo.Coords(lat: 41.39, lng: 2.16)
        let fromParis = RegionList.sections(photos: [], spots: try abroadSpots(), from: paris).map(\.key)
        XCTAssertEqual(fromParis, [.prefecture("東京都"), .country("フランス"), .country("スペイン"), .abroad])
        let fromBarcelona = RegionList.sections(photos: [], spots: try abroadSpots(), from: barcelona).map(\.key)
        XCTAssertEqual(fromBarcelona, [.prefecture("東京都"), .country("スペイン"), .country("フランス"), .abroad])
        // 起点が無ければ国名の順
        let noCenter = RegionList.sections(photos: [], spots: try abroadSpots(), from: nil).map(\.key)
        XCTAssertEqual(noCenter.filter { if case .country = $0 { return true }; return false },
                       [.country("スペイン"), .country("フランス")].sorted { $0.id < $1.id })
    }

    /// 海外の写真は、近く（150km 以内）の国の分かる撮影スポットの国へ。遠ければ「海外（その他）」
    func testAbroadPhotosTakeTheNearestSpotsCountry() throws {
        let nearParis = try photo("paris", lat: 48.86, lng: 2.35)
        let farAway = try photo("reykjavik", lat: 64.15, lng: -21.94)
        let sections = RegionList.sections(photos: [nearParis, farAway], spots: try abroadSpots(), from: nil)
        XCTAssertEqual(sections.first { $0.key == .country("フランス") }?.photos.map(\.id), ["paris"])
        XCTAssertEqual(sections.first { $0.key == .abroad }?.photos.map(\.id), ["reykjavik"])
    }

    /// 国は索引の `region.country` から読む。無い古い索引も読める
    func testRegionCountryDecodes() throws {
        let fr = try spot("v", prefecture: "イヴリーヌ県", lat: 48.8, lng: 2.1, country: "フランス")
        XCTAssertEqual(fr.region?.country, "フランス")
        XCTAssertNil(try spot("t", prefecture: "東京都", lat: 35.6, lng: 139.7).region?.country)
    }

    /// 🔴 国の載った行は、座標が日本の箱に入っても（釜山）近くの県に入れない
    func testCountryWinsOverTheJapanBox() throws {
        let busan = try spot("busan", prefecture: "釜山広域市", lat: 35.10, lng: 129.04, country: "韓国")
        let tsushima = try spot("tsushima", prefecture: "長崎県", lat: 34.20, lng: 129.29)
        let sections = RegionList.sections(photos: [], spots: [busan, tsushima], from: nil)
        XCTAssertEqual(sections.first { $0.key == .country("韓国") }?.spots.map(\.spot.slug), ["busan"])
        XCTAssertEqual(sections.first { $0.key == .prefecture("長崎県") }?.spots.map(\.spot.slug), ["tsushima"])
    }

    /// 海外にいるときは、近くの国の段が「いまいる段」（開いて出る）
    func testCurrentSectionAbroadIsTheNearbyCountry() throws {
        let paris = Photo.Coords(lat: 48.85, lng: 2.35)
        let sections = RegionList.sections(photos: [], spots: try abroadSpots(), from: paris)
        XCTAssertEqual(sections.filter(\.isCurrent).map(\.key), [.country("フランス")])
        XCTAssertEqual(RegionList.sections(photos: [], spots: try abroadSpots(), from: tokyo)
            .filter(\.isCurrent).map(\.key), [.prefecture("東京都")])
    }

    /// 釜山の写真・釜山を起点にしたときも、対馬の県ではなく近い方（韓国）へ
    func testBusanPhotoAndCenterGoToTheNearerCountry() throws {
        let busan = try spot("busan", prefecture: "釜山広域市", lat: 35.10, lng: 129.04, country: "韓国")
        let tsushima = try spot("tsushima", prefecture: "長崎県", lat: 34.20, lng: 129.29)
        let photoInBusan = try photo("p_busan", lat: 35.11, lng: 129.03)
        let center = Photo.Coords(lat: 35.10, lng: 129.04)
        let sections = RegionList.sections(photos: [photoInBusan], spots: [busan, tsushima], from: center)
        XCTAssertEqual(sections.first { $0.key == .country("韓国") }?.photos.map(\.id), ["p_busan"])
        XCTAssertEqual(sections.filter(\.isCurrent).map(\.key), [.country("韓国")])
        // 対馬の写真は長崎県のまま
        let photoInTsushima = try photo("p_tsushima", lat: 34.21, lng: 129.29)
        XCTAssertEqual(RegionList.sections(photos: [photoInTsushima], spots: [busan, tsushima], from: nil)
            .first { $0.key == .prefecture("長崎県") }?.photos.map(\.id), ["p_tsushima"])
    }

    /// 海外の起点でも、150km 以内に国の分かるスポットが無ければ「いまいる段」は無い
    func testNoCurrentSectionFarFromEverySpot() throws {
        let reykjavik = Photo.Coords(lat: 64.15, lng: -21.94)
        XCTAssertTrue(RegionList.sections(photos: [], spots: try abroadSpots(), from: reykjavik)
            .filter(\.isCurrent).isEmpty)
    }
}
