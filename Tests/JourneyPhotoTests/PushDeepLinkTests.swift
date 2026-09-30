import XCTest
@testable import JourneyPhoto

/// 通知を押したら、その写真・その人へ（2026-09-30）。
///
/// 固定したいのは:
///  1. プッシュの中身（`api-user/src/apns.ts` の `pushPayload`・最上位の鍵）から、
///     お知らせの一覧と同じ1件を作る。知らない種類・種類の無い中身は行き先なし
///  2. 行き先の決め方は**一覧の行を押したときと同じ**（写真が引けなければ一覧に留まる）
///  3. 押した行き先は1回だけ受け取る。続けて押したら後の方
@MainActor
final class PushDeepLinkTests: XCTestCase {

    private func photo(id: String) throws -> Photo {
        try JSONDecoder.api.decode(
            Photo.self, from: Data(#"{"id":"\#(id)","src":"https://x/\#(id).jpg"}"#.utf8)
        )
    }

    // MARK: - 1. 中身を読む

    /// サーバーが送る形そのもの（`aps` と並んで最上位に行き先の鍵）
    func testReadsTheServerPayload() async {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["loc-key": "NOTIF_LIKE", "loc-args": ["A"]], "badge": 3],
            "type": "like", "photoId": "p1", "byId": "u9",
        ]
        let target = AppNotification.fromPush(userInfo)
        XCTAssertEqual(target?.kind, .like)
        XCTAssertEqual(target?.photoId, "p1")
        XCTAssertEqual(target?.byId, "u9")
    }

    func testFollowCarriesTheTargetUser() async {
        let target = AppNotification.fromPush(["type": "follow", "byId": "u1", "targetUserId": "u1"])
        XCTAssertEqual(target?.kind, .follow)
        XCTAssertEqual(target?.targetUserId, "u1")
    }

    /// 種類の無い中身（見頃のお知らせ・古い形）は行き先なし。知らない種類は種類 nil
    func testUnknownOrMissingTypeHasNoDestination() async {
        XCTAssertNil(AppNotification.fromPush(["photoId": "p1"]))
        XCTAssertNil(AppNotification.fromPush([:]))
        XCTAssertNil(AppNotification.fromPush(["type": "mystery", "photoId": "p1"])?.kind)
        // 文字列でない値は読まない（落ちない）
        XCTAssertNil(AppNotification.fromPush(["type": 3]))
    }

    // MARK: - 2. 一覧の行と同じ行き先

    func testLikeOpensThePhotoWhenItCanBeFound() async throws {
        let model = NotificationsViewModel()
        model.setFeedForTesting([try photo(id: "p1")])
        let target = try XCTUnwrap(AppNotification.fromPush(["type": "comment", "photoId": "p1", "byId": "u9"]))
        guard case .photo(let found, let fromPublicFeed)? = model.route(for: target) else {
            return XCTFail("写真へ行かない")
        }
        XCTAssertEqual(found.id, "p1")
        XCTAssertTrue(fromPublicFeed)
    }

    /// 引けない写真（消された・圏外で一覧が空）とストーリーの返信は、一覧に留まる
    func testStaysOnTheListWhenThereIsNowhereToGo() async throws {
        let model = NotificationsViewModel()
        model.setFeedForTesting([])
        XCTAssertNil(model.route(for: try XCTUnwrap(AppNotification.fromPush(["type": "like", "photoId": "gone"]))))
        XCTAssertNil(model.route(for: try XCTUnwrap(AppNotification.fromPush(["type": "storyreply", "byId": "u1"]))))
    }

    func testFollowOpensTheProfileWithoutLoading() async throws {
        let target = try XCTUnwrap(AppNotification.fromPush(["type": "follow", "byId": "u1", "targetUserId": "u1"]))
        XCTAssertEqual(NotificationsViewModel().route(for: target), .user("u1"))
    }

    // MARK: - 3. 受け取るのは1回

    func testTargetIsTakenOnceAndTheLastTapWins() async {
        let router = NotificationRouter.shared
        _ = router.takePendingActivity()
        _ = router.takePendingTarget()
        router.openActivity(target: AppNotification.fromPush(["type": "follow", "byId": "a", "targetUserId": "a"]))
        router.openActivity(target: AppNotification.fromPush(["type": "follow", "byId": "b", "targetUserId": "b"]))
        XCTAssertEqual(router.takePendingTarget()?.targetUserId, "b")
        XCTAssertNil(router.takePendingTarget())
        // 行き先の無い押し方（一覧を開くだけ）は、前の行き先を残さない
        router.openActivity(target: AppNotification.fromPush(["type": "follow", "byId": "c", "targetUserId": "c"]))
        router.openActivity()
        XCTAssertNil(router.takePendingTarget())
        _ = router.takePendingActivity()
    }

    /// 🔴 古い行き先・待つのをやめた回の行き先は使わない（後でベルから開いたときに勝手に積まない）
    func testStaleOrDroppedTargetIsNotUsed() async {
        let router = NotificationRouter.shared
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        router.openActivity(target: AppNotification.fromPush(["type": "follow", "byId": "a", "targetUserId": "a"]), now: t0)
        XCTAssertNil(router.takePendingTarget(now: t0.addingTimeInterval(NotificationRouter.targetLifetime + 1)))
        router.openActivity(target: AppNotification.fromPush(["type": "follow", "byId": "b", "targetUserId": "b"]), now: t0)
        XCTAssertEqual(router.takePendingTarget(now: t0.addingTimeInterval(5))?.targetUserId, "b")
        router.openActivity(target: AppNotification.fromPush(["type": "follow", "byId": "c", "targetUserId": "c"]))
        router.dropPendingTarget()
        XCTAssertNil(router.takePendingTarget())
        _ = router.takePendingActivity()
    }
}
