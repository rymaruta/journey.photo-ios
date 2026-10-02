import XCTest
@testable import JourneyPhoto

/// 1つの投稿にまとめた束（`groupId`）を旅の記録の一冊にする（`TripBook.groupTrips`・`shelfTrips`）。
/// 旅の写真からまとめて上げた写真は非公開で始まるので、下書きを落とすだけだと棚に出なかった
final class TripBookGroupsTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!

    private func photo(_ id: String, date: String?, group: String? = nil, published: Bool? = nil,
                       place: String? = nil, user: String = "owner", created: String? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"", "\"userId\":\"\(user)\""]
        if let created { fields.append("\"createdAt\":\"\(created)\"") }
        if let date { fields.append("\"date\":\"\(date)\"") }
        if let group { fields.append("\"groupId\":\"\(group)\"") }
        if let published { fields.append("\"published\":\(published)") }
        if let place { fields.append("\"location\":\"\(place)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// 束は一冊になる（非公開を含む）。題・期間・印
    func testGroupBecomesOneBookEvenWhenPrivate() throws {
        let photos = [
            try photo("a", date: "2026-09-12", group: "trip-g1", published: false, place: "京都市"),
            try photo("b", date: "2026-09-14", group: "trip-g1", published: false, place: "京都市"),
            try photo("c", date: "2026-09-13", group: "trip-g1", published: false, place: "大阪市"),
        ]
        let shelf = TripBook.shelfTrips(from: photos, timeZone: utc)
        XCTAssertEqual(shelf.count, 1, "非公開の束が旅の記録に出ない")
        let book = try XCTUnwrap(shelf.first)
        XCTAssertEqual(book.id, "group#trip-g1")
        XCTAssertEqual(book.groupId, "trip-g1")
        XCTAssertTrue(book.isPrivate, "非公開の束に「自分だけ」の印が無い")
        XCTAssertEqual(book.place, "京都市")
        XCTAssertEqual(book.photos.map(\.id), ["a", "c", "b"], "旅の進む向きに並んでいない")
        XCTAssertEqual(TripPlanText.ymd(book.start), "2026-09-12")
        XCTAssertEqual(TripPlanText.ymd(book.end), "2026-09-14")
    }

    /// 公開だけの束は「自分だけ」ではない
    func testPublicGroupIsNotPrivate() throws {
        let photos = [
            try photo("a", date: "2026-09-12", group: "trip-g1", published: true),
            try photo("b", date: "2026-09-13", group: "trip-g1"),
        ]
        XCTAssertEqual(TripBook.shelfTrips(from: photos, timeZone: utc).first?.isPrivate, false)
    }

    /// 束の写真は日付の束に入らない（同じ写真を2冊に数えない）
    func testGroupPhotosAreNotInDateTrips() throws {
        let photos = [
            try photo("g-a", date: "2026-09-12", group: "trip-g1", published: true),
            try photo("g-b", date: "2026-09-13", group: "trip-g1", published: true),
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
            try photo("g-a", date: "2026-09-12", group: "trip-g1", published: true),
            try photo("p-a", date: "2026-09-13"),
        ]
        let shelf = TripBook.shelfTrips(from: photos, timeZone: utc)
        XCTAssertNil(shelf.first { $0.groupId != nil }, "1枚の束を一冊にした")
        XCTAssertEqual(shelf.first?.photos.map(\.id), ["g-a", "p-a"], "1枚の束の写真が日付の束から落ちた")
        XCTAssertTrue(TripBook.groupTrips(from: [try photo("x", date: "2026-09-12", group: "trip-g9", published: false)]).isEmpty)
    }

    /// 撮影日の幅が30日を超える束は一冊にしない。公開写真は日付の束に戻る（2026-10-02 判断）
    func testGroupLongerThanThirtyDaysIsNotABook() throws {
        let photos = [
            try photo("paris-a", date: "2026-01-10", group: "trip-g1", published: true),
            try photo("paris-b", date: "2026-01-11", group: "trip-g1", published: true),
            try photo("hokkaido-a", date: "2026-02-12", group: "trip-g1", published: true),
            try photo("hokkaido-b", date: "2026-02-13", group: "trip-g1", published: true),
        ]
        let shelf = TripBook.shelfTrips(from: photos, timeZone: utc)
        XCTAssertNil(shelf.first { $0.groupId != nil }, "何か月にまたがる束を一冊にした")
        XCTAssertEqual(shelf.map { $0.photos.map(\.id) }, [["hokkaido-a", "hokkaido-b"], ["paris-a", "paris-b"]],
                       "一冊にしなかった束の公開写真が日付の束に戻っていない")
        // ちょうど30日は一冊
        let edge = [
            try photo("a", date: "2026-01-01", group: "trip-g2", published: false),
            try photo("b", date: "2026-01-31", group: "trip-g2", published: false),
        ]
        XCTAssertEqual(TripBook.groupTrips(from: edge, timeZone: utc).count, 1, "30日の束を落とした")
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
            try photo("g-a", date: "2026-09-12", group: "trip-g1", published: false),
            try photo("g-b", date: "2026-09-13", group: "trip-g1", published: false),
            try photo("mid-a", date: "2026-03-01"), try photo("mid-b", date: "2026-03-02"),
        ]
        XCTAssertEqual(TripBook.shelfTrips(from: photos, timeZone: utc).map { $0.photos.first?.id },
                       ["g-a", "mid-a", "old-a"])
    }

    /// 束の一冊を開いた印は、同じ日々の日付の一冊を下げない（鍵が重ならない）
    func testOpenedKeysOfGroupAndDateBooksDoNotOverlap() throws {
        let photos = [
            try photo("g-a", date: "2026-09-12", group: "trip-g1", published: false),
            try photo("g-b", date: "2026-09-13", group: "trip-g1", published: false),
            try photo("p-a", date: "2026-09-12"),
            try photo("p-b", date: "2026-09-13"),
        ]
        let shelf = TripBook.shelfTrips(from: photos, timeZone: utc)
        let group = try XCTUnwrap(shelf.first { $0.groupId != nil })
        let dated = try XCTUnwrap(shelf.first { $0.groupId == nil })
        XCTAssertEqual(HomeTopCard.bookKey(group), "group#trip-g1")
        XCTAssertTrue(HomeTopCard.isOpened(group, openedBookDays: [HomeTopCard.bookKey(group)]))
        XCTAssertFalse(HomeTopCard.isOpened(dated, openedBookDays: [HomeTopCard.bookKey(group)]),
                       "束の一冊を開いただけで日付の一冊の札が下がる")
        XCTAssertFalse(HomeTopCard.isOpened(group, openedBookDays: [HomeTopCard.bookKey(dated)]),
                       "日付の一冊を開いただけで束の一冊の札が下がる")
    }

    // MARK: - 旅の写真の流れの束だけ（2026-10-02 判断）

    /// 🔴 レビューの再現: ふだんの「1つの投稿にまとめる」（頭に trip- の無い束）は一冊にしない。
    /// main と同じく日付の一冊が1冊で、開いた印は始まりの日（2026-08-01）
    func testOrdinaryGroupStaysInDateBook() throws {
        let ordinary = "0D5C2F4E-1111-2222-3333-444455556666"
        let photos = [
            try photo("d1", date: "2026-08-01"),
            try photo("g1", date: "2026-08-02", group: ordinary),
            try photo("g2", date: "2026-08-02", group: ordinary),
            try photo("g3", date: "2026-08-03", group: ordinary),
            try photo("d5", date: "2026-08-06"),
            try photo("d6", date: "2026-08-07"),
        ]
        let shelf = TripBook.shelfTrips(from: photos, timeZone: utc)
        XCTAssertEqual(shelf.count, 1, "ふだんのまとめ投稿で日付の一冊が割れた")
        let book = try XCTUnwrap(shelf.first)
        XCTAssertNil(book.groupId)
        XCTAssertEqual(book.photos.map(\.id), ["d1", "g1", "g2", "g3", "d5", "d6"])
        XCTAssertEqual(HomeTopCard.bookKey(book), "2026-08-01")
        XCTAssertTrue(HomeTopCard.isOpened(book, openedBookDays: ["2026-08-01"]), "前に開いた印が外れた")
    }

    /// 撮影日の無い写真だけの束は一冊にしない（投稿日で数えない）
    func testGroupWithoutTakenDaysIsNotABook() throws {
        let photos = [
            try photo("a", date: nil, group: "trip-g1", published: false, created: "2026-09-12T01:00:00Z"),
            try photo("b", date: nil, group: "trip-g1", published: false, created: "2026-09-12T02:00:00Z"),
            try photo("c", date: nil, group: "trip-g1", published: false, created: "2026-09-12T03:00:00Z"),
        ]
        XCTAssertTrue(TripBook.shelfTrips(from: photos, timeZone: utc).isEmpty, "撮影日の無い束を一冊にした")
    }

    /// 撮影日のある写真と無い写真が混ざった束は、撮影日のある写真だけで一冊（幅も撮影日だけで数える）
    func testMixedGroupUsesOnlyTakenDays() throws {
        let photos = [
            try photo("a", date: "2026-08-01", group: "trip-g1", published: false),
            try photo("b", date: "2026-08-03", group: "trip-g1", published: false),
            // 4か月後に上げた——投稿日で数えると30日を超えて一冊が消える・期間が延びる
            try photo("c", date: nil, group: "trip-g1", published: false, created: "2026-12-01T01:00:00Z"),
        ]
        let book = try XCTUnwrap(TripBook.groupTrips(from: photos, timeZone: utc).first)
        XCTAssertEqual(book.photos.map(\.id), ["a", "b"])
        XCTAssertEqual(TripPlanText.ymd(book.end), "2026-08-03", "撮影日の無い写真の投稿日を期間に数えた")
    }

    /// 31日（1/01〜2/01）の束は一冊にしない
    func testThirtyOneDayGroupIsNotABook() throws {
        let photos = [
            try photo("a", date: "2026-01-01", group: "trip-g1", published: false),
            try photo("b", date: "2026-02-01", group: "trip-g1", published: false),
        ]
        XCTAssertTrue(TripBook.groupTrips(from: photos, timeZone: utc).isEmpty, "31日の束を一冊にした")
    }

    /// 自分だけの一冊は共有しない（表紙に非公開の写真が載って外へ出る）
    func testPrivateBookIsNotShared() throws {
        let photos = [
            try photo("a", date: "2026-09-12", group: "trip-g1", published: false),
            try photo("b", date: "2026-09-13", group: "trip-g1", published: true),
            try photo("p1", date: "2025-01-01"), try photo("p2", date: "2025-01-02"),
        ]
        let shelf = TripBook.shelfTrips(from: photos, timeZone: utc)
        XCTAssertFalse(TripBook.canShare(try XCTUnwrap(shelf.first { $0.isPrivate })), "自分だけの一冊を共有できる")
        XCTAssertTrue(TripBook.canShare(try XCTUnwrap(shelf.first { $0.groupId == nil })))
    }

    /// ホームの札: 日付の一冊の途中に束の一冊があっても、旅の最中に「閉じた」と言わない
    func testBookReadyLooksAtTheLatestEnd() throws {
        var photos: [Photo] = []
        for day in 1...20 { photos.append(try photo("d\(day)", date: String(format: "2026-08-%02d", day))) }
        photos += [
            try photo("g-a", date: "2026-08-05", group: "trip-g1", published: false),
            try photo("g-b", date: "2026-08-07", group: "trip-g1", published: false),
        ]
        let today = try XCTUnwrap(TripPlanText.date(fromYMD: "2026-08-12"))
        XCTAssertNil(HomeTopCard.bookReady(today: today, myPhotos: photos, openedBookDays: [], timeZone: utc),
                     "旅の最中（8/20 まで撮っている）に束の一冊を「閉じた」と言った")
        let after = try XCTUnwrap(TripPlanText.date(fromYMD: "2026-08-25"))
        guard case .bookReady(let trip)? = HomeTopCard.bookReady(today: after, myPhotos: photos,
                                                                 openedBookDays: [], timeZone: utc) else {
            return XCTFail("旅が閉じたのに札が出ない")
        }
        XCTAssertNil(trip.groupId, "終わりの遅い日付の一冊を出していない")
    }

    // MARK: - 束の印の頭

    func testTripPrefixOnlyFromTheTripFlow() {
        let trip = UploadGrouping.newGroupId(fromTrip: true, uuid: "0D5C2F4E-1111-2222-3333-444455556666")
        XCTAssertTrue(trip.hasPrefix("trip-"))
        XCTAssertLessThanOrEqual(trip.count, 64, "サーバーの sanitizeGroupId（64字まで）で落ちる")
        XCTAssertNotNil(trip.range(of: "^[A-Za-z0-9-]+$", options: .regularExpression), "英数字とハイフン以外が入った")
        XCTAssertTrue(UploadGrouping.isTripGroup(trip))
        let ordinary = UploadGrouping.newGroupId(fromTrip: false)
        XCTAssertFalse(UploadGrouping.isTripGroup(ordinary), "ふだんのまとめ投稿に trip- が付いた")
        XCTAssertFalse(UploadGrouping.isTripGroup(nil))
    }
}
