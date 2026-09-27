import XCTest
@testable import JourneyPhoto

/// ハイライト・ストーリーの小さな判定（D9・D10・D13）。
final class StoriesHighlightsJudgeTests: XCTestCase {

    // MARK: D9 ハイライトの編集で中身が取れなかったら保存させない
    // → `HighlightFailureTests.testCannotSaveWhileTheCurrentContentsFailedToLoad`（main 側）が見る

    // MARK: D10 問いに答えていない下書きは消さない

    func testUnansweredDraftIsKept() {
        XCTAssertTrue(StoryComposerView.keepsDraft(stamp: "t1", keptStamp: nil, unansweredStamp: "t1"))
    }

    func testDraftSavedAgainInThisSessionIsCleared() {
        // 同じ回に保存し直した（印が変わった）ものは、この回の投稿の下書き
        XCTAssertFalse(StoryComposerView.keepsDraft(stamp: "t2", keptStamp: nil, unansweredStamp: "t1"))
        XCTAssertFalse(StoryComposerView.keepsDraft(stamp: "t1", keptStamp: nil, unansweredStamp: nil))
        XCTAssertTrue(StoryComposerView.keepsDraft(stamp: "t1", keptStamp: "t1", unansweredStamp: nil))
        // 残すと決めた下書きが消えた後（裏の送信・人の替わり）は、守るものが無い
        XCTAssertFalse(StoryComposerView.keepsDraft(stamp: nil, keptStamp: "t1", unansweredStamp: nil),
                       "無い下書きを守って保存を止めている")
        // 残すと決めた後に別の下書きになった（印が変わった）なら守らない
        XCTAssertFalse(StoryComposerView.keepsDraft(stamp: "t2", keptStamp: "t1", unansweredStamp: nil))
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
