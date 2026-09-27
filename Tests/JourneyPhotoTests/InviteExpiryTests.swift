import XCTest
@testable import JourneyPhoto

/// 招待リンクの期限（`InviteLink.expiry`）。サーバーは切れた招待も一覧に返し続ける。
final class InviteExpiryTests: XCTestCase {

    private func date(_ iso: String) throws -> Date {
        try XCTUnwrap(NotificationGroups.parse(iso))
    }

    /// 🔴 **切れた招待は「切れた」と判る。** 以前はトークンがあるだけで共有を出していた
    func testPastExpiryIsExpired() throws {
        let now = try date("2026-09-27T12:00:00.000Z")
        XCTAssertEqual(InviteLink.expiry("2026-09-20T12:00:00.000Z", now: now), .expired)
    }

    /// 期限ちょうどは切れている（サーバーの `inviteState` は `exp > now` だけを通す）
    func testExactlyAtExpiryIsExpired() throws {
        let now = try date("2026-09-27T12:00:00.000Z")
        XCTAssertEqual(InviteLink.expiry("2026-09-27T12:00:00.000Z", now: now), .expired)
    }

    /// まだ使えるなら期限を返す（「〜まで」に出す）。小数秒の無い書き方も読む
    func testFutureExpiryIsValidWithItsDate() throws {
        let now = try date("2026-09-27T12:00:00.000Z")
        XCTAssertEqual(InviteLink.expiry("2026-10-04T12:00:00.000Z", now: now),
                       .valid(until: try date("2026-10-04T12:00:00.000Z")))
        XCTAssertEqual(InviteLink.expiry("2026-10-04T12:00:00Z", now: now),
                       .valid(until: try date("2026-10-04T12:00:00Z")))
    }

    /// 期限が無い・読めないときは「切れた」と言い切らない（Web も日付を出さずにリンクを見せる）
    func testMissingOrUnreadableExpiryIsUnknown() {
        XCTAssertEqual(InviteLink.expiry(nil, now: Date()), .unknown)
        XCTAssertEqual(InviteLink.expiry("", now: Date()), .unknown)
        XCTAssertEqual(InviteLink.expiry("来週", now: Date()), .unknown)
    }

    /// 「〜まで」の日付は Web（`toLocaleDateString("ja-JP")`）と同じ形。**端末のゾーンのその日**
    func testUntilLabelMatchesWebAndUsesTheDeviceZone() throws {
        let expires = try date("2026-10-04T20:00:00.000Z")
        XCTAssertEqual(InviteLink.untilLabel(expires, timeZone: TimeZone(identifier: "UTC")!), "2026/10/4")
        // 東京では翌日の朝5時
        XCTAssertEqual(InviteLink.untilLabel(expires, timeZone: TimeZone(identifier: "Asia/Tokyo")!), "2026/10/5")
    }
}
