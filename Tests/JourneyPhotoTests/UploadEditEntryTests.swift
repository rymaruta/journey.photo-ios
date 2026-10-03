import XCTest
@testable import JourneyPhoto

/// 投稿画面から写真の編集へ入る口（`UploadEditEntry`・`UploadEditHintMemory`）。
/// 2026-10-03 owner（実機 1.0.58）「写真編集の仕方がわからなかった。どこから入るのか」
final class UploadEditEntryTests: XCTestCase {

    typealias Tag = UploadEditEntry.ThumbTag

    // MARK: - サムネの札（一本の札）

    func testUneditedEditablePhotoSaysEdit() {
        let tag = UploadEditEntry.thumbTag(badge: nil, canEdit: true)
        XCTAssertEqual(tag, .edit)
        XCTAssertEqual(tag.text, L("編集", "Edit"))
    }

    func testEditedPhotoKeepsItsBadgeInsteadOfEdit() {
        XCTAssertEqual(UploadEditEntry.thumbTag(badge: "夕凪", canEdit: true), .edited("夕凪"))
        XCTAssertEqual(UploadEditEntry.thumbTag(badge: "夕凪", canEdit: true).text, "夕凪",
                       "「編集」と編集済みの札を重ねない")
        XCTAssertEqual(UploadEditEntry.thumbTag(badge: L("調整", "Adjusted"), canEdit: true).text, L("調整", "Adjusted"))
    }

    func testLockedPhotoNeverSaysEdit() {
        // 再試行の鍵を控えている写真・送っている間——押しても開かないので「編集」と書かない
        XCTAssertEqual(UploadEditEntry.thumbTag(badge: nil, canEdit: false), .none)
        XCTAssertNil(Tag.none.text)
        // 編集してある事実は、開けなくても出す
        XCTAssertEqual(UploadEditEntry.thumbTag(badge: "夕凪", canEdit: false), .edited("夕凪"))
    }

    func testEmptyBadgeIsTreatedAsUnedited() {
        XCTAssertEqual(UploadEditEntry.thumbTag(badge: "", canEdit: true), .edit)
        XCTAssertEqual(UploadEditEntry.thumbTag(badge: "", canEdit: false), .none)
    }

    func testTagFollowsRealRecipes() {
        // 実際のレシピから: 無編集＝「編集」、調整だけ＝「調整」
        XCTAssertEqual(UploadEditEntry.thumbTag(badge: PhotoEditBadge.text(for: .identity), canEdit: true), .edit)
        var adjusted = PhotoRecipe.identity
        adjusted.exposure = 0.5
        XCTAssertEqual(UploadEditEntry.thumbTag(badge: PhotoEditBadge.text(for: adjusted), canEdit: true),
                       .edited(L("調整", "Adjusted")))
    }

    // MARK: - 「写真を編集」で開く写真

    func testButtonOpensFirstEditablePhoto() {
        XCTAssertEqual(UploadEditEntry.buttonTarget(editable: [true, true, true]), 0)
        XCTAssertEqual(UploadEditEntry.buttonTarget(editable: [false, true, true]), 1,
                       "1枚目が開けなければ、開ける写真の最初")
    }

    func testButtonHiddenWithoutEditablePhoto() {
        XCTAssertNil(UploadEditEntry.buttonTarget(editable: []), "写真が無い")
        XCTAssertNil(UploadEditEntry.buttonTarget(editable: [false, false]), "開ける写真が無い")
    }

    // MARK: - 一度だけの案内

    func testHintShowsOnlyOnce() {
        XCTAssertTrue(UploadEditEntry.showsHint(alreadyShown: false, hasEditablePhoto: true))
        XCTAssertFalse(UploadEditEntry.showsHint(alreadyShown: true, hasEditablePhoto: true))
    }

    func testHintSkippedWhenNothingCanBeEdited() {
        XCTAssertFalse(UploadEditEntry.showsHint(alreadyShown: false, hasEditablePhoto: false))
    }

    func testHintMemoryRemembersAcrossInstances() {
        let suite = "UploadEditEntryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = UploadEditHintMemory(defaults: defaults)
        XCTAssertFalse(first.shown, "覚えが無ければ、まだ出していない")
        XCTAssertTrue(UploadEditEntry.showsHint(alreadyShown: first.shown, hasEditablePhoto: true))
        first.shown = true

        // 次に投稿画面を開いたとき（別の入れ物）も覚えている
        let second = UploadEditHintMemory(defaults: defaults)
        XCTAssertTrue(second.shown)
        XCTAssertFalse(UploadEditEntry.showsHint(alreadyShown: second.shown, hasEditablePhoto: true))
    }

    func testHintStaysForAFewSeconds() {
        XCTAssertGreaterThanOrEqual(UploadEditEntry.hintSeconds, 3)
        XCTAssertLessThanOrEqual(UploadEditEntry.hintSeconds, 6)
    }
}
