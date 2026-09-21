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

/// 足取り（たどった場所）の出し方。
final class TripRouteTests: XCTestCase {

    private func photo(_ id: String, place: String?) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"",
                      "\"userId\":\"owner\""]
        if let place { fields.append("\"location\":\"\(place)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// **同じ場所が続いたらまとめる**（「金沢・金沢・福井」→「金沢・福井」）
    func testCollapsesRepeatedPlaces() throws {
        let photos = [
            try photo("a", place: "金沢"),
            try photo("b", place: "金沢"),
            try photo("c", place: "福井"),
        ]
        XCTAssertEqual(TripBook.route(of: photos), ["金沢", "福井"])
    }

    /// **1か所しか無い旅では出さない。** 点が1つあるだけの「足取り」は
    /// かえって壊れて見える（実機の絵で見つけた）
    func testASinglePlaceIsNotARoute() throws {
        let photos = [try photo("a", place: "三条市, 日本"), try photo("b", place: "三条市, 日本")]
        XCTAssertTrue(TripBook.route(of: photos).isEmpty)
    }

    /// 撮影地が1枚も無ければ空
    func testNoPlacesMeansNoRoute() throws {
        XCTAssertTrue(TripBook.route(of: [try photo("a", place: nil)]).isEmpty)
    }

    /// 離れた場所へ戻ってきた場合は、戻りも1歩として残す
    func testGoingBackIsPartOfTheRoute() throws {
        let photos = [
            try photo("a", place: "金沢"),
            try photo("b", place: "福井"),
            try photo("c", place: "金沢"),
        ]
        XCTAssertEqual(TripBook.route(of: photos), ["金沢", "福井", "金沢"])
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
