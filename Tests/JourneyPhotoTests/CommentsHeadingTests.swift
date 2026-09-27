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
}
