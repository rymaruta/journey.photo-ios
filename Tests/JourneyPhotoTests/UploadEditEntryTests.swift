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

    // MARK: - 帯の下の「色を編集」は無くした（2026-11-16 判断・使い勝手の見直し A11）

    /// 編集の入口は写真の札の「編集」1つ。帯の下のボタン（`upload.editButton`）を戻さない
    func testOnlyThumbTagOpensEditor() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Features/Upload/UploadView.swift")
        let upload = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(upload.contains("\"upload.editButton\""), "帯の下の「色を編集」が戻った（入口が2つ重なる）")
        XCTAssertFalse(upload.contains("private var editButton"), "帯の下の「色を編集」が戻った")
        XCTAssertTrue(upload.contains("openEditor(item.id)"), "写真の札から編集を開けない")
        XCTAssertTrue(upload.contains("UploadEditEntry.thumbTag(badge: item.editBadge, canEdit: canEdit)"))
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
