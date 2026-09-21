import XCTest
@testable import JourneyPhoto

/// 写真詳細の下段の札（モック6: コメント（N） / 関連写真）。
final class PhotoDetailTabTests: XCTestCase {

    /// **数は取れたときだけ。** 取れていない回に「コメント（0）」と
    /// 出すと「まだ無い」と読まれる（圏外でそう見せるのは嘘）
    func testLabelShowsCountOnlyWhenKnown() {
        XCTAssertEqual(PhotoDetailTab.comments.label(commentCount: nil), L("コメント", "Comments"))
        XCTAssertFalse(PhotoDetailTab.comments.label(commentCount: nil).contains("0"),
                       "取れていないのに 0 を出している")
        XCTAssertTrue(PhotoDetailTab.comments.label(commentCount: 24).contains("24"))
        XCTAssertTrue(PhotoDetailTab.comments.label(commentCount: 0).contains("0"),
                      "取れた 0 は「まだ無い」なので出す")
    }

    /// 関連写真は数を持たない（数えていない）
    func testRelatedLabelHasNoCount() {
        XCTAssertEqual(PhotoDetailTab.related.label(commentCount: 24), L("関連写真", "Related"))
        XCTAssertFalse(PhotoDetailTab.related.label(commentCount: 24).contains("24"))
    }

    func testOrderIsCommentsThenRelated() {
        XCTAssertEqual(PhotoDetailTab.allCases, [.comments, .related])
    }
}
