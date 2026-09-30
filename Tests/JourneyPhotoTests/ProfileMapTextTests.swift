import XCTest
@testable import JourneyPhoto

/// 人のページの地図が空のときの案内。
///
/// 🔴 **「投稿するときに場所を入れると」は本人にだけ言う。** 人のページで、見ている人を
/// 投稿した人として扱っていた
final class ProfileMapTextTests: XCTestCase {

    func testOthersPageDoesNotAskTheViewerToPost() {
        let text = MyPhotosMap.emptyMessage(isMine: false)
        XCTAssertFalse(text.contains("投稿するときに") || text.contains("when you post"),
                       "人のページで見ている人に投稿を促している: \(text)")
    }

    func testOwnPageStillExplainsHowToFillTheMap() {
        let text = MyPhotosMap.emptyMessage(isMine: true)
        XCTAssertTrue(text.contains("投稿するときに") || text.contains("when you post"))
    }
}
