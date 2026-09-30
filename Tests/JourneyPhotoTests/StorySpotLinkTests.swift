import XCTest
@testable import JourneyPhoto

/// ストーリーの撮影地 → 撮影スポットのガイド（`StorySpotLink`・2026-09-30）。
/// **名前は実データの形**（括弧・空白入り）で書く——架空の「高屋神社」で書いた初版の試験は、
/// 本番の「高屋神社 本宮（天空の鳥居）」に対して動かないことを見逃していた
final class StorySpotLinkTests: XCTestCase {

    private func story(location: String?, lat: Double? = nil, lng: Double? = nil) -> Story {
        var fields = [#""id":"s1""#, #""src":"https://x.test/s1.jpg""#, #""userId":"u1""#]
        if let location { fields.append(#""location":"\#(location)""#) }
        if let lat, let lng { fields.append(#""coords":{"lat":\#(lat),"lng":\#(lng)}"#) }
        return try! JSONDecoder.api.decode(Story.self, from: Data(("{" + fields.joined(separator: ",") + "}").utf8))
    }

    private func spot(_ slug: String, name: String, nameEn: String? = nil, lat: Double, lng: Double,
                      prefecture: String? = nil, city: String? = nil, stage: String = "published") -> OfficialSpot {
        var fields = [#""spotId":"sp_\#(slug)""#, #""slug":"\#(slug)""#, #""name":"\#(name)""#, #""stage":"\#(stage)""#,
                      #""coords":{"lat":\#(lat),"lng":\#(lng)}"#]
        if let nameEn { fields.append(#""nameEn":"\#(nameEn)""#) }
        var region: [String] = []
        if let prefecture { region.append(#""prefecture":"\#(prefecture)""#) }
        if let city { region.append(#""city":"\#(city)""#) }
        if !region.isEmpty { fields.append(#""region":{"# + region.joined(separator: ",") + "}") }
        return try! JSONDecoder.api.decode(OfficialSpot.self, from: Data(("{" + fields.joined(separator: ",") + "}").utf8))
    }

    private lazy var takaya = spot("takaya-jinja", name: "高屋神社 本宮（天空の鳥居）", lat: 34.13, lng: 133.64,
                                   prefecture: "香川県", city: "観音寺市")

    /// 実データの名前（後ろが長い・空白入り）でも、撮影地の頭が名前の頭なら結ぶ
    func testLinksByNameHeadAndDistance() {
        let spots = [takaya]
        XCTAssertEqual(StorySpotLink.spot(for: story(location: "高屋神社", lat: 34.13, lng: 133.65), in: spots)?.slug,
                       "takaya-jinja")
        XCTAssertEqual(StorySpotLink.spot(for: story(location: "高屋神社, 観音寺市, 香川県, 日本", lat: 34.13, lng: 133.64),
                                          in: spots)?.slug, "takaya-jinja")
        XCTAssertEqual(StorySpotLink.spot(for: story(location: "高屋神社本宮", lat: 34.13, lng: 133.64), in: spots)?.slug,
                       "takaya-jinja", "空白は無視する")
    }

    /// 🔴 括弧の中の地名で結ばない（「パリ, フランス」→ ノートルダム大聖堂 だった）
    func testParenthesizedPlaceNameIsNotAnAlias() {
        let notreDame = spot("notre-dame", name: "ノートルダム大聖堂（パリ）", lat: 48.85, lng: 2.35,
                             prefecture: "イル＝ド＝フランス地域圏", city: "パリ")
        let pantheon = spot("pantheon-paris", name: "パンテオン（パリ）", lat: 48.85, lng: 2.35)
        let spots = [notreDame, pantheon]
        XCTAssertNil(StorySpotLink.spot(for: story(location: "パリ", lat: 48.85, lng: 2.35), in: spots))
        XCTAssertNil(StorySpotLink.spot(for: story(location: "パリ, フランス", lat: 48.85, lng: 2.35), in: spots))
        XCTAssertEqual(StorySpotLink.spot(for: story(location: "パンテオン（パリ）", lat: 48.85, lng: 2.35), in: spots)?.slug,
                       "pantheon-paris", "同じ括弧を持つ別の名所に取られない")
    }

    /// 🔴 括弧の中の語は、**地名に無い語でも**別名にしない（前の試験は「パリ」が地名として
    /// 先に落ち、括弧の規則まで届いていなかった）
    func testParenthesizedWordOutsideAreasIsNotAnAlias() {
        let temple = spot("todaiji", name: "東大寺（奈良公園）", lat: 34.69, lng: 135.84)
        XCTAssertNil(StorySpotLink.spot(for: story(location: "奈良公園", lat: 34.69, lng: 135.84), in: [temple]))
    }

    /// 🔴 英語の都市名だけの撮影地は結ばない（英語名の頭で「Kyoto」→ 京都駅ビル だった）
    func testEnglishCityNameDoesNotLink() {
        let station = spot("kyoto-station", name: "京都駅ビル 大階段", nameEn: "Kyoto Station Building",
                           lat: 34.99, lng: 135.76, prefecture: "京都府", city: "京都市")
        let helsinki = spot("helsinki-central", name: "ヘルシンキ中央駅", nameEn: "Helsinki Central Station",
                            lat: 60.17, lng: 24.94, prefecture: "ウーシマー県", city: "ヘルシンキ")
        XCTAssertNil(StorySpotLink.spot(for: story(location: "Kyoto", lat: 34.99, lng: 135.76), in: [station]))
        XCTAssertNil(StorySpotLink.spot(for: story(location: "Kyoto, Japan", lat: 34.99, lng: 135.76), in: [station]))
        XCTAssertNil(StorySpotLink.spot(for: story(location: "Helsinki, Finland", lat: 60.17, lng: 24.94), in: [helsinki]))
        XCTAssertEqual(StorySpotLink.spot(for: story(location: "Kyoto Station Building", lat: 34.99, lng: 135.76),
                                          in: [station])?.slug, "kyoto-station", "英語名そのものなら結ぶ")
        let onuma = spot("onuma", name: "赤城大沼", nameEn: "Lake Onuma, Mount Akagi", lat: 36.55, lng: 139.18)
        XCTAssertEqual(StorySpotLink.spot(for: story(location: "Lake Onuma, Mount Akagi", lat: 36.55, lng: 139.18),
                                          in: [onuma])?.slug, "onuma", "カンマ入りの英語名もそのものなら結ぶ")
    }

    /// 名前の最初の語と**完全に同じ**ときだけ（前方一致だと「明治神宮」→ 明治神宮外苑 だった）。
    /// 市町村の接尾辞を外した地名（「近江八幡」）でも結ばない
    func testFirstWordMustMatchExactlyAndNotBeAPlace() {
        let gaien = spot("gaien", name: "明治神宮外苑 いちょう並木", lat: 35.67, lng: 139.72)
        let jingu = spot("meiji-jingu", name: "明治神宮", lat: 35.68, lng: 139.70)
        XCTAssertEqual(StorySpotLink.spot(for: story(location: "明治神宮", lat: 35.67, lng: 139.72), in: [gaien, jingu])?.slug,
                       "meiji-jingu")
        XCTAssertNil(StorySpotLink.spot(for: story(location: "明治神宮", lat: 35.67, lng: 139.72), in: [gaien]))
        let hori = spot("hachiman-bori", name: "近江八幡 八幡堀", lat: 35.14, lng: 136.09,
                        prefecture: "滋賀県", city: "近江八幡市")
        XCTAssertNil(StorySpotLink.spot(for: story(location: "近江八幡", lat: 35.14, lng: 136.09), in: [hori]))
    }

    /// 郡の付いた町村（索引は「南都留郡山中湖村」）の「山中湖村」だけでは結ばない。
    /// 長く当たった名前を先に（「明治神宮外苑」が近い方の明治神宮に取られていた）
    func testCountyTownAndLongestMatch() {
        let lake = spot("lake-yamanaka", name: "山中湖", lat: 35.42, lng: 138.87,
                        prefecture: "山梨県", city: "南都留郡山中湖村")
        XCTAssertNil(StorySpotLink.spot(for: story(location: "山中湖村, 山梨県", lat: 35.42, lng: 138.87), in: [lake]))
        // 市の名前の中の「郡」では切らない（「郡上市」から「上市」を作らない）
        let gujo = spot("gujo", name: "郡上八幡城", lat: 35.75, lng: 136.96, prefecture: "岐阜県", city: "郡上市")
        XCTAssertFalse(StorySpotLink.areaNames(in: [gujo]).contains("上市"))
        XCTAssertEqual(StorySpotLink.spot(for: story(location: "山中湖", lat: 35.42, lng: 138.87), in: [lake])?.slug,
                       "lake-yamanaka")
        let gaien = spot("gaien", name: "明治神宮外苑 いちょう並木", lat: 35.67, lng: 139.72)
        let jingu = spot("meiji-jingu", name: "明治神宮", lat: 35.68, lng: 139.71)
        XCTAssertEqual(StorySpotLink.spot(for: story(location: "明治神宮外苑 いちょう並木", lat: 35.68, lng: 139.71),
                                          in: [gaien, jingu])?.slug, "gaien")
    }

    func testShortenedPlace() {
        XCTAssertEqual(StorySpotLink.shortened("高屋神社"), "高屋神社")
        let long = String(repeating: "あ", count: 30)
        XCTAssertEqual(StorySpotLink.shortened(long).count, StorySpotLink.maxShownLength)
        XCTAssertTrue(StorySpotLink.shortened(long).hasSuffix("…"))
    }

    /// 🔴 市区町村・都道府県だけの撮影地は結ばない（名前が地名の一部でも）
    func testAreaOnlyLocationDoesNotLink() {
        let himeshima = spot("himeshima", name: "姫島", lat: 33.72, lng: 131.64, prefecture: "大分県", city: "姫島村")
        let towada = spot("towada-art", name: "十和田市現代美術館", lat: 40.61, lng: 141.20, prefecture: "青森県", city: "十和田市")
        let spots = [himeshima, towada, takaya]
        XCTAssertNil(StorySpotLink.spot(for: story(location: "姫島村, 大分県, 日本", lat: 33.72, lng: 131.64), in: spots))
        XCTAssertNil(StorySpotLink.spot(for: story(location: "十和田市", lat: 40.61, lng: 141.20), in: spots))
        XCTAssertNil(StorySpotLink.spot(for: story(location: "観音寺市, 香川県", lat: 34.13, lng: 133.64), in: spots))
        XCTAssertEqual(StorySpotLink.spot(for: story(location: "姫島", lat: 33.72, lng: 131.64), in: spots)?.slug,
                       "himeshima", "スポットの名前そのものなら結ぶ")
    }

    /// 🔴 座標の無いストーリーは結ばない（「飛島村」が山形の飛島に当たった）
    func testWithoutCoordsNeverLinks() {
        XCTAssertNil(StorySpotLink.spot(for: story(location: "高屋神社"), in: [takaya]))
    }

    /// 同じ名前でも遠ければ別の場所。近い方を選ぶ
    func testDistanceDisambiguatesSameName() {
        let near = spot("tenjin-a", name: "天神社", lat: 35.00, lng: 135.00)
        let far = spot("tenjin-b", name: "天神社", lat: 36.00, lng: 138.00)
        XCTAssertEqual(StorySpotLink.spot(for: story(location: "天神社", lat: 35.01, lng: 135.01), in: [far, near])?.slug,
                       "tenjin-a")
        XCTAssertNil(StorySpotLink.spot(for: story(location: "天神社", lat: 40.0, lng: 140.0), in: [near, far]),
                     "\(StorySpotLink.maxKm)km より遠いなら結ばない")
    }

    /// 下書きは結ばない・「旧・」の旧称と英語名では当たる
    func testDraftsAndAlternateNames() {
        let draft = spot("draft", name: "高屋神社 本宮", lat: 34.13, lng: 133.64, stage: "review")
        XCTAssertNil(StorySpotLink.spot(for: story(location: "高屋神社", lat: 34.13, lng: 133.64), in: [draft]))
        let renamed = spot("asmui", name: "ASMUI Spiritual Hikes（旧・大石林山）", lat: 26.85, lng: 128.25)
        XCTAssertEqual(StorySpotLink.spot(for: story(location: "大石林山", lat: 26.85, lng: 128.25), in: [renamed])?.slug,
                       "asmui", "「旧・」の旧称で当てる")
        let en = spot("matterhorn", name: "マッターホルン", nameEn: "Matterhorn", lat: 45.98, lng: 7.66)
        XCTAssertEqual(StorySpotLink.spot(for: story(location: "Matterhorn, Zermatt", lat: 45.98, lng: 7.66), in: [en])?.slug,
                       "matterhorn")
    }

    func testSplitParentheses() {
        XCTAssertEqual(StorySpotLink.splitParentheses("A（B）").outer, "A")
        XCTAssertEqual(StorySpotLink.splitParentheses("A（B）").inner, ["B"])
        XCTAssertEqual(StorySpotLink.splitParentheses("A").inner, [])
    }
}
