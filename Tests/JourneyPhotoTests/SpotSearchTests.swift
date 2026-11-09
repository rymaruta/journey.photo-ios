import XCTest
@testable import JourneyPhoto

/// 撮影スポットの一覧（地図のタブの「スポット」の札）の検索窓（2026-11-09・owner「撮影スポットを探す一覧に検索窓がほしい」）。
///
/// 引くのは `SpotSearchIndex`（手元の索引だけ・通信しない）。画面は Linux で描けないので、
/// 純粋な当て方・並びは値で、画面のつなぎはソースの突き合わせで確かめる。
final class SpotSearchTests: XCTestCase {

    private func spot(_ slug: String, name: String, nameEn: String? = nil, reading: String? = nil,
                      prefecture: String? = nil, city: String? = nil,
                      lat: Double? = nil, lng: Double? = nil) throws -> OfficialSpot {
        var json = "{\"spotId\":\"sp_\(slug)\",\"slug\":\"\(slug)\",\"name\":\"\(name)\",\"stage\":\"published\""
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
            try spot("kotohira", name: "金刀比羅宮", reading: "ことひらぐう", prefecture: "香川県", city: "仲多度郡琴平町",
                     lat: 34.18, lng: 133.81),
            try spot("arashiyama", name: "嵐山 渡月橋", reading: "あらしやまとげつきょう", prefecture: "京都府", city: "京都市右京区",
                     lat: 35.01, lng: 135.68),
            try spot("hotel-takaya", name: "ホテルたかや展望台", reading: "ほてるたかやてんぼうだい", prefecture: "北海道", city: "網走市",
                     lat: 44.02, lng: 144.28),
        ]
    }

    private func slugs(_ query: String, in spots: [OfficialSpot]) -> [String] {
        SpotSearchIndex(spots).hits(query: query).map(\.spot.slug)
    }

    // MARK: - 揃え方

    /// ひらがな・カタカナの違いを見ない（読みはひらがなで持つので、カタカナで打っても当たる）
    func testKanaIsFolded() throws {
        let spots = try index()
        XCTAssertEqual(slugs("たかや", in: spots).first, "takaya-jinja")
        XCTAssertEqual(slugs("タカヤ", in: spots).first, "takaya-jinja")
        XCTAssertEqual(slugs("コトヒラ", in: spots), ["kotohira"])
        // 名前がカタカナ・打つのがひらがな
        XCTAssertEqual(slugs("ほてる", in: spots), ["hotel-takaya"])
        XCTAssertEqual(slugs("ホテル", in: spots), ["hotel-takaya"])
        // 半角カタカナ（NFKC で全角になってからひらがなへ）
        XCTAssertEqual(slugs("ﾀｶﾔ", in: spots).first, "takaya-jinja")
        XCTAssertEqual(OfficialSpotIndex.foldKana("ガーデン・ヴ"), "がーでん・ゔ")
    }

    /// 全角半角・大文字小文字・空白・括弧は見ない（従来どおり）
    func testWidthCaseAndSpacesAreIgnored() throws {
        let spots = try index()
        XCTAssertEqual(slugs("ＴＡＫＡＹＡ", in: spots), ["takaya-jinja"])
        XCTAssertEqual(slugs("takaya shrine", in: spots), ["takaya-jinja"])
        XCTAssertEqual(slugs("嵐山渡月橋", in: spots), ["arashiyama"])
        XCTAssertEqual(slugs("嵐山 渡月橋", in: spots), ["arashiyama"])
    }

    /// 部分一致（名前の途中・県名・市区町村名）
    func testPartialMatchOnNameAndRegion() throws {
        let spots = try index()
        XCTAssertEqual(slugs("月橋", in: spots), ["arashiyama"])
        XCTAssertEqual(Set(slugs("香川", in: spots)), ["takaya-jinja", "kotohira"])
        XCTAssertEqual(slugs("網走", in: spots), ["hotel-takaya"])
        XCTAssertEqual(slugs("京都", in: spots), ["arashiyama"])
    }

    func testEmptyQueryMatchesNothing() throws {
        XCTAssertTrue(SpotSearchIndex(try index()).hits(query: "").isEmpty)
        XCTAssertTrue(SpotSearchIndex(try index()).hits(query: " 　\n").isEmpty)
    }

    // MARK: - 複数語は AND

    func testMultipleWordsAreAnded() throws {
        let spots = try index()
        // 名前の語 + 県
        XCTAssertEqual(slugs("高屋 香川", in: spots), ["takaya-jinja"])
        XCTAssertEqual(slugs("香川 高屋", in: spots), ["takaya-jinja"])
        // 全角空白・読点でも区切る
        XCTAssertEqual(slugs("高屋　香川", in: spots), ["takaya-jinja"])
        XCTAssertEqual(slugs("高屋、香川", in: spots), ["takaya-jinja"])
        // どれかの語が外れれば出ない
        XCTAssertTrue(slugs("高屋 北海道", in: spots).isEmpty)
        // 同じ「たかや」でも県で分かれる
        XCTAssertEqual(slugs("たかや 北海道", in: spots), ["hotel-takaya"])
        // 地域の語だけの AND は従来どおり（神奈川 箱根 の形）
        XCTAssertEqual(slugs("香川 観音寺", in: spots), ["takaya-jinja"])
    }

    // MARK: - 並び

    /// 名前の前方一致が先・部分一致が次・地域だけが最後（同じ段は索引の順）
    func testNamePrefixComesBeforeContainsBeforeRegion() throws {
        let spots = [
            try spot("region-only", name: "岬の灯台", prefecture: "高知県"),
            try spot("contains", name: "ホテルこうち展望台"),
            try spot("prefix", name: "高知城"),
        ]
        let hits = SpotSearchIndex(spots).hits(query: "高知")
        XCTAssertEqual(hits.map(\.spot.slug), ["prefix", "region-only"])
        XCTAssertEqual(hits.map(\.rank), [1, 3])
        // 「こうち」はひらがな: 「ホテルこうち…」の部分一致（読みの無い「高知城」は当たらない）
        let kana = SpotSearchIndex(spots).hits(query: "こうち")
        XCTAssertEqual(kana.map(\.spot.slug), ["contains"])
        XCTAssertEqual(kana.map(\.rank), [2])
    }

    /// AND の順位はいちばん弱い語（名前の前方一致 + 地域の語 = 地域の段）
    func testAndRankIsTheWeakestWord() throws {
        let hits = SpotSearchIndex(try index()).hits(query: "高屋 香川")
        XCTAssertEqual(hits.map(\.rank), [3])
    }

    /// 一覧の並び: 語があるときは当たりの強さが先、同じ強さの中だけ近い順。語が無ければ近い順のまま
    func testListRowsFollowRankThenDistance() throws {
        let near = try spot("near-region", name: "近い灯台", prefecture: "香川県", lat: 34.0, lng: 133.0)
        let far = try spot("far-name", name: "香川の展望台", lat: 40.0, lng: 140.0)
        let here = Photo.Coords(lat: 34.0, lng: 133.0)
        // 語なし: 近い順
        XCTAssertEqual(OfficialSpotList.rows([far, near], photos: [], from: here).map(\.spot.slug),
                       ["near-region", "far-name"])
        // 語あり: 名前の前方一致（1）が地域（3）より先——遠くても
        let hits = SpotSearchIndex([far, near]).hits(query: "香川")
        let ranks = Dictionary(uniqueKeysWithValues: hits.map { ($0.spot.spotId, $0.rank) })
        XCTAssertEqual(OfficialSpotList.rows(hits.map(\.spot), photos: [], from: here, ranks: ranks).map(\.spot.slug),
                       ["far-name", "near-region"])
    }

    // MARK: - 従来の入口は同じ当て方

    /// `OfficialSpotIndex.matches`（地図のピン・探す）も、索引と同じ答え
    func testMatchesAgreesWithTheIndex() throws {
        let spots = try index()
        for query in ["タカヤ", "高屋 香川", "香川", "月橋", "zzz"] {
            XCTAssertEqual(OfficialSpotIndex.matches(spots, query: query).map(\.slug), slugs(query, in: spots), query)
        }
        XCTAssertEqual(OfficialSpotIndex.matches(spots, query: "香川", limit: 1).count, 1)
    }

    // MARK: - 速さ

    /// 4,000件でも、折りたたんだ索引を作ってから引くのは一瞬（毎キー入力で全件を折りたたまない）。
    /// 数字の厳密な測定ではなく、桁違いに遅くなっていないことの見張り
    func testFourThousandSpotsStayQuick() throws {
        var spots: [OfficialSpot] = []
        for i in 0..<4000 {
            spots.append(try spot("s\(i)", name: "撮影スポット\(i)", reading: "さつえいすぽっと\(i)",
                                  prefecture: i % 2 == 0 ? "北海道" : "沖縄県", city: "市\(i % 50)"))
        }
        let index = SpotSearchIndex(spots)
        XCTAssertEqual(index.count, 4000)
        let start = Date()
        for query in ["さつえい", "撮影 沖縄", "市7", "スポット39"] { _ = index.hits(query: query) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0, "4,000件の絞りが遅い")
        XCTAssertEqual(index.hits(query: "スポット3999").first?.spot.slug, "s3999")
    }

    // MARK: - 画面のつなぎ（ソースの突き合わせ）

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    /// 「スポット」の札は、索引の当たり順で並べ、検索キーを出し、薄い字で引ける項目を言う。
    /// 戻すと（近い順だけに戻す・毎回全件を折りたたむ・キーが「改行」）落ちる
    func testSpotsTabIsWired() throws {
        let map = try source("Features/Map/PhotoMapView.swift")
        XCTAssertTrue(map.contains("model.spotSearchHits(query: model.query)"), "一覧が折りたたみ済みの索引を使っていない")
        XCTAssertTrue(map.contains("OfficialSpotList.rows(spots, photos: model.photos, from: center, links: model.photoLinks, ranks: ranks)"),
                      "語があるときの並びが当たりの強さ順でない")
        XCTAssertFalse(map.contains("OfficialSpotIndex.matches(model.officialSpots, query: model.query, aliases: model.spotAliases)\n        let rows"),
                       "一覧が毎回全件を折りたたむ引き方に戻っている")
        XCTAssertTrue(map.contains(".submitLabel(.search)"), "キーボードの確定キーが「検索」でない")
        XCTAssertTrue(map.contains("TextField(Self.searchPrompt(for: model.mode), text: $model.typedQuery)"))
        // 既存の約束: 間引き・確定・消す・44pt
        XCTAssertTrue(map.contains(".onSubmit { model.commitTypedQuery() }"))
        XCTAssertTrue(map.contains(".accessibilityLabel(L(\"消す\", \"Clear\"))"))
        XCTAssertEqual(PhotoMapView.searchFieldHeight, WebTheme.minTapTarget)

        let model = try source("Features/Map/PhotoMapViewModel.swift")
        XCTAssertTrue(model.contains("private(set) var officialSpots: [OfficialSpot] = [] { didSet { spotSearchCache = nil } }"),
                      "索引が替わっても古い折りたたみ済みの索引を使い続ける")
        XCTAssertTrue(model.contains("[String: [String]] = [:] { didSet { spotSearchCache = nil } }"),
                      "別名が替わっても古い折りたたみ済みの索引を使い続ける")
    }

    /// 薄い字: 「スポット」の札は引ける項目、ほかは従来の言い方（日英）
    func testSearchPrompt() {
        XCTAssertEqual(PhotoMapView.searchPrompt(for: .spots), L("スポット名・県・エリア", "Spot name, prefecture or area"))
        XCTAssertEqual(PhotoMapView.searchPrompt(for: .map), L("撮影地・撮影スポット名で絞る", "Filter by place or photo spot"))
        XCTAssertEqual(PhotoMapView.searchPrompt(for: .list), PhotoMapView.searchPrompt(for: .map))
    }
}
