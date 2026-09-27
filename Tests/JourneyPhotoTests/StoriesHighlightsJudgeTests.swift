import XCTest
@testable import JourneyPhoto

/// ハイライト・ストーリーの小さな判定（D9・D10・D13）。
final class StoriesHighlightsJudgeTests: XCTestCase {

    // MARK: D9 ハイライトの編集で中身が取れなかったら保存させない
    // → `HighlightFailureTests.testCannotSaveWhileTheCurrentContentsFailedToLoad`（main 側）が見る

    // MARK: D10 問いに答えていない下書きは消さない

    func testUnansweredDraftIsKept() {
        XCTAssertTrue(StoryComposerView.keepsDraft(stamp: "t1", keepExisting: false, unansweredStamp: "t1"))
    }

    func testDraftSavedAgainInThisSessionIsCleared() {
        // 同じ回に保存し直した（印が変わった）ものは、この回の投稿の下書き
        XCTAssertFalse(StoryComposerView.keepsDraft(stamp: "t2", keepExisting: false, unansweredStamp: "t1"))
        XCTAssertFalse(StoryComposerView.keepsDraft(stamp: "t1", keepExisting: false, unansweredStamp: nil))
        XCTAssertTrue(StoryComposerView.keepsDraft(stamp: "t1", keepExisting: true, unansweredStamp: nil))
    }

    // MARK: D13 自分用（アーカイブ）のストーリーには「写真として残す」を出さない

    private func story(_ extra: String) throws -> Story {
        try JSONDecoder.api.decode(Story.self, from: Data("""
        {"id":"s1","src":"https://example.com/a.jpg"\(extra)}
        """.utf8))
    }

    func testArchiveStoryCannotBeKept() throws {
        XCTAssertFalse(StoryViewerView.canKeepAsPhoto(try story(#","archive":true"#)))
    }

    func testPlainPhotoStoryCanBeKept() throws {
        XCTAssertTrue(StoryViewerView.canKeepAsPhoto(try story("")))
        XCTAssertFalse(StoryViewerView.canKeepAsPhoto(try story(#","mediaType":"video""#)))
    }
}
