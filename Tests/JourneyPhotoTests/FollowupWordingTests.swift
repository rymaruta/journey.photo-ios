import XCTest
@testable import JourneyPhoto

/// 2026-11-07 の言葉まわりの直し(接写の頁送りの読み上げ・新しくなったことのタブ名・下書きの期限の言い方)。
/// 画面は Linux で描けないので、書いてあるものを読んで見張る(クラスは MainActor ではない・同期でよい)
final class FollowupWordingTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 接写の頁送りの3つの押せるものに読み上げの名前がある(前の頁・次の頁・昼夜の切り替え)。
    /// `pager` の `.accessibilityLabel(label)` を外すと落ちる
    func testContactSheetPagersHaveSpokenLabels() throws {
        let sheet = try source("Sources/JourneyPhoto/Features/Camper/Room/CamperRoomContactSheet.swift")
        for text in [#"L("前の頁", "Previous page")"#, #"L("次の頁", "Next page")"#,
                     #"L("昼にする", "Switch to day")"#, #"L("夜にする", "Switch to night")"#,
                     ".accessibilityLabel(label)"] {
            XCTAssertTrue(sheet.contains(text), "接写の頁送りの読み上げに「\(text)」が無い")
        }
    }

    /// 新しくなったことの本文は、タブの表記(「探す」「マップ」)と合わせる(`Labels.searchTab`・`mapTab`)
    func testWhatsNewUsesTheRealTabNames() throws {
        let json = try source("Sources/JourneyPhoto/Resources/WhatsNew.json")
        XCTAssertFalse(json.contains("ホーム・さがす"), "タブは「探す」")
        XCTAssertFalse(json.contains("さがす・地図"), "タブは「マップ」")
        XCTAssertTrue(json.contains("ホーム・探す・マップ・"))
    }

    /// 移した下書きは保存日時より後から数えるので、期限は「保存から」ではなく「作ってから」と言う
    func testDraftExpiryWordingIsFromCreation() throws {
        let text = try source("Sources/JourneyPhoto/Features/Drafts/DraftsText.swift")
        XCTAssertFalse(text.contains("保存から\\("), "期限を「保存から」と言っている")
        XCTAssertFalse(text.contains("days after saving"))
        XCTAssertTrue(text.contains("作ってから\\("))
    }

    /// 編集をやめる確認に「破棄」「Discard」を使わない(何が起きるかで言う)
    func testPhotoEditCloseConfirmationWording() throws {
        let edit = try source("Sources/JourneyPhoto/Features/Upload/PhotoEditView.swift")
        XCTAssertTrue(edit.contains(#"L("編集を保存せずに閉じますか？", "Close without saving your edits?")"#))
        XCTAssertTrue(edit.contains(#"L("保存せずに閉じる", "Close without saving")"#))
        for file in ["Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift",
                     "Sources/JourneyPhoto/Features/Stories/StoriesRow.swift"] {
            let text = try source(file)
            XCTAssertFalse(text.contains(#"L("やめる", "Discard")"#), "\(file) の英語が「Discard」のまま")
        }
    }
}
