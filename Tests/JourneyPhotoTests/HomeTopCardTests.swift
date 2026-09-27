import XCTest
@testable import JourneyPhoto

/// ホームの上段の札（`HomeTopCard`・板 01・55）。**当たる1枚だけ**を、決めた優先順で選ぶ
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

    private func pick(plans: [TripPlan] = [], photos: [Photo] = [], opened: Set<String> = [],
                      now: Date? = nil, zone: TimeZone? = nil) -> HomeTopCard.Choice {
        HomeTopCard.pick(now: now ?? self.now, plans: plans, myPhotos: photos,
                         openedBookDays: opened, timeZone: zone ?? utc)
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

    // MARK: - 4. 1年前の今ごろ

    func testOneYearAgoWithinAWeek() throws {
        let hit = try photo("hit", date: "2025-09-30")
        XCTAssertEqual(pick(photos: [hit]), .oneYearAgo(photo: hit, byUploadDate: false))
        XCTAssertEqual(pick(photos: [try photo("edge", date: "2025-10-04")]),
                       .oneYearAgo(photo: try photo("edge", date: "2025-10-04"), byUploadDate: false))
        XCTAssertEqual(pick(photos: [try photo("miss", date: "2025-10-05")]), .theme)
    }

    func testOneYearAgoPrefersTakenDateThenCloseness() throws {
        let uploaded = try photo("up", created: "2025-09-27T10:00:00.000Z")
        let taken = try photo("taken", date: "2025-10-02")
        let closer = try photo("closer", date: "2025-09-28")
        XCTAssertEqual(pick(photos: [uploaded, taken]), .oneYearAgo(photo: taken, byUploadDate: false))
        XCTAssertEqual(pick(photos: [taken, closer]), .oneYearAgo(photo: closer, byUploadDate: false))
    }

    func testOneYearAgoSkipsDrafts() throws {
        XCTAssertEqual(pick(photos: [try photo("d", date: "2025-09-27", published: false)]), .theme)
    }

    func testOneYearAgoByUploadDateIsLabelled() throws {
        let uploaded = try photo("up", created: "2025-09-27T10:00:00.000Z")
        XCTAssertEqual(pick(photos: [uploaded]), .oneYearAgo(photo: uploaded, byUploadDate: true))
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
        XCTAssertEqual(pick(photos: [yearAgo]), .oneYearAgo(photo: yearAgo, byUploadDate: false))
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
