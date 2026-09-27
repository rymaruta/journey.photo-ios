import XCTest
@testable import JourneyPhoto

/// アルバムの招待リンクの期限と、お知らせのフォローバックを出すかの判定。
final class AlbumsAndFollowBackTests: XCTestCase {

    private let now = ISO8601DateFormatter().date(from: "2026-09-27T07:00:00Z")!

    /// サーバーは `toISOString()`（小数秒つき）で返す。**切れたリンクは共有させない**
    func testExpiredInviteIsDetected() {
        XCTAssertTrue(AlbumsViewModel.isInviteExpired("2026-09-27T06:59:59.000Z", now: now))
        XCTAssertTrue(AlbumsViewModel.isInviteExpired("2026-09-20T00:00:00Z", now: now))
        XCTAssertFalse(AlbumsViewModel.isInviteExpired("2026-10-04T07:00:00.123Z", now: now))
    }

    /// 期限が無い・読めないときは切れていない扱い（有効なリンクまで出せなくしない）
    func testMissingOrBrokenExpiryIsNotExpired() {
        XCTAssertFalse(AlbumsViewModel.isInviteExpired(nil, now: now))
        XCTAssertFalse(AlbumsViewModel.isInviteExpired("", now: now))
        XCTAssertFalse(AlbumsViewModel.isInviteExpired("あした", now: now))
        XCTAssertNotNil(AlbumsViewModel.inviteExpiry("2026-10-04T07:00:00.123Z"))
    }

    /// **フォロー中が取れない間は、誰にもフォローバックを出さない**
    /// （空扱いにすると全員に出ていた）
    func testFollowBackHiddenWhileFollowingUnknown() {
        XCTAssertFalse(NotificationsViewModel.showsFollowBack(to: "u1", following: nil))
    }

    func testFollowBackOnlyForPeopleNotFollowed() {
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
