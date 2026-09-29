import XCTest
@testable import JourneyPhoto

/// ホームの上段の札（`HomeTopCard`・板 01・55）。当たる札を決めた優先順で並べ、
/// そのあとに必ず「今日のテーマ」、日によってその後ろに「季節の撮影スポット」。`pick` は**先頭の1枚**（優先順を見るため）
final class HomeTopCardTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!
    /// 2026-09-27 12:00 UTC
    private let now = Date(timeIntervalSince1970: 1_790_510_400)

    private func photo(_ id: String, date: String? = nil, created: String? = nil,
                       likes: Int? = nil, place: String? = nil, published: Bool? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"", "\"userId\":\"me\""]
        if let published { fields.append("\"published\":\(published)") }
        if let date { fields.append("\"date\":\"\(date)\"") }
        if let created { fields.append("\"createdAt\":\"\(created)\"") }
        if let likes { fields.append("\"likes\":\(likes)") }
        if let place { fields.append("\"location\":\"\(place)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func plan(_ id: String, start: String?, end: String? = nil, created: String? = nil) -> TripPlan {
        TripPlan(planId: id, title: "[\(id)]", startDate: start, endDate: end, createdAt: created)
    }

    private func cards(plans: [TripPlan] = [], photos: [Photo] = [], opened: Set<String> = [],
                       now: Date? = nil, zone: TimeZone? = nil) -> [HomeTopCard.Choice] {
        HomeTopCard.cards(now: now ?? self.now, plans: plans, myPhotos: photos,
                          openedBookDays: opened, timeZone: zone ?? utc)
    }

    private func pick(plans: [TripPlan] = [], photos: [Photo] = [], opened: Set<String> = [],
                      now: Date? = nil, zone: TimeZone? = nil) -> HomeTopCard.Choice {
        cards(plans: plans, photos: photos, opened: opened, now: now, zone: zone).first ?? .theme
    }

    func testNowIsTheDayAssumed() {
        XCTAssertEqual(TripPlanText.ymd(HomeTopCard.today(now, in: utc)!), "2026-09-27")
    }

    // MARK: - 何も当たらない日

    func testNothingFallsBackToTheme() {
        XCTAssertEqual(pick(), .theme)
    }

    // MARK: - 1. 出発が近い

    func testDepartureWithinSevenDaysPicksTheNearest() {
        let near = plan("near", start: "2026-09-30")
        let far = plan("far", start: "2026-10-03")
        XCTAssertEqual(pick(plans: [far, near]), .departure(plan: near, daysUntil: 3))
        // 7日後までは出す・8日後は出さない
        XCTAssertEqual(pick(plans: [far]), .departure(plan: far, daysUntil: 6))
        XCTAssertEqual(pick(plans: [plan("p", start: "2026-10-04")]), .departure(plan: plan("p", start: "2026-10-04"), daysUntil: 7))
        XCTAssertEqual(pick(plans: [plan("p", start: "2026-10-05")]), .theme)
    }

    func testDepartureDayIsDepartureNotOnTrip() {
        let today = plan("t", start: "2026-09-27", end: "2026-09-29")
        XCTAssertEqual(pick(plans: [today]), .departure(plan: today, daysUntil: 0))
    }

    func testPlansWithoutStartOrInThePastAreNotDepartures() {
        XCTAssertEqual(pick(plans: [plan("none", start: nil), plan("past", start: "2026-09-20")]), .theme)
        // 読めない日付も当てない
        XCTAssertEqual(pick(plans: [plan("bad", start: "2026-02-30")]), .theme)
    }

    func testSameDayDeparturesAreStableByCreation() {
        let first = plan("b", start: "2026-09-29", created: "2026-09-01T00:00:00Z")
        let second = plan("a", start: "2026-09-29", created: "2026-09-02T00:00:00Z")
        XCTAssertEqual(pick(plans: [second, first]), .departure(plan: first, daysUntil: 2))
    }

    /// 🔴 **端末の時刻帯の暦日で数える。** UTC 9/26 16:00 は日本の 9/27 1:00
    func testDepartureCountsInTheDeviceTimeZone() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let lateUTC = Date(timeIntervalSince1970: 1_790_438_400) // 2026-09-26 16:00 UTC
        let p = plan("p", start: "2026-09-27")
        XCTAssertEqual(pick(plans: [p], now: lateUTC, zone: tokyo), .departure(plan: p, daysUntil: 0))
        XCTAssertEqual(pick(plans: [p], now: lateUTC, zone: utc), .departure(plan: p, daysUntil: 1))
    }

    // MARK: - 2. 旅の最中

    func testOnTripCountsDayNumberFromDeparture() {
        let trip = plan("t", start: "2026-09-25", end: "2026-09-29")
        XCTAssertEqual(pick(plans: [trip]), .onTrip(plan: trip, dayNumber: 3))
        // 帰着日の当日まで
        let lastDay = plan("l", start: "2026-09-25", end: "2026-09-27")
        XCTAssertEqual(pick(plans: [lastDay]), .onTrip(plan: lastDay, dayNumber: 3))
        // 帰着日を過ぎたら出さない
        XCTAssertEqual(pick(plans: [plan("done", start: "2026-09-20", end: "2026-09-26")]), .theme)
    }

    /// 出発当日は「旅の最中」ではなく「出発」の札（優先順に頼らず、判定そのもので縛る）
    func testOnTripStartsTheDayAfterDeparture() throws {
        let today = try XCTUnwrap(HomeTopCard.today(now, in: utc))
        XCTAssertNil(HomeTopCard.onTrip(today: today, plans: [plan("t", start: "2026-09-27", end: "2026-09-29")]))
        XCTAssertEqual(HomeTopCard.onTrip(today: today, plans: [plan("t", start: "2026-09-26", end: "2026-09-29")]),
                       .onTrip(plan: plan("t", start: "2026-09-26", end: "2026-09-29"), dayNumber: 2))
    }

    /// 帰着日の無いプランは、いつまで旅か分からないので「旅の最中」と言わない
    func testOnTripNeedsAnEndDate() {
        XCTAssertEqual(pick(plans: [plan("open", start: "2026-09-25")]), .theme)
    }

    // MARK: - 3. 一冊ができた

    private func tripPhotos(_ days: [String]) throws -> [Photo] {
        try days.enumerated().map { try photo("p\($0.offset)-\($0.element)", date: $0.element) }
    }

    func testBookReadyAfterTheTripClosesAndWhileFresh() throws {
        // 最後の写真が 9/20 → 9/24 から閉じる（3日空き）→ 9/27 は閉じて7日目までの内
        let photos = try tripPhotos(["2026-09-18", "2026-09-20"])
        guard case .bookReady(let trip) = pick(photos: photos) else { return XCTFail("一冊の札が出ない") }
        XCTAssertEqual(trip.photos.count, 2)
    }

    func testBookNotReadyWhileTheTripMayContinue() throws {
        // 最後の写真から3日以内は、まだ旅の途中かもしれない
        XCTAssertEqual(pick(photos: try tripPhotos(["2026-09-23", "2026-09-24"])), .theme)
    }

    func testBookNotShownOnceStale() throws {
        // 閉じてから7日を過ぎたら出さない（9/16 終わり → 9/27 は11日後）
        XCTAssertEqual(pick(photos: try tripPhotos(["2026-09-15", "2026-09-16"])), .theme)
        // 10日後（閉じて7日目）までは出す
        guard case .bookReady = pick(photos: try tripPhotos(["2026-09-15", "2026-09-17"])) else {
            return XCTFail("閉じて7日目の一冊が出ない")
        }
    }

    func testOpenedBookIsNotShownAgain() throws {
        let photos = try tripPhotos(["2026-09-18", "2026-09-20"])
        let trip = try XCTUnwrap(TripBook.shelfTrips(from: photos, timeZone: utc).first)
        XCTAssertEqual(pick(photos: photos, opened: [HomeTopCard.bookKey(trip)]), .theme)
    }

    /// 🔴 **開いたあとに写真を足し引きしても、同じ旅の札は出さない**
    /// （旅の id は写真の id をつないだものなので、印をそれで持つと生き返る）
    func testOpenedBookStaysOpenedWhenPhotosChange() throws {
        let photos = try tripPhotos(["2026-09-18", "2026-09-20"])
        let trip = try XCTUnwrap(TripBook.shelfTrips(from: photos, timeZone: utc).first)
        let key = HomeTopCard.bookKey(trip)
        // 撮り残しを1枚足す（旅の途中の日）・前の日の1枚を足して始まりが早まる
        let added = photos + [try photo("late", date: "2026-09-19")]
        let earlier = photos + [try photo("early", date: "2026-09-17")]
        XCTAssertEqual(pick(photos: added, opened: [key]), .theme)
        XCTAssertEqual(pick(photos: earlier, opened: [key]), .theme)
        // 別の旅の印では下げない
        XCTAssertNotEqual(pick(photos: photos, opened: ["2026-08-01"]), .theme)
    }

    /// 下書きは一冊に入れない（マイページの「旅の記録」と同じ棚）
    func testDraftsDoNotMakeABook() throws {
        let drafts = try [photo("d1", date: "2026-09-18", published: false),
                          photo("d2", date: "2026-09-20", published: false)]
        XCTAssertEqual(pick(photos: drafts), .theme)
        let mixed = try [photo("p1", date: "2026-09-18"), photo("p2", date: "2026-09-20"),
                         photo("d3", date: "2026-09-19", published: false)]
        guard case .bookReady(let trip) = pick(photos: mixed) else { return XCTFail("公開2枚の一冊が出ない") }
        XCTAssertEqual(trip.photos.map(\.id).sorted(), ["p1", "p2"])
    }

    /// 新しい旅がまだ続いているなら、その前の旅の札は出さない（いまの話ではない）。
    /// 🔴 前の旅は**それだけなら札が出る**新しさにしておく（古すぎて出ないだけの試験にしない）
    func testOnlyTheLatestTripCounts() throws {
        let older = try tripPhotos(["2026-09-15", "2026-09-18"])
        guard case .bookReady = pick(photos: older) else { return XCTFail("前の旅だけなら札が出るはず") }
        let ongoing = try [photo("n1", date: "2026-09-25"), photo("n2", date: "2026-09-26")]
        XCTAssertEqual(pick(photos: older + ongoing), .theme)
    }

    // MARK: - 7. 1年前の今ごろ（振り返りなので並びの最後）

    /// 並びの中の「1年前」の札（無ければ nil）
    private func yearAgo(_ photos: [Photo]) -> HomeTopCard.Choice? {
        cards(photos: photos).first { $0.slot == "oneYearAgo" }
    }

    func testOneYearAgoWithinAWeek() throws {
        let hit = try photo("hit", date: "2025-09-30")
        XCTAssertEqual(yearAgo([hit]), .oneYearAgo(photo: hit, byUploadDate: false))
        XCTAssertEqual(yearAgo([try photo("edge", date: "2025-10-04")]),
                       .oneYearAgo(photo: try photo("edge", date: "2025-10-04"), byUploadDate: false))
        XCTAssertNil(yearAgo([try photo("miss", date: "2025-10-05")]))
    }

    func testOneYearAgoPrefersTakenDateThenCloseness() throws {
        let uploaded = try photo("up", created: "2025-09-27T10:00:00.000Z")
        let taken = try photo("taken", date: "2025-10-02")
        let closer = try photo("closer", date: "2025-09-28")
        XCTAssertEqual(yearAgo([uploaded, taken]), .oneYearAgo(photo: taken, byUploadDate: false))
        XCTAssertEqual(yearAgo([taken, closer]), .oneYearAgo(photo: closer, byUploadDate: false))
    }

    func testOneYearAgoSkipsDrafts() throws {
        XCTAssertNil(yearAgo([try photo("d", date: "2025-09-27", published: false)]))
    }

    func testOneYearAgoByUploadDateIsLabelled() throws {
        let uploaded = try photo("up", created: "2025-09-27T10:00:00.000Z")
        XCTAssertEqual(yearAgo([uploaded]), .oneYearAgo(photo: uploaded, byUploadDate: true))
    }

    // MARK: - 優先順

    func testPriorityOrder() throws {
        let departure = plan("dep", start: "2026-09-30")
        let onTrip = plan("on", start: "2026-09-25", end: "2026-09-29")
        let book = try tripPhotos(["2026-09-18", "2026-09-20"])
        let yearAgo = try photo("y", date: "2025-09-27")

        XCTAssertEqual(pick(plans: [departure, onTrip], photos: book + [yearAgo]),
                       .departure(plan: departure, daysUntil: 3))
        XCTAssertEqual(pick(plans: [onTrip], photos: book + [yearAgo]),
                       .onTrip(plan: onTrip, dayNumber: 3))
        guard case .bookReady = pick(photos: book + [yearAgo]) else { return XCTFail("一冊が1年前より先") }
        // 1年前は振り返りなので、今日のテーマより後ろ（2026-09-29・owner）
        XCTAssertEqual(cards(photos: [yearAgo]), [.theme, .oneYearAgo(photo: yearAgo, byUploadDate: false)])
    }

    // MARK: - 並び（2026-09-28・owner「1年前の今ごろ、今日のテーマなど両方欲しい」）

    /// 当たる札は**全部**、優先順に並ぶ。今日のテーマは**必ず1枚**（季節の札が無ければ最後）
    func testAllMatchingCardsAreListedThenTheTheme() throws {
        let departure = plan("dep", start: "2026-09-30")
        let onTrip = plan("on", start: "2026-09-25", end: "2026-09-29")
        let book = try tripPhotos(["2026-09-18", "2026-09-20"])
        let yearAgo = try photo("y", date: "2025-09-27")

        let all = cards(plans: [departure, onTrip], photos: book + [yearAgo])
        XCTAssertEqual(all.count, 5, "当たった札を落とした")
        XCTAssertEqual(all[0], .departure(plan: departure, daysUntil: 3))
        XCTAssertEqual(all[1], .onTrip(plan: onTrip, dayNumber: 3))
        guard case .bookReady = all[2] else { return XCTFail("3枚目が一冊でない: \(all[2])") }
        XCTAssertEqual(all[3], .theme)
        XCTAssertEqual(all[4], .oneYearAgo(photo: yearAgo, byUploadDate: false), "1年前は最後")
        XCTAssertEqual(Set(all.map(\.slot)).count, all.count, "並びの目印が重なった（ForEach の id）")
    }

    /// 1年前と今日のテーマが**両方**出る（以前は1年前に押し出されてテーマが消えた）
    func testYearAgoAndThemeBothShow() throws {
        let yearAgo = try photo("y", date: "2025-09-27")
        XCTAssertEqual(cards(photos: [yearAgo]), [.theme, .oneYearAgo(photo: yearAgo, byUploadDate: false)])
    }

    /// 何も当たらない日は今日のテーマ1枚だけ（空き地を作らない）
    func testOnlyThemeWhenNothingMatches() {
        XCTAssertEqual(cards(), [.theme])
    }

    /// 出発の札は**7日前から**（owner「旅のカードは1週間くらいから」）
    func testDepartureShowsFromAWeekBefore() {
        XCTAssertEqual(HomeTopCard.departureWindowDays, 7)
        XCTAssertEqual(pick(plans: [plan("d7", start: "2026-10-04")]),
                       .departure(plan: plan("d7", start: "2026-10-04"), daysUntil: 7))
        XCTAssertEqual(cards(plans: [plan("d8", start: "2026-10-05")]), [.theme], "8日前から出した")
    }

    // MARK: - 6. この季節の撮影スポット

    /// 索引の1行。`seasons` は `[(季節, 文)]`
    private func spot(_ id: String, stage: String = "published", image: Bool = true,
                      seasons: [(String, String)] = [("autumn", "秋は紅葉")]) throws -> OfficialSpot {
        var fields = ["\"spotId\":\"\(id)\"", "\"slug\":\"\(id)\"", "\"name\":\"[\(id)]\"", "\"stage\":\"\(stage)\""]
        if image {
            fields.append("\"image\":{\"url\":\"https://journey-photo.com/images/spots/\(id).jpg\",\"author\":\"A\",\"license\":\"CC BY 4.0\"}")
        }
        if !seasons.isEmpty {
            let list = seasons.map { "{\"season\":\"\($0.0)\",\"text\":\"\($0.1)\"}" }.joined(separator: ",")
            fields.append("\"seasonalGuide\":[\(list)]")
        }
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// 季節の札（並びの中の `inSeason`）。並びの位置に頼らない
    private func inSeasonCard(_ cards: [HomeTopCard.Choice]) -> HomeTopCard.Choice? {
        cards.first { $0.slot == "inSeason" }
    }

    private func seasonCards(_ spots: [OfficialSpot], now: Date? = nil,
                             photos: [Photo] = []) -> [HomeTopCard.Choice] {
        HomeTopCard.cards(now: now ?? self.now, plans: [], myPhotos: photos,
                          openedBookDays: [], spots: spots, timeZone: utc)
    }

    /// 9/27 は秋。**秋の案内を持つ・写真のある・公開済み**の行だけが候補
    func testInSeasonPicksOnlyPublishedSpotsWithPhotoAndThisSeason() throws {
        let ok = try spot("sp_ok")
        let draft = try spot("sp_draft", stage: "review")
        let noImage = try spot("sp_noimage", image: false)
        let spring = try spot("sp_spring", seasons: [("spring", "春は桜")])
        let noGuide = try spot("sp_noguide", seasons: [])
        XCTAssertEqual(seasonCards([draft, noImage, spring, noGuide, ok]),
                       [.inSeason(spot: ok, season: "autumn", guide: "秋は紅葉"), .theme])
        // 当たる行が無ければ札を出さない（空き地を作らない）
        XCTAssertEqual(seasonCards([draft, noImage, spring, noGuide]), [.theme])
        XCTAssertEqual(seasonCards([]), [.theme])
    }

    /// 同じ日は何度開いても同じ・翌日は次の1件（`spotId` の順・紀元からの日数で進む）
    func testInSeasonRotatesDaily() throws {
        let a = try spot("sp_a", seasons: [("autumn", "Aの秋")])
        let b = try spot("sp_b", seasons: [("autumn", "Bの秋")])
        // 2026-09-27 は紀元から 20723 日目 → 20723 % 2 = 1 → 2件目
        XCTAssertEqual(inSeasonCard(seasonCards([b, a])), .inSeason(spot: b, season: "autumn", guide: "Bの秋"))
        XCTAssertEqual(inSeasonCard(seasonCards([a, b])), .inSeason(spot: b, season: "autumn", guide: "Bの秋"), "並び順で変わっている")
        let later = now.addingTimeInterval(11 * 3600) // 同じ日の 23:00
        XCTAssertEqual(inSeasonCard(seasonCards([a, b], now: later)), .inSeason(spot: b, season: "autumn", guide: "Bの秋"))
        let next = now.addingTimeInterval(86_400)
        XCTAssertEqual(inSeasonCard(seasonCards([a, b], now: next)), .inSeason(spot: a, season: "autumn", guide: "Aの秋"))
    }

    /// 季節は**端末の暦の月**で決める。12/1 は冬（UTC では 11/30 でも、東京の 12/1 なら冬）
    func testInSeasonUsesLocalMonth() throws {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let s = try spot("sp_s", seasons: [("autumn", "秋の文"), ("winter", "冬の文")])
        // 2026-11-30 16:00 UTC = 2026-12-01 01:00 JST
        let dec1 = Date(timeIntervalSince1970: 1_796_054_400)
        XCTAssertEqual(inSeasonCard(HomeTopCard.cards(now: dec1, plans: [], myPhotos: [], openedBookDays: [],
                                                      spots: [s], timeZone: tokyo)),
                       .inSeason(spot: s, season: "winter", guide: "冬の文"))
        XCTAssertEqual(inSeasonCard(HomeTopCard.cards(now: dec1, plans: [], myPhotos: [], openedBookDays: [],
                                                      spots: [s], timeZone: utc)),
                       .inSeason(spot: s, season: "autumn", guide: "秋の文"))
    }

    /// 並びは 季節（今月の見ごろ）→ 今日のテーマ → 1年前（owner・2026-09-29）
    func testInSeasonComesBeforeTheme() throws {
        let s = try spot("sp_s")
        let old = try photo("old", date: "2025-09-27")
        XCTAssertEqual(seasonCards([s], photos: [old]).map(\.slot), ["inSeason", "theme", "oneYearAgo"])
        XCTAssertEqual(seasonCards([s]).map(\.slot), ["inSeason", "theme"])
    }

    // MARK: - 5. 行きたい場所のこの季節

    private func wishCards(_ spots: [OfficialSpot], wishlist: Set<String>,
                           photos: [Photo] = []) -> [HomeTopCard.Choice] {
        HomeTopCard.cards(now: now, plans: [], myPhotos: photos, openedBookDays: [],
                          spots: spots, wishlist: wishlist, timeZone: utc)
    }

    /// 「行きたい」に入れた公開済みのスポットで、いまの季節の案内があるものだけ。写真は無くてもよい
    func testWishlistSeasonPicksOnlyWishedPublishedSpots() throws {
        let wished = try spot("sp_w", image: false, seasons: [("autumn", "秋の文")])
        let notWished = try spot("sp_n")
        let draft = try spot("sp_d", stage: "review")
        let spring = try spot("sp_s", seasons: [("spring", "春の文")])
        let keys: Set<String> = ["SPOT-sp_w", "SPOT-sp_d", "SPOT-sp_s"]
        let all = wishCards([wished, notWished, draft, spring], wishlist: keys)
        XCTAssertEqual(all.first { $0.slot == "wishlistSeason" },
                       .wishlistSeason(spot: wished, season: "autumn", guide: "秋の文"))
        // 撮影地の鍵（SPOT- の無い slug）では当てない
        XCTAssertNil(wishCards([wished], wishlist: ["sp_w"]).first { $0.slot == "wishlistSeason" })
        XCTAssertNil(wishCards([wished], wishlist: []).first { $0.slot == "wishlistSeason" })
    }

    /// 並びは 行きたい場所 → 季節 → テーマ → 1年前。**季節の札は同じスポットを出さない**
    func testWishlistSeasonOrderAndNoDuplicateWithSeason() throws {
        let only = try spot("sp_only")
        let old = try photo("old", date: "2025-09-27")
        XCTAssertEqual(wishCards([only], wishlist: ["SPOT-sp_only"], photos: [old]).map(\.slot),
                       ["wishlistSeason", "theme", "oneYearAgo"], "同じスポットが季節の札にも出た")
        let other = try spot("sp_other")
        XCTAssertEqual(wishCards([only, other], wishlist: ["SPOT-sp_only"]).map(\.slot),
                       ["wishlistSeason", "inSeason", "theme"])
        XCTAssertEqual(inSeasonCard(wishCards([only, other], wishlist: ["SPOT-sp_only"])),
                       .inSeason(spot: other, season: "autumn", guide: "秋は紅葉"))
    }

    /// 見出しは季節の名前（「見頃」とは言わない）
    func testSeasonEyebrowNamesTheSeason() {
        XCTAssertEqual(HomeTopCard.seasonEyebrow("autumn"), L("秋の撮影スポット", "Autumn photo spot"))
        XCTAssertEqual(HomeTopCard.seasonEyebrow("monsoon"), L("この季節の撮影スポット", "Photo spot for this season"))
    }

    /// 索引の季節の案内は**行ごとは落とさない**。壊れた項目・知らない季節・空の文だけ落とす
    func testSeasonalGuideDecodesLeniently() throws {
        let json = """
        {"spotId":"sp_x","slug":"x","name":"X","stage":"published",
         "seasonalGuide":[{"season":"autumn","text":"秋"},{"season":"monsoon","text":"雨季"},
                          {"season":"winter","text":"  "},{"season":1},{"season":"spring","text":"春"}]}
        """
        let x = try JSONDecoder.api.decode(OfficialSpot.self, from: Data(json.utf8))
        XCTAssertEqual(x.seasons.map(\.season), ["autumn", "spring"])
        // 欄が壊れていても行は読める・欄が無い古い索引も読める
        let broken = try JSONDecoder.api.decode(OfficialSpot.self, from: Data(
            #"{"spotId":"sp_y","slug":"y","name":"Y","stage":"published","seasonalGuide":"oops"}"#.utf8))
        XCTAssertEqual(broken.seasons, [])
        let old = try JSONDecoder.api.decode(OfficialSpot.self, from: Data(
            #"{"spotId":"sp_z","slug":"z","name":"Z","stage":"published"}"#.utf8))
        XCTAssertNil(old.seasonalGuide)
        XCTAssertEqual(old.seasons, [])
    }
}

/// 札から開いた一冊の印（`OpenedTripBooks`）
final class OpenedTripBooksTests: XCTestCase {

    func testMarksArePerPersonAndBounded() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = OpenedTripBooks(defaults: defaults)
        store.mark("2026-09-18", for: "a")
        XCTAssertEqual(store.ids(for: "a"), ["2026-09-18"])
        XCTAssertTrue(store.ids(for: "b").isEmpty, "別の人の印で札を下げない")
        XCTAssertTrue(store.ids(for: nil).isEmpty)
        store.mark("x", for: nil)   // 未ログインは覚えない
        XCTAssertTrue(store.ids(for: nil).isEmpty)
        for i in 0..<(OpenedTripBooks.limit + 5) { store.mark("k\(i)", for: "a") }
        XCTAssertEqual(store.ids(for: "a").count, OpenedTripBooks.limit, "増え続けない")
        XCTAssertTrue(store.ids(for: "a").contains("k\(OpenedTripBooks.limit + 4)"), "新しい印は残る")
    }
}
