import XCTest
@testable import JourneyPhoto

/// 写真から行き先を選ぶ（`TripPicker`）。
///
/// 固定したいのは:
///  1. 札は**公開済み・写真あり**だけ。もう「行きたい」に入れた場所は出さない。並びは種で決まる
///  2. 地域（国・都道府県）で束ね、**近い順**に回る
///  3. 日への割り振りは**回る順を変えず**、日数とサーバーの上限に合わせる。場所を落とさない
final class TripPickerTests: XCTestCase {

    /// 索引の1行
    private func spot(_ slug: String, stage: String = "published", image: Bool = true,
                      prefecture: String? = nil, country: String? = nil,
                      lat: Double? = nil, lng: Double? = nil,
                      seasons: [(String, String)] = []) throws -> OfficialSpot {
        var fields = ["\"spotId\":\"sp_\(slug)\"", "\"slug\":\"\(slug)\"", "\"name\":\"[\(slug)]\"", "\"stage\":\"\(stage)\""]
        if image {
            fields.append("\"image\":{\"url\":\"https://journey-photo.com/images/spots/\(slug).jpg\",\"author\":\"A\",\"license\":\"CC BY 4.0\"}")
        }
        var region: [String] = []
        if let prefecture { region.append("\"prefecture\":\"\(prefecture)\"") }
        if let country { region.append("\"country\":\"\(country)\"") }
        if !region.isEmpty { fields.append("\"region\":{\(region.joined(separator: ","))}") }
        if let lat, let lng { fields.append("\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}") }
        if !seasons.isEmpty {
            let list = seasons.map { "{\"season\":\"\($0.0)\",\"text\":\"\($0.1)\"}" }.joined(separator: ",")
            fields.append("\"seasonalGuide\":[\(list)]")
        }
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func slugs(_ spots: [OfficialSpot]) -> [String] { spots.map(\.slug) }
    private func slugs(_ days: [[OfficialSpot]]) -> [[String]] { days.map { $0.map(\.slug) } }

    // 実在の場所に近い座標（約1km に丸めた形）
    private func kyoto(_ slug: String, lat: Double = 35.00, lng: Double = 135.77) throws -> OfficialSpot {
        try spot(slug, prefecture: "京都府", lat: lat, lng: lng)
    }
    private func nara(_ slug: String, lat: Double = 34.68, lng: Double = 135.80) throws -> OfficialSpot {
        try spot(slug, prefecture: "奈良県", lat: lat, lng: lng)
    }
    private func hokkaido(_ slug: String, lat: Double = 43.06, lng: Double = 141.35) throws -> OfficialSpot {
        try spot(slug, prefecture: "北海道", lat: lat, lng: lng)
    }

    // MARK: - 1. 札の山

    func testDeckHasOnlyPublishedSpotsWithPhotoNotYetWanted() throws {
        let ok = try spot("ok")
        let draft = try spot("draft", stage: "review")
        let noImage = try spot("noimage", image: false)
        let wanted = try spot("wanted")
        let deck = TripPicker.deck(from: [draft, noImage, wanted, ok],
                                   excluding: [SavedSpotKey.official("wanted")], seed: 1)
        XCTAssertEqual(slugs(deck), ["ok"])
    }

    /// 撮影地の鍵（頭の無い slug）は撮影スポットを隠さない（`SavedSpotKey` の約束）
    func testLocationKeyWithSameSpellingDoesNotHideSpot() throws {
        let deck = TripPicker.deck(from: [try spot("kyoto")], excluding: ["kyoto"], seed: 1)
        XCTAssertEqual(slugs(deck), ["kyoto"])
    }

    func testDeckIsDeterministicForSeedAndIgnoresIndexOrder() throws {
        let spots = try (0..<20).map { try spot("s\($0)") }
        let a = TripPicker.deck(from: spots, excluding: [], seed: 42)
        let b = TripPicker.deck(from: spots.reversed(), excluding: [], seed: 42)
        XCTAssertEqual(slugs(a), slugs(b))
        XCTAssertEqual(Set(slugs(a)), Set(spots.map(\.slug)))
        // 混ざっている（索引の並びのまま＝順位のように見せない）
        XCTAssertNotEqual(slugs(a), slugs(spots.sorted { $0.spotId < $1.spotId }))
        // 種が違えば並びも違う
        XCTAssertNotEqual(slugs(a), slugs(TripPicker.deck(from: spots, excluding: [], seed: 43)))
    }

    func testDeckDropsDuplicateSlugs() throws {
        let a = try spot("same")
        let b = try JSONDecoder.api.decode(OfficialSpot.self, from: Data("""
        {"spotId":"sp_other","slug":"same","name":"別の行","stage":"published",
         "image":{"url":"https://journey-photo.com/x.jpg","author":"A","license":"CC BY 4.0"}}
        """.utf8))
        XCTAssertEqual(TripPicker.deck(from: [a, b], excluding: [], seed: 1).count, 1)
    }

    func testSeasonHintOnlyForCurrentSeason() throws {
        let utc = TimeZone(identifier: "UTC")!
        // 2026-10-01 は秋
        let now = Date(timeIntervalSince1970: 1_790_812_800)
        let autumn = try spot("a", seasons: [("spring", "春は桜"), ("autumn", "秋は紅葉")])
        let spring = try spot("b", seasons: [("spring", "春は桜")])
        XCTAssertEqual(TripPicker.seasonHint(autumn, now: now, timeZone: utc)?.text, "秋は紅葉")
        XCTAssertEqual(TripPicker.seasonHint(autumn, now: now, timeZone: utc)?.label, L("秋", "Autumn"))
        XCTAssertNil(TripPicker.seasonHint(spring, now: now, timeZone: utc))
    }

    // MARK: - 2. 地域で束ねる

    func testRegionIsCountryAbroadAndPrefectureInJapan() throws {
        XCTAssertEqual(TripPicker.region(of: try spot("paris", prefecture: "イル＝ド＝フランス", country: "フランス")).label, "フランス")
        XCTAssertEqual(TripPicker.region(of: try kyoto("k")).label, "京都府")
        XCTAssertNil(TripPicker.region(of: try spot("none")).label)
        // 国と県で同じ名前でも別の地域
        XCTAssertNotEqual(TripPicker.region(of: try spot("x", country: "A")),
                          TripPicker.region(of: try spot("y", prefecture: "A")))
    }

    /// 選んだ順がばらばらでも、同じ地域は続けて回る
    func testGroupsKeepRegionsTogether() throws {
        let k1 = try kyoto("k1"), n1 = try nara("n1"), k2 = try kyoto("k2", lat: 35.01), n2 = try nara("n2", lat: 34.60)
        let groups = TripPicker.grouped([k1, n1, k2, n2])
        XCTAssertEqual(slugs(groups), [["k1", "k2"], ["n1", "n2"]])
    }

    /// 次の地域は**いまいる場所にいちばん近い**地域（選んだ順ではない）
    func testNextRegionIsTheNearestOne() throws {
        let k = try kyoto("k"), h = try hokkaido("h"), n = try nara("n")
        // 京都 → (北海道を先に選んでいても) 奈良 → 北海道
        XCTAssertEqual(slugs(TripPicker.grouped([k, h, n])), [["k"], ["n"], ["h"]])
    }

    /// 地域の中は近い順（最初に選んだ場所から、いちばん近い未訪の場所へ）
    func testInsideRegionFollowsNearestNeighbour() throws {
        let a = try kyoto("a", lat: 35.00)
        let far = try kyoto("far", lat: 35.30)
        let near = try kyoto("near", lat: 35.02)
        XCTAssertEqual(slugs(TripPicker.grouped([a, far, near])), [["a", "near", "far"]])
    }

    /// 次の地域は、前の地域の最後にいちばん近い場所から始める
    func testNextRegionStartsNearWhereWeAre() throws {
        let k = try kyoto("k", lat: 35.00)
        let nFar = try nara("nfar", lat: 34.30)
        let nNear = try nara("nnear", lat: 34.70)
        XCTAssertEqual(slugs(TripPicker.grouped([k, nFar, nNear])), [["k"], ["nnear", "nfar"]])
    }

    /// 座標の無い場所・地域も落とさない（地域の最後・全体の最後に、選んだ順で）
    func testSpotsWithoutCoordsAreKept() throws {
        let k = try kyoto("k")
        let kNoCoords = try spot("k0", prefecture: "京都府")
        let none = try spot("none")
        let n = try nara("n")
        let groups = TripPicker.grouped([kNoCoords, none, k, n])
        XCTAssertEqual(slugs(groups), [["k", "k0"], ["n"], ["none"]])
    }

    func testGroupedDropsRepeatedPicks() throws {
        let k = try kyoto("k")
        XCTAssertEqual(slugs(TripPicker.grouped([k, k])), [["k"]])
        XCTAssertEqual(TripPicker.grouped([]).count, 0)
    }

    // MARK: - 3. 日へ割り振る

    private func line(_ prefix: String, _ n: Int) throws -> [OfficialSpot] {
        try (0..<n).map { try kyoto("\(prefix)\($0)", lat: 35.0 + Double($0) * 0.01) }
    }

    /// 日付が無いときは、地域ごとに4か所前後で均す（地域を1日に混ぜない）
    func testDaysWithoutDatesSplitEachRegionByAboutFour() throws {
        let k = try line("k", 5)
        let n = [try nara("n0")]
        let days = TripPicker.days([k, n], dayCount: nil)
        XCTAssertEqual(days.map(\.count), [3, 2, 1])
        XCTAssertEqual(slugs(days.flatMap { $0 }), slugs(k + n))
    }

    /// 日数が少ないとき: 地域を混ぜる日を最も少なく（混ぜずに済むなら混ぜない）
    func testFewerDaysAvoidMixingRegions() throws {
        // 京都 5・奈良 1 → 2日: 京都 5 / 奈良 1（3・3 にすると奈良の日に京都が混ざる）
        let k = try line("k", 5)
        let n = [try nara("n0")]
        XCTAssertEqual(TripPicker.days([k, n], dayCount: 2).map(\.count), [5, 1])

        // 京都 6・奈良 3 → 2日: 京都 6 / 奈良 3。並びが逆でも同じ（違う地域どうしをまとめない）
        let k6 = try line("k", 6)
        let n3 = try (0..<3).map { try nara("n\($0)", lat: 34.6 + Double($0) * 0.01) }
        XCTAssertEqual(TripPicker.days([k6, n3], dayCount: 2).map(\.count), [6, 3])
        let reversed = TripPicker.days([n3, k6], dayCount: 2)
        XCTAssertEqual(reversed.map(\.count), [3, 6])
        XCTAssertEqual(slugs(reversed[0]), slugs(n3))
    }

    /// 混ぜるしかないときは、いちばん多い日を最も少なく（1日20か所まで）
    func testFewerDaysBalanceWhenMixingIsUnavoidable() throws {
        let k = try line("k", 30)
        let n = [try nara("n0")]
        let days = TripPicker.days([k, n], dayCount: 2)
        XCTAssertEqual(days.map(\.count), [16, 15])
        XCTAssertEqual(slugs(days.flatMap { $0 }), slugs(k + n))
    }

    /// 1日が詰まりすぎるなら、地域を混ぜてでも均す（混ぜない「20・10・10」にしない）
    func testCrowdedDaysAreBalancedEvenIfRegionsMix() throws {
        let k = try line("k", 20)
        let n = try (0..<20).map { try nara("n\($0)", lat: 34.6 - Double($0) * 0.01) }
        let days = TripPicker.days([k, n], dayCount: 3)
        XCTAssertEqual(days.map(\.count), [14, 13, 13])
        XCTAssertEqual(slugs(days.flatMap { $0 }), slugs(k + n))
    }

    /// 均した数が目安を越えても、少しの偏りで混ぜずに済むなら混ぜない
    func testSlightImbalanceIsAllowedToKeepRegionsApart() throws {
        let k10 = try line("k", 10)
        let n17 = try (0..<17).map { try nara("n\($0)", lat: 34.6 - Double($0) * 0.01) }
        XCTAssertEqual(TripPicker.days([k10, n17], dayCount: 3).map(\.count), [10, 9, 8])
        let k9 = try line("k", 9)
        let n7 = Array(n17.prefix(7))
        XCTAssertEqual(TripPicker.days([k9, n7], dayCount: 2).map(\.count), [9, 7])
    }

    /// 詰まる日程では、混ぜる日を減らすために小さい日を作り過ぎない（「10・10・2」「14・14・7」にしない）
    func testCrowdedPackingDoesNotLeaveTinyDays() throws {
        func regions(_ counts: [Int]) throws -> [[OfficialSpot]] {
            try counts.enumerated().map { r, count in
                try (0..<count).map { i in
                    try spot("g\(r)-\(i)", prefecture: "県\(r)", lat: 35 + Double(r) * 0.5 + Double(i) * 0.01, lng: 135)
                }
            }
        }
        for (counts, dayCount) in [([10, 10, 2], 3), ([7, 7, 7, 7, 7], 3), ([10, 10, 10, 1], 4), ([10, 10, 4], 3)] {
            let groups = try regions(counts)
            let days = TripPicker.days(groups, dayCount: dayCount)
            let n = counts.reduce(0, +)
            XCTAssertEqual(days.count, dayCount)
            XCTAssertGreaterThanOrEqual(days.map(\.count).min() ?? 0, n / dayCount - TripPicker.placesPerDay / 2, "\(counts)")
            XCTAssertEqual(slugs(days.flatMap { $0 }), slugs(groups.flatMap { $0 }))
        }
    }

    /// どんな数でも、決めた日数ちょうど・1日20か所まで・場所を落とさない・並びを変えない
    func testAnyCountFitsRequestedDaysWithinServerLimits() throws {
        let pool = try (0..<TripPicker.pickMax).map { i in
            try spot("r\(i)", prefecture: ["京都府", "奈良県", "大阪府"][i % 3], lat: 34.5 + Double(i) * 0.01, lng: 135.5)
        }
        for n in [1, 2, 5, 9, 17, 23, 40] {
            let groups = TripPicker.grouped(Array(pool.prefix(n)))
            let flat = groups.flatMap { $0 }
            for dayCount in [1, 2, 3, 7, 60, 61] {
                let days = TripPicker.days(groups, dayCount: dayCount)
                let expected = max(min(dayCount, TripPlanService.daysMax),
                                   (n + TripPlanService.itemsPerDayMax - 1) / TripPlanService.itemsPerDayMax)
                XCTAssertEqual(days.count, expected, "n=\(n) days=\(dayCount)")
                XCTAssertTrue(days.allSatisfy { $0.count <= TripPlanService.itemsPerDayMax })
                XCTAssertEqual(slugs(days.flatMap { $0 }), slugs(flat), "n=\(n) days=\(dayCount)")
            }
        }
    }

    /// 地域の無い場所が地域のある場所の間に挟まっても落とさない
    func testUnplacedBetweenRegionsIsKept() throws {
        let k = try kyoto("k"), u = try spot("u", lat: 34.85, lng: 135.78), n = try nara("n")
        let groups = TripPicker.grouped([k, u, n])
        XCTAssertEqual(slugs(groups), [["k"], ["u"], ["n"]])
        XCTAssertEqual(slugs(TripPicker.days(groups, dayCount: 2).flatMap { $0 }), ["k", "u", "n"])
    }

    /// 地域の無い場所は、日に割るときは続いた並びとして均す（1か所ずつ1日にしない・混ぜると数えない）
    func testUnplacedSpotsAreSpreadLikeOneRegion() throws {
        let spots = try (0..<10).map { try spot("u\($0)", lat: 35 + Double($0) * 0.01, lng: 135) }
        let groups = TripPicker.grouped(spots)
        XCTAssertEqual(TripPicker.days(groups, dayCount: nil).map(\.count), [4, 3, 3])
        XCTAssertEqual(TripPicker.days(groups, dayCount: 3).map(\.count), [4, 3, 3])
        let forty = try (0..<40).map { try spot("v\($0)", lat: 35 + Double($0) * 0.01, lng: 135) }
        XCTAssertEqual(TripPicker.days(TripPicker.grouped(forty), dayCount: 5).map(\.count), [8, 8, 8, 8, 8])
    }

    /// 0以下の日数は「日数が無い」と同じ（60日の上限を素通りさせない）
    func testNonPositiveDayCountIsLikeNoDates() throws {
        let spots = try (0..<70).map { try spot("p\($0)", prefecture: "県\($0)", lat: 35, lng: 135 + Double($0) * 0.1) }
        let groups = TripPicker.grouped(spots)
        XCTAssertEqual(TripPicker.days(groups, dayCount: 0).count, TripPlanService.daysMax)
        XCTAssertEqual(TripPicker.days(groups, dayCount: -3).count, TripPlanService.daysMax)
        XCTAssertEqual(TripPicker.days([], dayCount: 0).count, 0)
        XCTAssertEqual(TripPicker.days([], dayCount: 2), [[], []])
    }

    /// 収まる日程は必ず収める（貪欲にまとめると 40か所/2日 が「16・16・8」の3日になっていた）
    func testPacksIntoTheRequestedDaysWhenItFits() throws {
        let k = try line("k", 40)
        let days = TripPicker.days([k], dayCount: 2)
        XCTAssertEqual(days.map(\.count), [20, 20])
        XCTAssertEqual(slugs(days.flatMap { $0 }), slugs(k))
    }

    /// 日数が多いとき: いちばん多い日を切る。それでも余れば空の日
    func testMoreDaysSplitTheBusiestDayThenAddEmptyDays() throws {
        let k = try line("k", 3)
        let days = TripPicker.days([k], dayCount: 5)
        XCTAssertEqual(days.map(\.count), [1, 1, 1, 0, 0])
        XCTAssertEqual(slugs(days.flatMap { $0 }), slugs(k))
    }

    /// 1日の上限（20）を越えてまとめない。まとめ切れなければ日数を越えたまま（場所を落とさない）
    func testNeverExceedsItemsPerDayAndNeverDropsPlaces() throws {
        let k = try line("k", 30)
        let days = TripPicker.days([k], dayCount: 1)
        XCTAssertTrue(days.allSatisfy { $0.count <= TripPlanService.itemsPerDayMax })
        XCTAssertEqual(days.flatMap { $0 }.count, 30)
        XCTAssertEqual(slugs(days.flatMap { $0 }), slugs(k))
    }

    /// 選べる上限いっぱいでも、日付が無いときの日数はサーバーの上限に収まる
    func testPickMaxFitsServerLimits() throws {
        // 地域がばらばら（1か所ずつ）でも 1日1か所で pickMax 日
        let spots = try (0..<TripPicker.pickMax).map { try spot("p\($0)", prefecture: "県\($0)", lat: 35, lng: 135 + Double($0) * 0.1) }
        let days = TripPicker.days(TripPicker.grouped(spots), dayCount: nil)
        XCTAssertLessThanOrEqual(days.count, TripPlanService.daysMax)
        XCTAssertEqual(days.flatMap { $0 }.count, TripPicker.pickMax)
    }

    /// 🔴 日付が無くても60日を越えない（サーバーは越えた日を**黙って切り捨てる**）
    func testNeverMoreThanDaysMaxWithoutDates() throws {
        let spots = try (0..<70).map { try spot("p\($0)", prefecture: "県\($0)", lat: 35, lng: 135 + Double($0) * 0.1) }
        let days = TripPicker.days(TripPicker.grouped(spots), dayCount: nil)
        XCTAssertEqual(days.count, TripPlanService.daysMax)
        XCTAssertTrue(days.allSatisfy { !$0.isEmpty && $0.count <= TripPlanService.itemsPerDayMax })
        XCTAssertEqual(days.flatMap { $0 }.count, 70)
    }

    /// 地域の無い場所どうしを「同じ地域」にしない（遠い2か所を同じ日にまとめない）
    func testSpotsWithoutRegionAreNotOneRegion() throws {
        let a = try spot("a", lat: 35.0, lng: 135.7)
        let b = try spot("b", lat: 48.86, lng: 2.35)
        XCTAssertNotEqual(TripPicker.region(of: a), TripPicker.region(of: b))
        XCTAssertEqual(slugs(TripPicker.grouped([a, b])), [["a"], ["b"]])
    }

    func testDayCountFromDates() {
        XCTAssertEqual(TripPicker.dayCount(start: "2026-11-03", end: "2026-11-05"), 3)
        XCTAssertEqual(TripPicker.dayCount(start: "2026-11-03", end: "2026-11-03"), 1)
        XCTAssertNil(TripPicker.dayCount(start: "2026-11-05", end: "2026-11-03"))
        XCTAssertNil(TripPicker.dayCount(start: "2026-11-03", end: nil))
        XCTAssertNil(TripPicker.dayCount(start: "2026-02-30", end: "2026-03-02"))
        XCTAssertEqual(TripPicker.dayCount(start: "2026-01-01", end: "2026-12-31"), TripPlanService.daysMax)
    }

    func testTripDaysUseLedgerKeysWithoutDates() throws {
        let days = TripPicker.tripDays([[try kyoto("k")], []])
        XCTAssertEqual(days, [TripDay(items: [.spot(spotId: "sp_k", note: nil)]), TripDay()])
    }

    func testTitleAndDayRegionLabel() throws {
        let k = try kyoto("k"), n = try nara("n"), h = try hokkaido("h")
        XCTAssertEqual(TripPicker.defaultTitle([[k], [n]]), L("京都府・奈良県の旅", "Trip to 京都府, 奈良県"))
        XCTAssertEqual(TripPicker.defaultTitle([[k], [n], [h]]), L("京都府・奈良県ほかの旅", "Trip to 京都府, 奈良県 and more"))
        XCTAssertEqual(TripPicker.defaultTitle([[try spot("x")]]), L("行きたい場所の旅", "Places I want to go"))
        XCTAssertEqual(TripPicker.regionLabel(of: [k, n, k]), "京都府・奈良県")
        XCTAssertNil(TripPicker.regionLabel(of: [try spot("x")]))
    }
}
