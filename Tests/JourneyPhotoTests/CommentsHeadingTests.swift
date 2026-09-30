import XCTest
@testable import JourneyPhoto

/// 写真詳細のコメントの見出し（「コメント（N）」）。
final class CommentsHeadingTests: XCTestCase {

    /// **数は取れたときだけ。** 取れていない回に「コメント（0）」と
    /// 出すと「まだ無い」と読まれる（圏外でそう見せるのは嘘）
    func testLabelShowsCountOnlyWhenKnown() {
        XCTAssertEqual(CommentsHeading.label(commentCount: nil), L("コメント", "Comments"))
        XCTAssertFalse(CommentsHeading.label(commentCount: nil).contains("0"),
                       "取れていないのに 0 を出している")
        XCTAssertTrue(CommentsHeading.label(commentCount: 24).contains("24"))
        XCTAssertTrue(CommentsHeading.label(commentCount: 0).contains("0"),
                      "取れた 0 は「まだ無い」なので出す")
    }

    /// 🔴 **すべてブロックした人のコメントなら 0。** 見出しは「コメント（1）」なのに
    /// 下が空白だった（数はサーバーの総数のまま、一覧だけ落としていた）
    func testVisibleCountSubtractsHiddenComments() {
        XCTAssertEqual(CommentsHeading.visibleCount(total: 1, loaded: 1, shown: 0), 0)
        XCTAssertEqual(CommentsHeading.visibleCount(total: 5, loaded: 5, shown: 3), 3)
        // 一覧をまだ読んでいない回はサーバーの数のまま
        XCTAssertEqual(CommentsHeading.visibleCount(total: 4, loaded: 0, shown: 0), 4)
        XCTAssertNil(CommentsHeading.visibleCount(total: nil, loaded: 2, shown: 1))
    }
}
