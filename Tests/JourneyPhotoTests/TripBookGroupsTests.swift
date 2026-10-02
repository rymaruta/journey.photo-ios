import XCTest
@testable import JourneyPhoto

/// 1つの投稿にまとめた束（`groupId`）を旅の記録の一冊にする（`TripBook.groupTrips`・`shelfTrips`）。
/// 旅の写真からまとめて上げた写真は非公開で始まるので、下書きを落とすだけだと棚に出なかった
final class TripBookGroupsTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!

    private func photo(_ id: String, date: String?, group: String? = nil, published: Bool? = nil,
                       place: String? = nil, user: String = "owner") throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"", "\"userId\":\"\(user)\""]
        if let date { fields.append("\"date\":\"\(date)\"") }
        if let group { fields.append("\"groupId\":\"\(group)\"") }
        if let published { fields.append("\"published\":\(published)") }
        if let place { fields.append("\"location\":\"\(place)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// 束は一冊になる（非公開を含む）。題・期間・印
    func testGroupBecomesOneBookEvenWhenPrivate() throws {
        let photos = [
            try photo("a", date: "2026-09-12", group: "g1", published: false, place: "京都市"),
            try photo("b", date: "2026-09-14", group: "g1", published: false, place: "京都市"),
            try photo("c", date: "2026-09-13", group: "g1", published: false, place: "大阪市"),
        ]
        let shelf = TripBook.shelfTrips(from: photos, timeZone: utc)
        XCTAssertEqual(shelf.count, 1, "非公開の束が旅の記録に出ない")
        let book = try XCTUnwrap(shelf.first)
        XCTAssertEqual(book.id, "group#g1")
        XCTAssertEqual(book.groupId, "g1")
        XCTAssertTrue(book.isPrivate, "非公開の束に「自分だけ」の印が無い")
        XCTAssertEqual(book.place, "京都市")
        XCTAssertEqual(book.photos.map(\.id), ["a", "c", "b"], "旅の進む向きに並んでいない")
        XCTAssertEqual(TripPlanText.ymd(book.start), "2026-09-12")
        XCTAssertEqual(TripPlanText.ymd(book.end), "2026-09-14")
    }

    /// 公開だけの束は「自分だけ」ではない
    func testPublicGroupIsNotPrivate() throws {
        let photos = [
            try photo("a", date: "2026-09-12", group: "g1", published: true),
            try photo("b", date: "2026-09-13", group: "g1"),
        ]
        XCTAssertEqual(TripBook.shelfTrips(from: photos, timeZone: utc).first?.isPrivate, false)
    }

    /// 束の写真は日付の束に入らない（同じ写真を2冊に数えない）
    func testGroupPhotosAreNotInDateTrips() throws {
        let photos = [
            try photo("g-a", date: "2026-09-12", group: "g1", published: true),
            try photo("g-b", date: "2026-09-13", group: "g1", published: true),
            try photo("p-a", date: "2026-09-13"),
            try photo("p-b", date: "2026-09-14"),
        ]
        let shelf = TripBook.shelfTrips(from: photos, timeZone: utc)
        XCTAssertEqual(shelf.count, 2)
        let all = shelf.flatMap { $0.photos.map(\.id) }
        XCTAssertEqual(all.count, Set(all).count, "束の写真を日付の一冊にも数えた")
        XCTAssertEqual(Set(shelf.first { $0.groupId == nil }?.photos.map(\.id) ?? []), ["p-a", "p-b"])
    }

    /// 1枚の束は一冊にしない（公開ならその1枚は日付の束に入る）
    func testSinglePhotoGroupIsNotABook() throws {
        let photos = [
            try photo("g-a", date: "2026-09-12", group: "g1", published: true),
            try photo("p-a", date: "2026-09-13"),
        ]
        let shelf = TripBook.shelfTrips(from: photos, timeZone: utc)
        XCTAssertNil(shelf.first { $0.groupId != nil }, "1枚の束を一冊にした")
        XCTAssertEqual(shelf.first?.photos.map(\.id), ["g-a", "p-a"], "1枚の束の写真が日付の束から落ちた")
        XCTAssertTrue(TripBook.groupTrips(from: [try photo("x", date: "2026-09-12", group: "g9", published: false)]).isEmpty)
    }

    /// 公開写真の日付の束は今までどおり（下書きは入れない）
    func testDateTripsUnchanged() throws {
        let photos = [
            try photo("a", date: "2026-05-01"),
            try photo("b", date: "2026-05-02"),
            try photo("draft", date: "2026-05-02", published: false),
        ]
        let shelf = TripBook.shelfTrips(from: photos, timeZone: utc)
        XCTAssertEqual(shelf.count, 1)
        XCTAssertEqual(shelf.first?.photos.map(\.id), ["a", "b"], "束でない下書きが一冊に入った")
        XCTAssertNil(shelf.first?.groupId)
        XCTAssertEqual(shelf.first?.isPrivate, false)
    }

    /// 並びは期間の新しい順（束と日付の束を混ぜて）
    func testShelfIsNewestFirst() throws {
        let photos = [
            try photo("old-a", date: "2025-01-01"), try photo("old-b", date: "2025-01-02"),
            try photo("g-a", date: "2026-09-12", group: "g1", published: false),
            try photo("g-b", date: "2026-09-13", group: "g1", published: false),
            try photo("mid-a", date: "2026-03-01"), try photo("mid-b", date: "2026-03-02"),
        ]
        XCTAssertEqual(TripBook.shelfTrips(from: photos, timeZone: utc).map { $0.photos.first?.id },
                       ["g-a", "mid-a", "old-a"])
    }

    /// 束の一冊を開いた印は、同じ日々の日付の一冊を下げない（鍵が重ならない）
    func testOpenedKeysOfGroupAndDateBooksDoNotOverlap() throws {
        let photos = [
            try photo("g-a", date: "2026-09-12", group: "g1", published: false),
            try photo("g-b", date: "2026-09-13", group: "g1", published: false),
            try photo("p-a", date: "2026-09-12"),
            try photo("p-b", date: "2026-09-13"),
        ]
        let shelf = TripBook.shelfTrips(from: photos, timeZone: utc)
        let group = try XCTUnwrap(shelf.first { $0.groupId != nil })
        let dated = try XCTUnwrap(shelf.first { $0.groupId == nil })
        XCTAssertEqual(HomeTopCard.bookKey(group), "group#g1")
        XCTAssertTrue(HomeTopCard.isOpened(group, openedBookDays: [HomeTopCard.bookKey(group)]))
        XCTAssertFalse(HomeTopCard.isOpened(dated, openedBookDays: [HomeTopCard.bookKey(group)]),
                       "束の一冊を開いただけで日付の一冊の札が下がる")
        XCTAssertFalse(HomeTopCard.isOpened(group, openedBookDays: [HomeTopCard.bookKey(dated)]),
                       "日付の一冊を開いただけで束の一冊の札が下がる")
    }
}
