import XCTest
@testable import JourneyPhoto

/// 探すの撮影スポットの節の行の控え（`SearchSpotHits`）と、字をそろえ終えた索引（`OfficialSpotIndex.Prepared`）。
/// 2026-11-13 札 #590「探すの検索が重い」: 1字ごとに全件へ 9〜12 回当て直していた（Mac の回 1219）
final class SearchSpotHitsTests: XCTestCase {

    private func spot(_ slug: String, name: String, nameEn: String? = nil, reading: String? = nil,
                      country: String? = nil, prefecture: String? = nil, city: String? = nil,
                      stage: String = "published", season: String? = nil) throws -> OfficialSpot {
        var json = "{\"spotId\":\"sp_\(slug)\",\"slug\":\"\(slug)\",\"name\":\"\(name)\",\"stage\":\"\(stage)\""
        if let nameEn { json += ",\"nameEn\":\"\(nameEn)\"" }
        if let reading { json += ",\"reading\":\"\(reading)\"" }
        if country != nil || prefecture != nil || city != nil {
            let parts = [country.map { "\"country\":\"\($0)\"" }, prefecture.map { "\"prefecture\":\"\($0)\"" },
                         city.map { "\"city\":\"\($0)\"" }]
            json += ",\"region\":{\(parts.compactMap { $0 }.joined(separator: ","))}"
        }
        if let season { json += ",\"seasonalGuide\":[{\"season\":\"\(season)\",\"text\":\"案内\"}]" }
        json += "}"
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(json.utf8))
    }

    private func corpus() throws -> [OfficialSpot] {
        [
            try spot("kinkakuji", name: "金閣寺（鹿苑寺）", nameEn: "Kinkaku-ji", reading: "きんかくじ",
                     prefecture: "京都府", city: "京都市北区", season: "autumn"),
            try spot("arashiyama", name: "嵐山 渡月橋", nameEn: "Arashiyama Togetsukyo", reading: "あらしやま とげつきょう",
                     prefecture: "京都府", city: "京都市右京区"),
            try spot("tokyo-station", name: "東京駅", nameEn: "Tokyo Station", reading: "とうきょうえき",
                     prefecture: "東京都", city: "千代田区"),
            try spot("fuji-5", name: "富士山 五合目", nameEn: "Mt. Fuji 5th Station", reading: "ふじさん ごごうめ",
                     prefecture: "山梨県", city: "南都留郡鳴沢村", season: "winter"),
            try spot("fujinomiya", name: "富士宮の白糸の滝", reading: "ふじのみやのしらいとのたき",
                     prefecture: "静岡県", city: "富士宮市"),
            try spot("hakone", name: "芦ノ湖", nameEn: "Lake Ashi", reading: "あしのこ",
                     prefecture: "神奈川県", city: "足柄下郡箱根町"),
            try spot("sevilla", name: "スペイン広場", nameEn: "Plaza de España",
                     country: "スペイン", prefecture: "アンダルシア州", city: "セビリア"),
            try spot("japan-row", name: "本栖湖", reading: "もとすこ", country: "日本", prefecture: "山梨県"),
            try spot("draft-kyoto", name: "京都の下書き", reading: "きょうとのしたがき", prefecture: "京都府", stage: "draft"),
            try spot("no-region", name: "ＳＡＫＵＲＡ　Ｔｒｅｅ", nameEn: "Sakura Tree"),
            // 合成できない半濁点（か + U+309A）。バイト列では「か」を含むが、字としては「か゚」で「か」ではない
            try spot("semi-voiced", name: "か\u{309A}き山", reading: "か\u{309A}きやま", prefecture: "か\u{309A}き県"),
            // 「パ」（合成済み U+30D1）と「ハ」の組。「ハ」で「パ」を含む名前に当たるかは、直す前の当て方と同じであること
            //（2026-11-13 確かめ役の指摘。Darwin での振る舞いは Mac の回で見る）
            try spot("panorama", name: "パノラマ台", nameEn: "Panorama Point", reading: "ぱのらまだい", prefecture: "山梨県"),
            try spot("hanoura", name: "ハノ浦", reading: "はのうら", prefecture: "パ県"),
            // 分けた形（ハ + U+309A）で載っている名前
            try spot("decomposed-pa", name: "ハ\u{309A}ン屋", reading: "は\u{309A}んや"),
        ]
    }

    private let aliases = ["kinkakuji": ["金閣", "Golden Pavilion"], "fuji-5": ["富士山（吉田口）"]]

    /// 直す前（2026-11-13 まで）の当て方の写し。呼ぶたびに全件の字をそろえ直していた。
    /// **当て方・並びが前と同じこと**を、この写しと突き合わせて確かめる
    private func legacyMatches(_ spots: [OfficialSpot], query: String, aliases: [String: [String]]) -> [OfficialSpot] {
        func rankByNames(_ names: [String?], _ needle: String) -> Int {
            var rank = -1
            for raw in names {
                let name = OfficialSpotIndex.spotName(raw)
                if name.isEmpty { continue }
                if name == needle { return 0 }
                if name.hasPrefix(needle) { rank = 1; continue }
                if name.contains(needle), rank < 0 { rank = 2 }
            }
            return rank
        }
        let needle = OfficialSpotIndex.spotName(query)
        guard !needle.isEmpty else { return [] }
        return spots.enumerated()
            .compactMap { i, spot -> (OfficialSpot, Int, Int)? in
                var rank = rankByNames([spot.name, spot.nameEn, spot.reading] + (aliases[spot.slug] ?? []), needle)
                if rank < 0, legacyRegionMatches(spot, query: query) { rank = 3 }
                return rank < 0 ? nil : (spot, rank, i)
            }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.2 < $1.2 }
            .map(\.0)
    }

    /// 直す前の `regionMatches` の写し（行ごと・語ごとに字をそろえ直していた）
    private func legacyRegionMatches(_ spot: OfficialSpot, query: String) -> Bool {
        guard let r = spot.region else { return false }
        let country = r.country == "日本" ? nil : r.country
        let pair: String = [r.prefecture, r.city].compactMap { $0 }.joined()
        let whole: String = [country, r.prefecture, r.city].compactMap { $0 }.joined()
        let fields = [country, r.prefecture, r.city, pair, whole].map(OfficialSpotIndex.spotName).filter { !$0.isEmpty }
        func hit(_ word: String) -> Bool {
            !word.isEmpty && fields.contains { $0.hasPrefix(word) || LocationMatch.nameIn($0, word, boundaries: ["州", "地方"]) }
        }
        let words = query.components(separatedBy: CharacterSet(charactersIn: "、,，").union(.whitespacesAndNewlines))
            .map(OfficialSpotIndex.spotName).filter { !$0.isEmpty }
        if words.count > 1, words.allSatisfy(hit) { return true }
        return hit(OfficialSpotIndex.spotName(query))
    }

    private let queries = ["京", "京都", "京都 嵐", "京都 嵐山", "嵐山渡月橋", "東京", "東京都千代田区", "富", "富士", "富士山",
                           "ふじ", "金閣", "golden", "ＧＯＬＤＥＮ", "sakura tree", "さくら", "神奈", "神奈川 箱根", "箱根",
                           "神奈川 京都", "アンダルシア", "スペイン", "日本", "山梨", "（吉田口）", "s", "a", "zzzz", "", "  ",
                           // 合成した字・分けた字（バイト列の下調べが字と同じ答えになるか）
                           "españa", "Espan\u{0303}a", "ＥＳＰＡÑＡ", "de esp", "ﾌｼﾞ", "ﾌﾞ", "か", "き山", "か\u{309A}",
                           "ハ", "パ", "ハノ", "パノ", "ﾊﾟ", "ﾊ", "は", "ぱ", "ハ\u{309A}", "ハ\u{309A}ン", "パン", "ﾊﾟﾝ", "パ県"]

    /// そろえ終えた索引で当てても、直す前の当て方と**同じ行が同じ順で**返る（語・別名・地域・幅と大小・空白と括弧）
    func testPreparedMatchesSameAsBefore() throws {
        let spots = try corpus()
        let prepared = OfficialSpotIndex.Prepared(spots, aliases: aliases)
        XCTAssertEqual(prepared.count, spots.count)
        for q in queries {
            let before = legacyMatches(spots, query: q, aliases: aliases).map(\.slug)
            XCTAssertEqual(prepared.matches(query: q).map(\.slug), before, "語「\(q)」")
            XCTAssertEqual(OfficialSpotIndex.matches(spots, query: q, aliases: aliases).map(\.slug), before, "語「\(q)」")
            XCTAssertEqual(prepared.matches(query: q, limit: 2).map(\.slug), Array(before.prefix(2)), "語「\(q)」")
            for s in spots {
                XCTAssertEqual(OfficialSpotIndex.regionMatches(s, query: q), legacyRegionMatches(s, query: q),
                               "地域「\(q)」\(s.slug)")
            }
        }
        // 京都で東京都を混ぜない（2026-10-07 判断のまま）
        XCTAssertFalse(prepared.matches(query: "京都").map(\.slug).contains("tokyo-station"))
    }

    /// 控え: 探すの節の行は、直す前の `SearchView.spotHits`（下書きを落とす → 当てる → 季節・時間帯）と同じ
    func testHitsSameAsBefore() throws {
        let spots = try corpus()
        let memo = SearchSpotHits()
        let index = SearchSpotHits.prepare(spots: spots, aliases: aliases)
        let published = spots.filter { !$0.isDraft }
        for q in queries {
            for filter in [ShootingTime.Filter(), ShootingTime.Filter(season: .autumn)] {
                let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
                let before: [String] = (!t.isEmpty || !filter.isEmpty)
                    ? ShootingTime.spots(t.isEmpty ? published : legacyMatches(published, query: t, aliases: aliases),
                                         filter: filter).map(\.slug)
                    : []
                let hits = memo.hits(spots: spots, index: index, query: q, filter: filter, showsSpots: true)
                XCTAssertEqual(hits.rows.map(\.slug), before, "語「\(q)」\(filter)")
                XCTAssertFalse(hits.pending)
            }
            XCTAssertEqual(memo.hits(spots: spots, index: index, query: q, filter: .init(), showsSpots: false), .init())
        }
        XCTAssertFalse(memo.hits(spots: spots, index: index, query: "京都", filter: .init(), showsSpots: true).rows
            .contains { $0.isDraft }, "下書きは出さない")
    }

    /// 🔴 一覧は届いたが、そろえた索引がまだ（主スレッドの外で作っている最中）の間は**読み込み中**。
    /// 0件と扱わない（「見つかりませんでした」と言わない・2026-11-13 確かめ役の指摘）
    func testPendingWhileIndexIsBeingPrepared() throws {
        let spots = try corpus()
        let memo = SearchSpotHits()
        let waiting = memo.hits(spots: spots, index: nil, query: "京都", filter: .init(), showsSpots: true)
        XCTAssertTrue(waiting.pending)
        XCTAssertFalse(waiting.isEmpty, "作っている最中を0件と言っている")
        // 索引ができたら当たる
        let ready = memo.hits(spots: spots, index: SearchSpotHits.prepare(spots: spots, aliases: aliases), query: "京都",
                              filter: .init(), showsSpots: true)
        XCTAssertFalse(ready.pending)
        XCTAssertFalse(ready.rows.isEmpty)
        // 本当に何も当たらないときは0件と言ってよい
        let none = memo.hits(spots: spots, index: SearchSpotHits.prepare(spots: spots, aliases: aliases), query: "zzzz",
                             filter: .init(), showsSpots: true)
        XCTAssertTrue(none.isEmpty)
        // 語が無い（季節だけ）ときは索引を待たない（今の行を絞るだけ）
        let seasonOnly = memo.hits(spots: spots, index: nil, query: "", filter: .init(season: .autumn), showsSpots: true)
        XCTAssertFalse(seasonOnly.pending)
        XCTAssertEqual(seasonOnly.rows.map(\.slug), ["kinkakuji"])
        // 一覧がまだ無い（索引そのものを読んでいる）ときは、今までどおり空（この直しの外）
        XCTAssertFalse(memo.hits(spots: [], index: nil, query: "京都", filter: .init(), showsSpots: true).pending)
        // 0件の文を上に出すかも、読み込み中なら出さない
        XCTAssertFalse(SearchView.zeroHitOnTop(discovering: false, showsPhotos: true, hasLoaded: true, photosEmpty: true,
                                               spotsEmpty: true, spotsPending: true, usersEmpty: true, loadFailed: false))
        XCTAssertTrue(SearchView.zeroHitOnTop(discovering: false, showsPhotos: true, hasLoaded: true, photosEmpty: true,
                                              spotsEmpty: true, spotsPending: false, usersEmpty: true, loadFailed: false))
    }

    /// 🔴 **body の中で何度呼ばれても、同じ語・同じ索引なら当てるのは1回**
    func testMemoComputesOncePerQuery() throws {
        let spots = try corpus()
        let memo = SearchSpotHits()
        let index = SearchSpotHits.prepare(spots: spots, aliases: aliases)
        for _ in 0..<12 {
            _ = memo.hits(spots: spots, index: index, query: "京", filter: .init(), showsSpots: true)
        }
        XCTAssertEqual(memo.computeCount, 1, "同じ語で当て直している")
        // 前後の空白だけ違う語も同じ
        _ = memo.hits(spots: spots, index: index, query: " 京 ", filter: .init(), showsSpots: true)
        XCTAssertEqual(memo.computeCount, 1)
        // 語が替われば当て直す
        for _ in 0..<5 { _ = memo.hits(spots: spots, index: index, query: "京都", filter: .init(), showsSpots: true) }
        XCTAssertEqual(memo.computeCount, 2)
        // 絞り込みが替われば当て直す
        _ = memo.hits(spots: spots, index: index, query: "京都", filter: .init(season: .autumn), showsSpots: true)
        XCTAssertEqual(memo.computeCount, 3)
    }

    /// 索引が作り直されたら（届いた・別名が届いた）、同じ語でも当て直す（古い行を出さない）
    func testMemoRefreshesWhenIndexChanges() throws {
        var spots = try corpus()
        let memo = SearchSpotHits()
        let plain = SearchSpotHits.prepare(spots: spots, aliases: [:])
        // 「golden」は別名「Golden Pavilion」でだけ当たる
        XCTAssertEqual(memo.hits(spots: spots, index: plain, query: "golden", filter: .init(), showsSpots: true).rows, [])
        let withAliases = SearchSpotHits.prepare(spots: spots, aliases: aliases)
        XCTAssertEqual(memo.hits(spots: spots, index: withAliases, query: "golden", filter: .init(), showsSpots: true)
            .rows.map(\.slug), ["kinkakuji"])
        XCTAssertEqual(memo.computeCount, 2)
        // 行が足された一覧が届いた。作り直している間は前の索引の行で当てる（節は消えない）
        spots.append(try spot("kinkaku-2", name: "金閣の池", prefecture: "京都府"))
        XCTAssertEqual(memo.hits(spots: spots, index: withAliases, query: "金閣", filter: .init(), showsSpots: true)
            .rows.map(\.slug), ["kinkakuji"])
        let more = SearchSpotHits.prepare(spots: spots, aliases: aliases)
        XCTAssertEqual(memo.hits(spots: spots, index: more, query: "金閣", filter: .init(), showsSpots: true).rows.map(\.slug),
                       ["kinkakuji", "kinkaku-2"])
    }

    /// 🔴 詳細を重ねた（季節の案内が届いた）だけなら材料は同じ。**索引を作り直さず、今の一覧の行を返す**
    /// （案内の文が作り直しを待たずに出る・2026-11-13 確かめ役の指摘）
    func testDetailOverlayUsesCurrentRowsWithoutRebuild() throws {
        let bare = try corpus().map { $0.slug == "arashiyama" ? try spot("arashiyama", name: "嵐山 渡月橋",
            nameEn: "Arashiyama Togetsukyo", reading: "あらしやま とげつきょう", prefecture: "京都府", city: "京都市右京区") : $0 }
        let overlaid = try bare.map { $0.slug == "arashiyama" ? try spot("arashiyama", name: "嵐山 渡月橋",
            nameEn: "Arashiyama Togetsukyo", reading: "あらしやま とげつきょう", prefecture: "京都府", city: "京都市右京区",
            season: "autumn") : $0 }
        XCTAssertTrue(SearchSpotHits.sameMaterial(bare, overlaid), "詳細を重ねただけで作り直す")
        let index = SearchSpotHits.prepare(spots: bare, aliases: aliases)
        let memo = SearchSpotHits()
        let filter = ShootingTime.Filter(season: .autumn)
        XCTAssertEqual(memo.hits(spots: bare, index: index, query: "嵐山", filter: filter, showsSpots: true).rows.map(\.slug), [])
        // 同じ索引のまま、案内の届いた一覧を渡す
        let hits = memo.hits(spots: overlaid, index: index, query: "嵐山", filter: filter, showsSpots: true)
        XCTAssertEqual(hits.rows.map(\.slug), ["arashiyama"])
        XCTAssertNotNil(ShootingTime.guide(for: try XCTUnwrap(hits.rows.first), filter: filter), "案内の文が今の行から来ていない")
    }

    /// 当てる材料が替われば作り直す（名前・行の増減・下書きかどうか）
    func testSameMaterial() throws {
        let spots = try corpus()
        XCTAssertTrue(SearchSpotHits.sameMaterial(spots, spots.map { $0 }))
        XCTAssertFalse(SearchSpotHits.sameMaterial(spots, Array(spots.dropLast())))
        XCTAssertFalse(SearchSpotHits.sameMaterial(spots, try spots.map {
            $0.slug == "hakone" ? try spot("hakone", name: "芦ノ湖（改）", prefecture: "神奈川県") : $0 }))
        XCTAssertFalse(SearchSpotHits.sameMaterial(spots, try spots.map {
            $0.slug == "hakone" ? try spot("hakone", name: "芦ノ湖", nameEn: "Lake Ashi", reading: "あしのこ",
                                           prefecture: "神奈川県", city: "足柄下郡箱根町", stage: "draft") : $0 }))
    }

    /// 🔴 索引を作るのは**語があって、今の世代の索引がまだ無いときだけ**（画面に戻った・詳細を重ねたでは作り直さない）
    func testShouldBuildOnlyWhenNeededAndStale() {
        let need = SearchSpotHits.IndexNeed(generation: 3, needed: true)
        XCTAssertTrue(SearchSpotHits.shouldBuild(need, builtGeneration: nil, hasSpots: true))
        XCTAssertTrue(SearchSpotHits.shouldBuild(need, builtGeneration: 2, hasSpots: true))
        XCTAssertFalse(SearchSpotHits.shouldBuild(need, builtGeneration: 3, hasSpots: true), "同じ材料で作り直している")
        XCTAssertFalse(SearchSpotHits.shouldBuild(.init(generation: 3, needed: false), builtGeneration: nil, hasSpots: true),
                       "語が無いのに作っている")
        XCTAssertFalse(SearchSpotHits.shouldBuild(need, builtGeneration: nil, hasSpots: false))
    }

    /// 節を出さない・語も絞り込みも無いときは、控えが古い索引・一覧を握り続けない
    func testMemoReleasesIndexWhenUnused() throws {
        let spots = try corpus()
        let memo = SearchSpotHits()
        let index = SearchSpotHits.prepare(spots: spots, aliases: aliases)
        _ = memo.hits(spots: spots, index: index, query: "京", filter: .init(), showsSpots: true)
        XCTAssertTrue(memo.holdsIndex)
        _ = memo.hits(spots: spots, index: index, query: "京", filter: .init(), showsSpots: false)
        XCTAssertFalse(memo.holdsIndex, "節を出さないのに握っている")
        _ = memo.hits(spots: spots, index: index, query: "京", filter: .init(), showsSpots: true)
        XCTAssertTrue(memo.holdsIndex)
        _ = memo.hits(spots: spots, index: index, query: "  ", filter: .init(), showsSpots: true)
        XCTAssertFalse(memo.holdsIndex, "語が空なのに握っている")
        // 手放した後も、同じ語で正しく当て直す
        XCTAssertEqual(memo.hits(spots: spots, index: index, query: "京", filter: .init(), showsSpots: true).rows.isEmpty, false)
    }

    /// 🔴 探すの配線: `spotHits` が控えを通る・字をそろえるのは主スレッドの外で、語があるとき・材料が替わったときだけ・
    /// 作っている最中は0件と言わない。戻すと落ちる
    func testSearchViewWiring() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Features/Search/SearchView.swift")
        let search = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(search.contains("@State private var spotHitsMemo = SearchSpotHits()"))
        let hits = try XCTUnwrap(search.range(of: "private var spotHitsResult: SearchSpotHits.Hits {"))
        let body = search[hits.upperBound...].prefix(500)
        XCTAssertTrue(body.contains("spotHitsMemo.hits(spots: officialSpots, index: spotSearchIndex, query: query,"), String(body))
        XCTAssertFalse(body.contains("OfficialSpotIndex.matches("), "body の中で全件に直に当てている")
        XCTAssertFalse(body.contains("prepare("), "body の中で字をそろえている")
        let task = try XCTUnwrap(search.range(of: ".task(id: SearchSpotHits.IndexNeed(generation: spotMaterialGeneration,"))
        let taskBody = search[task.upperBound...].prefix(1200)
        XCTAssertTrue(taskBody.contains("guard SearchSpotHits.shouldBuild(need, builtGeneration: spotSearchIndexGeneration,"),
                      "同じ材料でも作り直している")
        XCTAssertTrue(taskBody.contains("await Task.detached(priority: .userInitiated) {\n                SearchSpotHits.prepare(spots: spots, aliases: aliases)"),
                      "字をそろえるのが主スレッドの外ではない")
        XCTAssertTrue(search.contains("if !SearchSpotHits.sameMaterial(old, spots) { spotMaterialGeneration += 1 }"),
                      "詳細を重ねただけで作り直す")
        XCTAssertTrue(search.contains("spotsEmpty: spotHits.isEmpty, spotsPending: spotHitsResult.pending,"),
                      "作っている最中に0件の文を上に出す")
        XCTAssertTrue(search.contains(": (spotHitsResult.isEmpty ? L(\"見つかりませんでした\""),
                      "作っている最中に「見つかりませんでした」と言う")
    }

    /// 🔴 時間帯のチップが押せるか（`availableDayParts`）は、撮影地の側を**索引が替わったときだけ**数えた控えから出す。
    /// body の中で全件（3,899 件）を見直す形に戻すと落ちる（2026-11-14・Mac の回 1235 の×で消した直後の積み）
    func testAvailableDayPartsUsesCachedSpotParts() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Features/Search/SearchView.swift")
        let search = try String(contentsOf: url, encoding: .utf8)
        let getter = try XCTUnwrap(search.range(of: "private var availableDayParts: Set<ShootingTime.DayPart> {"))
        let body = search[getter.upperBound...].prefix(200)
        XCTAssertTrue(body.contains("model.dayPartsWithPhotos.union(spotDayParts)"), String(body))
        XCTAssertFalse(body.contains("ShootingTime.dayParts("), "body の中で全件を見直している")
        let change = try XCTUnwrap(search.range(of: ".onChange(of: officialSpots) { old, spots in"))
        XCTAssertTrue(search[change.upperBound...].prefix(700).contains("spotDayParts = ShootingTime.dayParts(photos: [], spots: spots)"),
                      "索引が替わったときに数え直していない（古い時間帯のまま）")
        // 控えの中身は、全件を見直したときと同じ（下書きは数えない）
        let spots = try corpus()
        XCTAssertEqual(ShootingTime.dayParts(photos: [], spots: spots),
                       ShootingTime.dayParts(photos: [], spots: spots.filter { !$0.isDraft }))
    }
}
