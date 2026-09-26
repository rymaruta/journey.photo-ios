import XCTest
@testable import JourneyPhoto

/// 写真が「旅」にまとまるところ。**ここが間違うと、関係ない写真が
/// 1つの旅に紛れ込む**——一冊の意味が壊れるので、規則ごとに見張る。
final class TripBookTests: XCTestCase {

    /// **投稿者を必ず入れる。** 旅は1人のものなので、身元の分からない
    /// 写真は束ねない規則（`TripOwnershipTests`）。実データの写真は
    /// 全部 `userId` を持っている（30/30）
    private func photo(_ id: String, date: String?, place: String? = nil,
                       likes: Int? = nil, user: String = "owner") throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"",
                      "\"userId\":\"\(user)\""]
        if let date { fields.append("\"date\":\"\(date)\"") }
        if let place { fields.append("\"location\":\"\(place)\"") }
        if let likes { fields.append("\"likes\":\(likes)") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// 連続した日は1つの旅
    func testConsecutiveDaysBecomeOneTrip() throws {
        let trips = TripBook.trips(from: [
            try photo("a", date: "2026-05-01"),
            try photo("b", date: "2026-05-02"),
            try photo("c", date: "2026-05-03"),
        ])
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips.first?.photos.map(\.id), ["a", "b", "c"], "旅の進む向き（古い順）で並ぶ")
        XCTAssertEqual(trips.first?.days, 3)
    }

    /// **中日に撮らなくてもつながる**（移動日に1枚も撮らないのはよくある）
    func testAGapOfThreeDaysStillOneTrip() throws {
        let trips = TripBook.trips(from: [
            try photo("a", date: "2026-05-01"),
            try photo("b", date: "2026-05-04"),
        ])
        XCTAssertEqual(trips.count, 1, "3日空いても同じ旅")
    }

    /// 離れすぎていれば別の旅
    func testAWeekApartIsAnotherTrip() throws {
        let trips = TripBook.trips(from: [
            try photo("a", date: "2026-05-01"),
            try photo("b", date: "2026-05-02"),
            try photo("c", date: "2026-05-20"),
            try photo("d", date: "2026-05-21"),
        ])
        XCTAssertEqual(trips.count, 2)
        XCTAssertEqual(trips.first?.photos.map(\.id), ["c", "d"], "新しい旅が先頭")
    }

    /// **1枚は旅ではない**（ただのその日の写真）
    func testASinglePhotoIsNotATrip() throws {
        XCTAssertTrue(TripBook.trips(from: [try photo("a", date: "2026-05-01")]).isEmpty)
    }

    /// **場所では切らない。** 金沢へ行って帰りに福井へ寄った、は1つの旅。
    /// 切ると「移動そのもの」が消える
    func testDifferentPlacesInTheSameDaysStayOneTrip() throws {
        let trips = TripBook.trips(from: [
            try photo("a", date: "2026-05-01", place: "金沢"),
            try photo("b", date: "2026-05-02", place: "金沢"),
            try photo("c", date: "2026-05-03", place: "福井"),
        ])
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips.first?.place, "金沢", "いちばん多い撮影地が題")
    }

    /// 日付を持たない写真は混ぜない（いつの旅か決まらない）
    func testUndatedPhotosAreLeftOut() throws {
        let trips = TripBook.trips(from: [
            try photo("a", date: "2026-05-01"),
            try photo("b", date: "2026-05-02"),
            try photo("none", date: nil),
        ])
        XCTAssertEqual(trips.first?.photos.map(\.id), ["a", "b"])
    }

    /// 表紙は**いいねがいちばん多い1枚**
    func testCoverIsTheMostLikedPhoto() throws {
        let trips = TripBook.trips(from: [
            try photo("a", date: "2026-05-01", likes: 1),
            try photo("b", date: "2026-05-02", likes: 9),
        ])
        XCTAssertEqual(trips.first?.cover?.id, "b")
    }

    /// 同じ日だけの旅は「1日」
    func testSameDayTripIsOneDay() throws {
        let trips = TripBook.trips(from: [
            try photo("a", date: "2026-05-01"),
            try photo("b", date: "2026-05-01"),
        ])
        XCTAssertEqual(trips.first?.days, 1)
    }
}

/// 足取り（ルート図の点）の出し方。
final class TripRouteTests: XCTestCase {

