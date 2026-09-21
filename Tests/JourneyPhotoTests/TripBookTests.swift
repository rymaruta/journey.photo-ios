import XCTest
@testable import JourneyPhoto

/// 写真が「旅」にまとまるところ。**ここが間違うと、関係ない写真が
/// 1つの旅に紛れ込む**——一冊の意味が壊れるので、規則ごとに見張る。
final class TripBookTests: XCTestCase {

    private func photo(_ id: String, date: String?, place: String? = nil,
                       likes: Int? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\""]
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
