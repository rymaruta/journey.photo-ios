import XCTest
@testable import JourneyPhoto

/// ストーリーの投稿画面を ✕・下へ払って閉じるときの扱い（`StoryComposerView.leave`）。
///
/// 以前は写真を選んで文字を置いたあとでも、確かめずに閉じて全部消えた。
final class StoryComposerLeaveTests: XCTestCase {

    private func content(shots: [UUID] = [], caption: String = "",
                         overlays: [[TextOverlay]]? = nil) -> StoryComposerContent {
        StoryComposerContent(shotIds: shots, overlays: overlays ?? shots.map { _ in [] },
                             caption: caption, location: "", song: nil,
                             durationSec: StoryService.defaultDurationSec, archive: false)
    }

    func testEmptyComposerClosesAtOnce() {
        XCTAssertEqual(StoryComposerView.leave(content(), restored: nil), .now)
    }

    func testPickedPhotosAreConfirmedBeforeClosing() {
        XCTAssertEqual(StoryComposerView.leave(content(shots: [UUID()]), restored: nil), .confirm)
    }

    func testRestoredDraftWithoutEditsClosesAtOnce() {
        // 「続きから」で戻したまま＝同じものが下書きに残っている
        let restored = content(shots: [UUID(), UUID()], caption: "雲海")
        XCTAssertEqual(StoryComposerView.leave(restored, restored: restored), .now)
    }

    func testRestoredDraftEditedAfterwardsIsConfirmed() {
        let id = UUID()
        let restored = content(shots: [id], caption: "雲海")
        // ひとことを変えた
        XCTAssertEqual(StoryComposerView.leave(content(shots: [id], caption: "雲海と朝日"),
                                               restored: restored), .confirm)
        // 文字を置いた
        XCTAssertEqual(StoryComposerView.leave(content(shots: [id], caption: "雲海",
                                                       overlays: [[TextOverlay(text: "朝")]]),
                                               restored: restored), .confirm)
        // 写真を足した
        XCTAssertEqual(StoryComposerView.leave(content(shots: [id, UUID()], caption: "雲海"),
                                               restored: restored), .confirm)
    }
}
