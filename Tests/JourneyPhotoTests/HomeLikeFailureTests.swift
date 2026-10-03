import XCTest
@testable import JourneyPhoto

/// ホームのカードのハート（`HomeLikeGate.send`・バグ探し 2026-10-03）
@MainActor
final class HomeLikeFailureTests: XCTestCase {

    private struct Offline: LocalizedError {
        var errorDescription: String? { "通信できません" }
    }

    private func stores() -> (FavoritesStore, LikeCountStore, ToastCenter) {
        let favorites = FavoritesStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        favorites.use(userId: "me")
        return (favorites, LikeCountStore(), ToastCenter())
    }

    /// 🔴 **届かなかったら戻して、一言出す**（大きく見る画面と同じ `ViewerLike.failureNotice`）。
    /// 以前は戻すだけで、先に灯したハートが黙って消えた
    func testFailedLikeRollsBackAndSaysSo() async {
        let (favorites, counts, toasts) = stores()
        // カードが先に灯した姿
        favorites.set("p1", favorite: true)
        await HomeLikeGate.send("p1", wasLiked: false, owner: "me",
                                favorites: favorites, likeCounts: counts, toasts: toasts) {
            throw Offline()
        }
        XCTAssertFalse(favorites.contains("p1"), "届かなかったのに いいね済みのまま")
        XCTAssertEqual(toasts.current?.kind, .failure, "届かなかったと言っていない")
        XCTAssertEqual(toasts.current?.text, ViewerLike.failureNotice(Offline()))
        XCTAssertNil(counts.entry(for: "p1"))
    }

    /// 外すのが届かなかったら、いいね済みに戻す（押す前の姿）
    func testFailedUnlikeRestoresTheLike() async {
        let (favorites, counts, toasts) = stores()
        favorites.set("p1", favorite: false)
        await HomeLikeGate.send("p1", wasLiked: true, owner: "me",
                                favorites: favorites, likeCounts: counts, toasts: toasts) {
            throw URLError(.notConnectedToInternet)
        }
        XCTAssertTrue(favorites.contains("p1"))
        XCTAssertEqual(toasts.current?.text, ViewerLike.failureNotice(URLError(.notConnectedToInternet)))
    }

    /// 届いたら答えの状態と数を書き、何も言わない（数を返さない答えは数を書かない）
    func testSuccessWritesTheAnswerQuietly() async {
        let (favorites, counts, toasts) = stores()
        favorites.set("p1", favorite: true)
        await HomeLikeGate.send("p1", wasLiked: false, owner: "me",
                                favorites: favorites, likeCounts: counts, toasts: toasts) {
            SocialService.LikeResult(liked: true, likes: 7)
        }
        XCTAssertTrue(favorites.contains("p1"))
        XCTAssertEqual(counts.entry(for: "p1")?.count, 7)
        XCTAssertNil(toasts.current)

        await HomeLikeGate.send("p2", wasLiked: false, owner: "me",
                                favorites: favorites, likeCounts: counts, toasts: toasts) {
            SocialService.LikeResult(liked: false, likes: nil)
        }
        XCTAssertFalse(favorites.contains("p2"))
        XCTAssertNil(counts.entry(for: "p2"), "数を返さない答えで数を作っている")
    }
}
