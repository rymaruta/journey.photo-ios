import XCTest
@testable import JourneyPhoto

/// 板 15 の1行（文言・まとめ・経過時間・未読）。
final class NotificationTextTests: XCTestCase {

    /// **鍵はサーバーと同じ `type`**（`kind` と書くと種類が nil になり、
    /// 何も確かめないテストになる）
    private func row(_ type: String, by: String? = "u1", name: String? = "Aki",
                     photo: String? = "p1", t: String = "2026-09-21T10:00:00.000Z",
                     deleted: Bool = false) throws -> AppNotification {
        var fields = ["\"type\":\"\(type)\"", "\"t\":\"\(t)\""]
        if let by { fields.append("\"byId\":\"\(by)\"") }
        if let name { fields.append("\"byName\":\"\(name)\"") }
        if let photo { fields.append("\"photoId\":\"\(photo)\"") }
        if deleted { fields.append("\"deleted\":true") }
        return try JSONDecoder.api.decode(AppNotification.self,
                                          from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var now: Date { NotificationGroups.parse("2026-09-21T12:00:00.000Z")! }

    private func single(_ notification: AppNotification) -> NotificationText.Entry {
        NotificationText.Entry(lead: notification, others: 0, unread: false)
    }

    // MARK: 文言（板の言い方）

    func testWordingFollowsTheBoard() throws {
        XCTAssertEqual(NotificationText.line(for: single(try row("like")))?.plain,
                       L("Aki があなたの写真にいいねしました", "Aki liked your photo"))
        XCTAssertEqual(NotificationText.line(for: single(try row("follow", photo: nil)))?.plain,
                       L("Aki があなたをフォローしました", "Aki followed you"))
        XCTAssertEqual(NotificationText.line(for: single(try row("comment")))?.plain,
                       L("Aki がコメントしました", "Aki commented on your photo"))
        XCTAssertEqual(NotificationText.line(for: single(try row("storyreply")))?.plain,
                       L("Aki がストーリーに返信しました", "Aki replied to your story"))
    }

    /// 名前だけ太くするので、名前と残りを分けて返す
    func testNameIsSeparated() throws {
        let line = try XCTUnwrap(NotificationText.line(for: single(try row("like"))))
        XCTAssertEqual(line.who, "Aki")
        XCTAssertFalse(line.rest.contains("Aki"))
    }

    func testGroupedLikeWording() throws {
        let entry = NotificationText.Entry(lead: try row("like"), others: 3, unread: false)
        XCTAssertEqual(NotificationText.line(for: entry)?.plain,
                       L("Aki ほか 3人 がいいねしました", "Aki and 3 others liked your photo"))
    }

    func testUnknownKindAndDeletedUser() throws {
        XCTAssertNil(NotificationText.line(for: single(try row("inspired"))))
        XCTAssertEqual(NotificationText.line(for: single(try row("like", deleted: true)))?.who,
                       Labels.Common.deletedUser)
    }

    // MARK: まとめ

    func testLikesOnTheSamePhotoCollapse() throws {
        let rows = [
            try row("like", by: "a", photo: "p1", t: "2026-09-21T11:00:00.000Z"),
            try row("comment", by: "b", photo: "p1", t: "2026-09-21T10:30:00.000Z"),
            try row("like", by: "b", photo: "p1", t: "2026-09-21T10:00:00.000Z"),
            try row("like", by: "c", photo: "p2", t: "2026-09-21T09:30:00.000Z"),
            try row("like", by: "d", photo: "p1", t: "2026-09-21T09:00:00.000Z"),
        ]
        let entries = NotificationText.collapse(rows)
        // 並びは先頭の位置のまま。コメントはまとめない
        XCTAssertEqual(entries.map(\.lead.byId), ["a", "b", "c"])
        XCTAssertEqual(entries.map(\.lead.kind), [.like, .comment, .like])
        XCTAssertEqual(entries.map(\.others), [2, 0, 0])
    }

    /// 同じ人が押し直した（外して、また押した）ぶんは「ほか」に数えない
    func testSamePersonIsCountedOnce() throws {
        let rows = [
            try row("like", by: "a", t: "2026-09-21T11:00:00.000Z"),
            try row("like", by: "a", t: "2026-09-21T10:00:00.000Z"),
        ]
        let entries = NotificationText.collapse(rows)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.others, 0)
    }

    /// 写真の id が無いいいね・フォローはまとめない
    func testRowsWithoutPhotoAreNotCollapsed() throws {
        let rows = [
            try row("follow", by: "a", photo: nil),
            try row("follow", by: "b", photo: nil),
            try row("like", by: "c", photo: ""),
            try row("like", by: "d", photo: ""),
        ]
        XCTAssertEqual(NotificationText.collapse(rows).count, 4)
    }

    // MARK: 未読

    /// サーバーの未読は「先頭から何件」
    func testUnreadIsTheHeadOfTheList() throws {
        let rows = [
            try row("like", by: "a", photo: "p1", t: "2026-09-21T11:00:00.000Z"),
            try row("follow", by: "b", photo: nil, t: "2026-09-21T10:00:00.000Z"),
            try row("like", by: "c", photo: "p2", t: "2026-09-21T09:00:00.000Z"),
        ]
        let ids = NotificationText.unreadIds(rows, unread: 2)
        XCTAssertEqual(NotificationText.collapse(rows, unreadIds: ids).map(\.unread), [true, true, false])
        XCTAssertTrue(NotificationText.unreadIds(rows, unread: 0).isEmpty)
        XCTAssertEqual(NotificationText.unreadIds(rows, unread: 99).count, 3)
    }

    /// まとめた中に未読があれば、その行は未読
    func testCollapsedEntryIsUnreadIfAnyMemberIs() throws {
        let rows = [
            try row("like", by: "a", photo: "p1", t: "2026-09-21T11:00:00.000Z"),
            try row("follow", by: "b", photo: nil, t: "2026-09-21T10:00:00.000Z"),
            try row("like", by: "c", photo: "p1", t: "2026-09-21T09:00:00.000Z"),
        ]
        let ids: Set<String> = [rows[2].id]
        XCTAssertEqual(NotificationText.collapse(rows, unreadIds: ids).map(\.unread), [true, false])
    }

    // MARK: 経過時間

    func testAgo() {
        func ago(_ t: String?) -> String? { NotificationText.ago(t, now: now, calendar: calendar) }
        XCTAssertEqual(ago("2026-09-21T10:00:00.000Z"), L("2時間前", "2h ago"))
        XCTAssertEqual(ago("2026-09-21T11:55:00Z"), L("5分前", "5m ago"))
        XCTAssertEqual(ago("2026-09-20T23:00:00.000Z"), L("昨日", "Yesterday"))
        XCTAssertEqual(ago("2026-09-18T20:00:00.000Z"), L("3日前", "3d ago"))
        XCTAssertNil(ago(nil))
        XCTAssertNil(ago("壊れた値"))
        XCTAssertNil(ago("2026-09-22T10:00:00.000Z"))   // 未来
    }
}
