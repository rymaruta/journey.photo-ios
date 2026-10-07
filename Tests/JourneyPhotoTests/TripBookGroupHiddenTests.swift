import XCTest
@testable import JourneyPhoto

/// 束の一冊（`groupId`）で写真を非公開にしても、一冊の中から消えない（2026-10-07）。
///
/// 非公開にした印（`goneMarks`・7日）で一冊の中だけ落ち、棚の枚数（束は非公開も数える）と
/// ずれていた。束の一冊は**消した**写真とブロック・通報だけで落とす
final class TripBookGroupHiddenTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!

    private func photo(_ id: String, date: String, group: String? = nil, published: Bool? = nil,
                       user: String = "owner") throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"", "\"userId\":\"\(user)\"",
                      "\"date\":\"\(date)\""]
        if let group { fields.append("\"groupId\":\"\(group)\"") }
        if let published { fields.append("\"published\":\(published)") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func groupBook() throws -> TripBook.Trip {
        let photos = [
            try photo("a", date: "2026-09-12", group: "trip-g1", published: false),
            try photo("b", date: "2026-09-13", group: "trip-g1", published: true),
            try photo("c", date: "2026-09-14", group: "trip-g1", published: true),
        ]
        let book = try XCTUnwrap(TripBook.shelfTrips(from: photos, timeZone: utc).first)
        XCTAssertNotNil(book.groupId)
        return book
    }

    /// 非公開にした（印は付くが消してはいない）写真は、束の一冊に残る＝棚の枚数と同じ
    func testPrivatizedPhotoStaysInGroupBook() throws {
        let book = try groupBook()
        let shown = TripBookView.visible(book, dropped: ModerationSnapshot(gone: ["b"]))
        XCTAssertEqual(shown.photos.map(\.id), ["a", "b", "c"], "非公開にした写真が束の一冊から消えた")
        XCTAssertEqual(shown.photos.count, book.photos.count, "棚の枚数とずれる")
    }

    /// 消した写真・通報した写真・ブロックした人の写真は、束の一冊からも落ちる
    func testDeletedReportedAndBlockedLeaveGroupBook() throws {
        let book = try groupBook()
        XCTAssertEqual(TripBookView.visible(book, dropped: ModerationSnapshot(gone: ["a", "b"], deleted: ["a"]))
            .photos.map(\.id), ["b", "c"], "消した写真（非公開のものも）が束の一冊に残った")
        XCTAssertEqual(TripBookView.visible(book, dropped: ModerationSnapshot(reported: ["c"])).photos.map(\.id),
                       ["a", "b"])
        XCTAssertTrue(TripBookView.visible(book, dropped: ModerationSnapshot(blocked: ["owner"])).photos.isEmpty)
    }

    /// 日付で束ねた一冊（公開写真だけ）は今までどおり、非公開にした写真を落とす
    func testDateBookStillDropsPrivatized() throws {
        let book = try XCTUnwrap(TripBook.shelfTrips(from: [
            try photo("x", date: "2026-05-01"), try photo("y", date: "2026-05-02"),
        ], timeZone: utc).first)
        XCTAssertNil(book.groupId)
        XCTAssertEqual(TripBookView.visible(book, dropped: ModerationSnapshot(gone: ["x"])).photos.map(\.id), ["y"])
    }

    /// 印は「消した」と「非公開にした」に分かれる。消した印は人が替わったら持ち越さない
    @MainActor
    func testStoreSeparatesDeletedFromPrivatized() async {
        let store = ModerationStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.use(userId: "me")
        store.markGone("a", for: "me")
        store.markGone("b", for: "me", deleted: true)
        XCTAssertEqual(store.snapshot.gone, ["a", "b"])
        XCTAssertEqual(store.snapshot.deleted, ["b"])
        store.use(userId: "other")
        XCTAssertTrue(store.snapshot.deleted.isEmpty, "前の人の消した印を持ち越した")
    }

    /// 写真詳細の「削除」は消した印で付ける（非公開にする編集は付けない）
    func testDeletePathMarksDeleted() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        let detail = try String(contentsOf: root.appendingPathComponent("Features/PhotoDetail/PhotoDetailView.swift"),
                                encoding: .utf8)
        XCTAssertTrue(detail.contains("hideGone(photoId, for: owner, environment: environment, deleted: true)"),
                      "削除で消した印を付けていない")
        let edit = try String(contentsOf: root.appendingPathComponent("Features/Profile/EditPhotoView.swift"),
                              encoding: .utf8)
        XCTAssertFalse(edit.contains("deleted: true"), "非公開にする編集で消した印を付けた")
    }
}
