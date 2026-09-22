import XCTest
@testable import JourneyPhoto

final class NotificationGroupsTests: XCTestCase {

    private func row(_ t: String?) throws -> AppNotification {
        let time = t.map { "\"t\":\"\($0)\"," } ?? ""
        return try JSONDecoder.api.decode(AppNotification.self, from: Data(
            "{\(time)\"kind\":\"like\",\"byId\":\"u1\",\"photoId\":\"p1\"}".utf8))
    }

    private var now: Date {
        NotificationGroups.parse("2026-09-21T12:00:00.000Z")!
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testReadsBothISOShapes() {
        XCTAssertNotNil(NotificationGroups.parse("2026-09-21T12:00:00.000Z"))
        XCTAssertNotNil(NotificationGroups.parse("2026-09-21T12:00:00Z"))
        XCTAssertNil(NotificationGroups.parse("きのう"))
    }

    func testBuckets() throws {
        XCTAssertEqual(NotificationGroups.bucket(of: try row("2026-09-21T09:00:00.000Z"),
                                                 now: now, calendar: calendar), .today)
        XCTAssertEqual(NotificationGroups.bucket(of: try row("2026-09-20T23:00:00.000Z"),
                                                 now: now, calendar: calendar), .yesterday)
        XCTAssertEqual(NotificationGroups.bucket(of: try row("2026-09-17T10:00:00.000Z"),
                                                 now: now, calendar: calendar), .thisWeek)
        XCTAssertEqual(NotificationGroups.bucket(of: try row("2026-08-01T10:00:00.000Z"),
                                                 now: now, calendar: calendar), .earlier)
    }

    /// **`now` から数えているか。** システムの時計を見ていると、
    /// このテストは書いた日だけ通って翌日に落ちる（実際に落ちた）
    func testCountsFromTheGivenNowNotTheSystemClock() throws {
        // システムの時計では遠い過去。`now` から見れば「今日」
        let past = NotificationGroups.parse("2001-01-02T09:00:00.000Z")!
        XCTAssertEqual(NotificationGroups.bucket(of: try row("2001-01-02T01:00:00.000Z"),
                                                 now: past, calendar: calendar), .today)
        XCTAssertEqual(NotificationGroups.bucket(of: try row("2001-01-01T23:00:00.000Z"),
                                                 now: past, calendar: calendar), .yesterday)
    }

    /// 時刻の読めないお知らせは**捨てない**。「今日」にも置かない
    func testUnknownTimeGoesToEarlier() throws {
        XCTAssertEqual(NotificationGroups.bucket(of: try row(nil), now: now, calendar: calendar), .earlier)
        XCTAssertEqual(NotificationGroups.bucket(of: try row("壊れた値"), now: now, calendar: calendar), .earlier)
    }

    func testEmptyBucketsAreNotShown() throws {
        let groups = NotificationGroups.grouped([try row("2026-09-21T09:00:00.000Z")],
                                                now: now, calendar: calendar)
        XCTAssertEqual(groups.map(\.bucket), [.today])
    }

    func testOrderWithinAGroupIsKept() throws {
        let rows = [
            try row("2026-09-21T09:00:00.000Z"),
            try row("2026-09-21T11:00:00.000Z"),
        ]
        let groups = NotificationGroups.grouped(rows, now: now, calendar: calendar)
        // サーバーが返した順のまま（並べ替えない）
        XCTAssertEqual(groups.first?.rows.map(\.id), rows.map(\.id))
    }

    func testGroupsComeInTimeOrder() throws {
        let rows = [
            try row("2026-08-01T10:00:00.000Z"),
            try row("2026-09-21T09:00:00.000Z"),
            try row("2026-09-20T09:00:00.000Z"),
        ]
        XCTAssertEqual(NotificationGroups.grouped(rows, now: now, calendar: calendar).map(\.bucket),
                       [.today, .yesterday, .earlier])
    }
}