    private func photo(_ id: String, place: String?, date: String = "2026-05-01") throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"",
                      "\"userId\":\"owner\"", "\"date\":\"\(date)\""]
        if let place { fields.append("\"location\":\"\(place)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func trip(_ photos: [Photo]) throws -> TripBook.Trip {
        try XCTUnwrap(TripBook.trips(from: photos).first)
    }

    private func places(_ photos: [Photo]) throws -> [String] {
        TripBook.routeStops(of: try trip(photos)).map(\.place)
    }

    /// **同じ場所が続いたらまとめる**（「金沢・金沢・福井」→「金沢・福井」）
    func testCollapsesRepeatedPlaces() throws {
        XCTAssertEqual(try places([
            try photo("a", place: "金沢"),
            try photo("b", place: "金沢"),
            try photo("c", place: "福井"),
        ]), ["金沢", "福井"])
    }

    /// **1か所しか無い旅では出さない。** 点が1つあるだけの「足取り」は
    /// かえって壊れて見える（実機の絵で見つけた）
    func testASinglePlaceIsNotARoute() throws {
        XCTAssertTrue(try places([try photo("a", place: "三条市, 日本"),
                                  try photo("b", place: "三条市, 日本")]).isEmpty)
    }

    /// 撮影地が1枚も無ければ空
    func testNoPlacesMeansNoRoute() throws {
        XCTAssertTrue(try places([try photo("a", place: nil), try photo("b", place: nil)]).isEmpty)
    }

    /// 離れた場所へ戻ってきた場合は、戻りも1歩として残す
    func testGoingBackIsPartOfTheRoute() throws {
        XCTAssertEqual(try places([
            try photo("a", place: "金沢"),
            try photo("b", place: "福井"),
            try photo("c", place: "金沢"),
        ]), ["金沢", "福井", "金沢"])
    }

    /// 点には**その場所に着いた日**が付く（板「DAY 3 · 福井」）
    func testStopsCarryTheDayTheyWereReached() throws {
        let stops = TripBook.routeStops(of: try trip([
            try photo("a", place: "金沢", date: "2026-09-12"),
            try photo("b", place: "金沢", date: "2026-09-13"),
            try photo("c", place: "福井", date: "2026-09-14"),
        ]))
        XCTAssertEqual(stops, [TripBook.RouteStop(day: 1, place: "金沢"),
                               TripBook.RouteStop(day: 3, place: "福井")])
    }

    /// 図に載せきれないときは間引く。**最初と最後は必ず残す**
    func testSamplingKeepsTheEnds() {
        let stops = (1...7).map { TripBook.RouteStop(day: $0, place: "P\($0)") }
        let sampled = TripBook.sampledStops(stops, limit: 4)
        XCTAssertEqual(sampled.count, 4)
        XCTAssertEqual(sampled.first?.place, "P1")
        XCTAssertEqual(sampled.last?.place, "P7")
        XCTAssertEqual(TripBook.sampledStops(Array(stops.prefix(3)), limit: 4).count, 3, "少なければそのまま")
    }
}

/// 旅の一冊・背表紙に出す文字と数（板 03・16）。
final class TripBookFactsTests: XCTestCase {

