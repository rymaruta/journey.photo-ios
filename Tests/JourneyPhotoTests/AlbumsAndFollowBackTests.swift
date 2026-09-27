import XCTest
@testable import JourneyPhoto

/// アルバムの招待リンクの期限と、お知らせのフォローバックを出すかの判定。
@MainActor
final class AlbumsAndFollowBackTests: XCTestCase {

    private let now = ISO8601DateFormatter().date(from: "2026-09-27T07:00:00Z")!

    /// サーバーは `toISOString()`（小数秒つき）で返す。**切れたリンクは共有させない**
    ///
    /// 期限の判定は `InviteLink.expiry` の1本だけ（main 側で `AlbumsViewModel` に
    /// 足された同じ判定は、併合で `InviteLink` に寄せた）。
    func testExpiredInviteIsDetected() async {
        XCTAssertEqual(InviteLink.expiry("2026-09-27T06:59:59.000Z", now: now), .expired)
        XCTAssertEqual(InviteLink.expiry("2026-09-20T00:00:00Z", now: now), .expired)
        XCTAssertNotEqual(InviteLink.expiry("2026-10-04T07:00:00.123Z", now: now), .expired)
    }

    /// 期限が無い・読めないときは切れていない扱い（有効なリンクまで出せなくしない）
    func testMissingOrBrokenExpiryIsNotExpired() async {
        XCTAssertNotEqual(InviteLink.expiry(nil, now: now), .expired)
        XCTAssertNotEqual(InviteLink.expiry("", now: now), .expired)
        XCTAssertNotEqual(InviteLink.expiry("あした", now: now), .expired)
        XCTAssertEqual(InviteLink.expiry("2026-10-04T07:00:00.123Z", now: now),
                       .valid(until: NotificationGroups.parse("2026-10-04T07:00:00.123Z")!))
    }

    /// **フォロー中が取れない間は、誰にもフォローバックを出さない**
    /// （空扱いにすると全員に出ていた）
    func testFollowBackHiddenWhileFollowingUnknown() async {
        XCTAssertFalse(NotificationsViewModel.showsFollowBack(to: "u1", following: nil))
    }

    func testFollowBackOnlyForPeopleNotFollowed() async {
        XCTAssertTrue(NotificationsViewModel.showsFollowBack(to: "u1", following: []))
        XCTAssertTrue(NotificationsViewModel.showsFollowBack(to: "u1", following: ["u2"]))
        XCTAssertFalse(NotificationsViewModel.showsFollowBack(to: "u1", following: ["u1"]))
    }

    /// 読めていない最初の姿は「分からない」（nil）であって、空ではない
    @MainActor
    func testInitialFollowingIsUnknown() async {
        let model = NotificationsViewModel()
        XCTAssertNil(model.following)
        model.forget()
        XCTAssertNil(model.following)
    }
}
