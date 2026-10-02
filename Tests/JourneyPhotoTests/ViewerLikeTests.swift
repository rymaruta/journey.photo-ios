import XCTest
@testable import JourneyPhoto

/// 大きく見る画面の下のハート（`ViewerLike`）。
final class ViewerLikeTests: XCTestCase {

    /// 🔴 **詳細の1枚も、送っている間は先に灯す。** 以前は答えまで白いままだった
    /// （隣の写真は先に灯っていた）
    func testCurrentPhotoLightsWhileSending() {
        XCTAssertTrue(ViewerLike.isLiked("p1", currentId: "p1", currentLiked: false,
                                         pending: ["p1": true], stored: false),
                      "送っている間、詳細の1枚のハートが白いまま")
        // 外す向きも先に出す
        XCTAssertFalse(ViewerLike.isLiked("p1", currentId: "p1", currentLiked: true,
                                          pending: ["p1": false], stored: true))
    }

    /// **届かなければ戻る**（送っている間の向きを外すと、画面の値に戻る）
    func testFailureFallsBackToTheScreenValue() {
        XCTAssertFalse(ViewerLike.isLiked("p1", currentId: "p1", currentLiked: false,
                                          pending: [:], stored: true),
                       "詳細の1枚に端末の控えを出している（画面の値が本体）")
    }

    /// 隣の写真は端末の控え（ホームのハートと同じ出どころ）
    func testNeighbourUsesTheStoredValue() {
        XCTAssertTrue(ViewerLike.isLiked("p2", currentId: "p1", currentLiked: false,
                                         pending: ["p1": false], stored: true))
        XCTAssertFalse(ViewerLike.isLiked("p2", currentId: "p1", currentLiked: true,
                                          pending: [:], stored: false))
    }

    /// 理由の分からない失敗にも一言を出す（黙って戻さない）
    func testFailureNoticeIsNeverEmpty() {
        struct Plain: Error {}
        XCTAssertFalse(ViewerLike.failureNotice(Plain()).isEmpty)
        XCTAssertEqual(ViewerLike.failureNotice(APIError.unreachable), APIError.unreachable.errorDescription)
    }
}