    private func photo(_ id: String, date: String? = nil, created: String? = nil,
                       place: String? = nil, lat: Double? = nil, lng: Double? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"",
                      "\"userId\":\"owner\""]
        if let date { fields.append("\"date\":\"\(date)\"") }
        if let created { fields.append("\"createdAt\":\"\(created)\"") }
        if let place { fields.append("\"location\":\"\(place)\"") }
        if let lat, let lng { fields.append("\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func utc(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: text + "T00:00:00Z")!
    }

    // MARK: 期間の範囲

    /// 板の「2026.09.12 — 09.14」
    func testRangeWithinAYear() {
        XCTAssertEqual(TripBook.dateRange(from: utc("2026-09-12"), to: utc("2026-09-14")),
                       "2026.09.12 — 09.14")
    }

    /// 同じ日は1つだけ
    func testRangeOfOneDay() {
        XCTAssertEqual(TripBook.dateRange(from: utc("2026-09-12"), to: utc("2026-09-12")), "2026.09.12")
    }

    /// **年をまたいだら終わりにも年**（「— 01.02」ではどの年か読めない）
    func testRangeAcrossYears() {
        XCTAssertEqual(TripBook.dateRange(from: utc("2025-12-30"), to: utc("2026-01-02")),
                       "2025.12.30 — 2026.01.02")
    }

    /// 日の段の日付
    func testMonthDay() {
        XCTAssertEqual(TripBook.monthDay(utc("2026-09-03")), "09.03")
    }

    /// **暦の日で数える。** 投稿日で代用した写真は時刻を持つので、経過秒で
    /// 割ると 5/1 20:00 → 5/3 08:00 が「2日間」になり、範囲（05.01 — 05.03）と食い違う
    func testDaysCountCalendarDaysNotElapsedTime() throws {
        let trip = try XCTUnwrap(TripBook.trips(from: [
            try photo("a", created: "2026-05-01T20:00:00.000Z"),
            try photo("b", created: "2026-05-03T08:00:00.000Z"),
        ]).first)
        XCTAssertEqual(trip.days, 3)
        XCTAssertEqual(TripBook.dateRange(from: trip.start, to: trip.end), "2026.05.01 — 05.03")
    }

    // MARK: 題

    /// 板「金沢の旅」。撮影地があれば題の中に入る
    func testTitleUsesThePlace() throws {
        let trip = try XCTUnwrap(TripBook.trips(from: [
            try photo("a", date: "2026-09-12", place: "金沢"),
            try photo("b", date: "2026-09-13", place: "金沢"),
        ]).first)
        let title = TripBook.title(of: trip)
        XCTAssertTrue(title.contains("金沢"))
        XCTAssertNotEqual(title, "金沢", "撮影地だけを題にしている（板は「金沢の旅」）")
    }

    // MARK: 数

    /// 撮影地は**名前の異なり**で数える（空白の違い・空は数えない）
    func testPlaceCount() throws {
        let photos = [
            try photo("a", place: "金沢"), try photo("b", place: " 金沢 "),
            try photo("c", place: "福井"), try photo("d", place: ""), try photo("e"),
        ]
        XCTAssertEqual(TripBook.placeCount(of: photos), 2)
    }

    /// 直線距離は座標のある写真だけをつなぐ（無い写真は飛ばす）
    func testDistanceSkipsPhotosWithoutCoords() throws {
        let photos = [
            try photo("a", date: "2026-09-12", lat: 36.56, lng: 136.65),   // 金沢
            try photo("b", date: "2026-09-13"),                            // 座標なし
            try photo("c", date: "2026-09-14", lat: 36.06, lng: 136.22),   // 福井
        ]
        let km = try XCTUnwrap(TravelDistance.countableTotal(of: photos))
        XCTAssertEqual(km, 67, accuracy: 3)
    }

    /// **数えられないときは「—」。** 0 km（同じ場所で2枚）とは分ける
    func testDistanceIsUnknownWithFewerThanTwoPoints() throws {
        let one = [try photo("a", date: "2026-09-12", lat: 36.56, lng: 136.65),
                   try photo("b", date: "2026-09-13")]
        XCTAssertNil(TravelDistance.countableTotal(of: one))
        XCTAssertEqual(TripBook.distanceText(nil), "—")

        let same = [try photo("a", date: "2026-09-12", lat: 36.56, lng: 136.65),
                    try photo("b", date: "2026-09-13", lat: 36.56, lng: 136.65)]
        XCTAssertEqual(TravelDistance.countableTotal(of: same), 0)
        XCTAssertEqual(TripBook.distanceText(0), "0")
    }

    // MARK: 日ごとの段

    /// 撮った日ごとに段を作る。**撮っていない日は段を作らない**（DAY 2 が抜ける）
    func testDaysGroupPhotosAndSkipEmptyDays() throws {
        let trip = try XCTUnwrap(TripBook.trips(from: [
            try photo("a", date: "2026-09-12", place: "金沢"),
            try photo("b", date: "2026-09-12", place: "金沢"),
            try photo("c", date: "2026-09-14", place: "福井"),
        ]).first)
        let days = TripBook.days(of: trip)
        XCTAssertEqual(days.map(\.number), [1, 3])
        XCTAssertEqual(days.map { $0.photos.map(\.id) }, [["a", "b"], ["c"]])
        XCTAssertEqual(days.map(\.place), ["金沢", "福井"])
        XCTAssertEqual(days.map { TripBook.monthDay($0.date) }, ["09.12", "09.14"])
    }

    // MARK: 共有

    /// 共有の文は題と期間。**URL を入れない**（旅の一冊にはサイトのページが無い）
    func testShareTextHasTitleAndPeriodButNoLink() throws {
        let trip = try XCTUnwrap(TripBook.trips(from: [
            try photo("a", date: "2026-09-12", place: "金沢"),
            try photo("b", date: "2026-09-14", place: "金沢"),
        ]).first)
        let text = TripBook.shareText(of: trip)
        XCTAssertTrue(text.hasPrefix(TripBook.title(of: trip)))
        XCTAssertTrue(text.contains("2026.09.12 — 09.14"))
        XCTAssertFalse(text.contains("http"))
    }
}

/// **旅は1人のもの。**
///
/// 公開一覧は全員の写真が入っているので、日付だけで束ねると
/// **同じ日に別の人が撮った写真が1つの旅に混ざる**。人が増えた瞬間に起きる。
final class TripOwnershipTests: XCTestCase {

    private func photo(_ id: String, user: String?, date: String) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"",
                      "\"date\":\"\(date)\""]
        if let user { fields.append("\"userId\":\"\(user)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    func testPhotosFromDifferentPeopleAreDifferentTrips() throws {
        let trips = TripBook.trips(from: [
            try photo("a1", user: "A", date: "2026-05-01"),
            try photo("b1", user: "B", date: "2026-05-01"),
            try photo("a2", user: "A", date: "2026-05-02"),
            try photo("b2", user: "B", date: "2026-05-02"),
        ])
        XCTAssertEqual(trips.count, 2, "別の人の写真が1つの旅に混ざっている")
        for trip in trips {
            let owners = Set(trip.photos.compactMap(\.userId))
            XCTAssertEqual(owners.count, 1, "1つの旅に2人ぶんの写真が入っている")
        }
    }

    /// **投稿者が分からない写真どうしを束ねない。** 空を鍵にすると、
    /// 身元の分からない写真が「同じ人の旅」になる
    func testUnknownOwnersDoNotFormATrip() throws {
        let trips = TripBook.trips(from: [
            try photo("x", user: nil, date: "2026-05-01"),
            try photo("y", user: nil, date: "2026-05-02"),
        ])
        XCTAssertTrue(trips.isEmpty)
    }
}
