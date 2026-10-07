import XCTest
@testable import JourneyPhoto

/// ストーリーの投稿画面を ✕・下へ払って閉じるときの扱い（`StoryComposerView.leave`）。
///
/// 以前は写真を選んで文字を置いたあとでも、確かめずに閉じて全部消えた。
final class StoryComposerLeaveTests: XCTestCase {

    private func content(shots: [UUID] = [], caption: String = "",
                         overlays: [[TextOverlay]]? = nil, allowReplies: Bool = true) -> StoryComposerContent {
        StoryComposerContent(shotIds: shots, overlays: overlays ?? shots.map { _ in [] },
                             caption: caption, location: "", song: nil,
                             durationSec: StoryService.defaultDurationSec, archive: false,
                             allowReplies: allowReplies)
    }

    /// 🔴 **写真の読み込み中は、閉じる確認に「下書きに保存」を出さない。** 右上の「…」の
    /// 下書き保存は止めていたのに、閉じる確認からは通り、読み込み中の写真を落とした下書きを書いていた
    func testLeaveDialogHidesDraftSaveWhileLoading() {
        let loading = StoryComposerView.leaveDialog(canSaveDraft: true, loading: true, restored: false)
        XCTAssertFalse(loading.canSave, "読み込み中に「下書きに保存」が出ている")
        XCTAssertEqual(loading.title, L("閉じますか？", "Close?"))

        let idle = StoryComposerView.leaveDialog(canSaveDraft: true, loading: false, restored: false)
        XCTAssertTrue(idle.canSave)
        XCTAssertEqual(idle.title, L("下書きに保存しますか？", "Save as a draft?"))
        // 戻した下書きを直した回の説明は前のまま
        XCTAssertNotEqual(StoryComposerView.leaveDialog(canSaveDraft: true, loading: false, restored: true).message,
                          idle.message)
        // 残すと決めた下書きがある間は、読み込みに関係なく出さない（前のまま）
        XCTAssertFalse(StoryComposerView.leaveDialog(canSaveDraft: false, loading: false, restored: false).canSave)
    }

    /// 読み込み中に下書き保存へ来たら、黙って戻らずに理由を知らせる
    func testDraftSaveWhileLoadingSaysWhy() {
        XCTAssertEqual(StoryComposerView.draftSaveBlockedNote(loading: true),
                       L("写真の読み込み中は下書きに保存できません。読み込み終わってからお試しください",
                         "You can't save a draft while photos are loading. Try again when they finish."),
                       "読み込み中の下書き保存が黙って戻る")
        XCTAssertNil(StoryComposerView.draftSaveBlockedNote(loading: false))
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

    /// 写真を拡大・移動・回転しただけでも、閉じる前に確かめる（下書きに残る中身が変わった）
    func testReframingThePhotoIsConfirmed() {
        let id = UUID()
        var restored = content(shots: [id], caption: "雲海")
        restored.framings = [.identity]
        var reframed = restored
        reframed.framings = [PhotoFraming(scale: 2)]
        XCTAssertEqual(StoryComposerView.leave(reframed, restored: restored), .confirm)
        XCTAssertEqual(StoryComposerView.leave(restored, restored: restored), .now)
    }

    /// 投票を置いた・直しただけでも、閉じる前に確かめる
    func testPlacingAPollIsConfirmed() {
        let id = UUID()
        var restored = content(shots: [id], caption: "雲海")
        restored.votes = [nil]
        var polled = restored
        polled.votes = [StoryVoteDraft.new()]
        XCTAssertEqual(StoryComposerView.leave(polled, restored: restored), .confirm)
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

    /// 「返信を許可」を切り替えただけでも確かめる（下書きに残すなら、その選択も残る）。
    /// 切った下書きを戻したまま何も変えなければ、そのまま閉じる
    func testRepliesChoiceCountsAsAnEdit() {
        let id = UUID()
        let restored = content(shots: [id], caption: "雲海")
        XCTAssertEqual(StoryComposerView.leave(content(shots: [id], caption: "雲海", allowReplies: false),
                                               restored: restored), .confirm)
        let restoredOff = content(shots: [id], caption: "雲海", allowReplies: false)
        XCTAssertEqual(StoryComposerView.leave(restoredOff, restored: restoredOff), .now)
    }
}
