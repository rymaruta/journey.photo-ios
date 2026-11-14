import XCTest
@testable import JourneyPhoto

/// 書きかけのシートを下へ払ったとき（`SheetSwipe`・`sheetSwipeGuard`）と、投稿画面の下の主ボタン
/// （`UploadSubmitBar`）。2026-11-14・札 #188・点検「直すべき 1・2」
final class SheetSwipeGuardTests: XCTestCase {

    // MARK: - 下へ払う

    /// 書きかけが無ければ今までどおり払って閉じる。書きかけがあれば止めて確かめ、送っている最中は止めるだけ
    func testSwipeFollowsTheSameDecisionAsTheCloseButton() {
        XCTAssertEqual(SheetSwipe.from(.now), .close)
        XCTAssertEqual(SheetSwipe.from(.confirm), .ask)
        XCTAssertEqual(SheetSwipe.from(.wait), .hold)
        XCTAssertFalse(SheetSwipe.close.blocksSwipe, "書きかけが無いのに払って閉じられない")
        XCTAssertTrue(SheetSwipe.ask.blocksSwipe)
        XCTAssertTrue(SheetSwipe.hold.blocksSwipe)
        XCTAssertEqual(SheetSwipe.busy(false), .close)
        XCTAssertEqual(SheetSwipe.busy(true), .hold)
    }

    /// 投稿画面: 左上の「キャンセル」と下へ払うは同じ判断（書きかけ → 閉じる確認・送信中 → 止めるだけ）
    func testUploadAsksOnlyWithADraft() {
        XCTAssertEqual(SheetSwipe.from(UploadDraftRules.leave(hasDraft: false, isWorking: false)), .close,
                       "書きかけが無いのに払うと確かめが出る")
        XCTAssertEqual(SheetSwipe.from(UploadDraftRules.leave(hasDraft: true, isWorking: false)), .ask,
                       "書きかけのまま払っても確かめが出ない")
        XCTAssertEqual(SheetSwipe.from(UploadDraftRules.leave(hasDraft: true, isWorking: true)), .hold)
        XCTAssertEqual(SheetSwipe.from(UploadDraftRules.leave(hasDraft: false, isWorking: true)), .hold)
    }

    /// 1つのシートに部品が重なったとき（積んだ画面）、手前から見て最初の確かめが答える。
    /// 手前が送っている最中なら奥の確かめは出さない
    func testFrontmostGuardAnswers() {
        XCTAssertNil(SheetSwipe.responder(in: []))
        XCTAssertNil(SheetSwipe.responder(in: [.close]))
        XCTAssertEqual(SheetSwipe.responder(in: [.ask]), 0)
        XCTAssertEqual(SheetSwipe.responder(in: [.ask, .ask]), 1, "奥の画面の確かめが出る")
        XCTAssertEqual(SheetSwipe.responder(in: [.ask, .close]), 0, "手前に書きかけが無ければ奥の書きかけを確かめる")
        XCTAssertNil(SheetSwipe.responder(in: [.ask, .hold]), "手前が送っている最中に奥の「保存せずに閉じる」を出す")
        XCTAssertEqual(SheetSwipe.responder(in: [.hold, .ask]), 1)
    }

    /// 🔴 **払って閉じるのを止めるのは必ず `sheetSwipeGuard` を通す**（直に `interactiveDismissDisabled` を書くと、
    /// 払っても跳ね返るだけで何も言わない画面に戻る）
    func testNoScreenBlocksSwipeDirectly() throws {
        let root = sourcesRoot()
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertGreaterThan(files.count, 100)
        var direct: [String] = []
        var guarded = 0
        for file in files {
            let text = code(try String(contentsOf: file, encoding: .utf8))
            if file.lastPathComponent == "SheetSwipeGuard.swift" { continue }
            if text.contains(".interactiveDismissDisabled(") { direct.append(file.lastPathComponent) }
            guarded += text.components(separatedBy: ".sheetSwipeGuard(").count - 1
        }
        XCTAssertEqual(direct, [], "払って閉じるのを直に止めている")
        // 投稿・戻るの確かめ・✕ の確かめ（2）と、送っている最中だけ止めるシート（11）
        XCTAssertEqual(guarded, 14, "払う止め方の数が変わった（増えたなら、払ったときの確かめを渡しているか見る）")
    }

    /// どの画面が確かめを出すか: 書きかけの確かめを持つ画面は、払ったときに **✕・戻ると同じ手** を渡す
    func testDraftScreensPassTheirCloseAction() throws {
        let upload = try source("Features/Upload/UploadView.swift")
        XCTAssertTrue(upload.contains(".sheetSwipeGuard(SheetSwipe.from(leave)) { attemptClose() }"),
                      "投稿画面を払っても閉じる確認が出ない")
        // 左上の「キャンセル」も同じ手
        let cancel = slice(upload, from: "ToolbarItem(placement: .cancellationAction) {", to: ".accessibilityLabel(Labels.Common.cancel)")
        XCTAssertTrue(cancel.contains("attemptClose()"), "「キャンセル」と払うで閉じ方が割れている")
        let attempt = slice(upload, from: "private func attemptClose() {", to: "/// 閉じる確認の中身")
        XCTAssertTrue(attempt.contains("case .confirm:\n            confirmDiscard = true"), "書きかけで閉じる確認を出さない")
        XCTAssertTrue(attempt.contains("model.closeWithoutDraft()"), "書きかけが無いのに片づけずに閉じる")

        let guards = try source("Features/Common/UnsavedLeaveGuard.swift")
        XCTAssertEqual(guards.components(separatedBy: ".sheetSwipeGuard(SheetSwipe.from(leave)) {\n                if leave == .confirm { isPresented.wrappedValue = true }").count - 1, 2,
                       "戻る・✕ の確かめ（`unsavedLeaveGuard`・`unsavedCloseGuard`）が払ったときに確かめを出さない")
        // ✕ の確かめを使う画面（ストーリー作成・写真の編集・ハイライト）・戻るの確かめ（親しい友達・旅行プラン・プロフィール）
        for (file, call) in [("Features/Profile/EditPhotoView.swift", ".unsavedCloseGuard("),
                             ("Features/Profile/HighlightEditorView.swift", ".unsavedCloseGuard("),
                             ("Features/Stories/StoryComposerView.swift", ".unsavedCloseGuard("),
                             ("Features/Social/CloseFriendsView.swift", ".unsavedLeaveGuard("),
                             ("Features/Trips/TripPlanDetailView.swift", ".unsavedLeaveGuard("),
                             ("Features/Profile/ProfileEditView.swift", ".unsavedLeaveGuard(")] {
            XCTAssertTrue(try source(file).contains(call), "\(file) が共通の確かめを使っていない")
        }
    }

    /// 払ったときに出す確かめの言葉は ✕ と同じ（「捨てる」を使わない・何が起きるかで言う）
    func testSwipeDialogWording() throws {
        let upload = try source("Features/Upload/UploadView.swift")
        let dialog = slice(upload, from: ".confirmationDialog(closeTitle, isPresented: $confirmDiscard", to: "} message: {")
        for word in ["L(\"下書きに保存\", \"Save draft\")", "L(\"投稿をやめる\", \"Stop posting\")",
                     "DraftsText.update", "L(\"書き続ける\", \"Keep editing\")"] {
            XCTAssertTrue(dialog.contains(word), "閉じる確認に「\(word)」が無い")
        }
        XCTAssertFalse(dialog.contains("捨て"))
        let guards = try source("Features/Common/UnsavedLeaveGuard.swift")
        XCTAssertTrue(guards.contains("L(\"保存せずに戻る\", \"Go back without saving\")"))
        XCTAssertFalse(guards.contains("L(\"捨て"))
    }

    // MARK: - 投稿画面の下の主ボタン

    func testSubmitTitleCountsPhotos() {
        XCTAssertEqual(UploadSubmitBar.title(count: 3), L("3枚を投稿する", "Post 3 photos"))
        XCTAssertEqual(UploadSubmitBar.title(count: 1), L("投稿する", "Post"))
        XCTAssertEqual(UploadSubmitBar.title(count: 0), L("投稿する", "Post"))
        XCTAssertEqual(UploadSubmitBar.disabledOpacity, 0.32)
    }

    /// 押せない間は理由を下に1行（板 Components 01）。送っている最中・押せるときは出さない
    func testBlockedReason() {
        XCTAssertEqual(UploadSubmitBar.blockedReason(hasPhotos: false, loading: false, working: false),
                       L("写真を選ぶと投稿できます", "Choose a photo to post"))
        XCTAssertEqual(UploadSubmitBar.blockedReason(hasPhotos: true, loading: true, working: false),
                       L("写真を読み込んでいます", "Loading photos"))
        XCTAssertNil(UploadSubmitBar.blockedReason(hasPhotos: true, loading: false, working: false))
        XCTAssertNil(UploadSubmitBar.blockedReason(hasPhotos: true, loading: false, working: true))
    }

    /// 「投稿する」は下の帯の白の主ボタン1つ。右上には置かない（板の投稿画面は上のバーの右を空ける）
    func testSubmitIsTheBottomPrimaryButton() throws {
        let upload = try source("Features/Upload/UploadView.swift")
        XCTAssertTrue(upload.contains(".safeAreaInset(edge: .bottom, spacing: 0) { submitBar }"), "下の帯に主ボタンが無い")
        XCTAssertFalse(upload.contains("ToolbarItem(placement: .confirmationAction)"), "右上に「投稿する」が残っている")
        XCTAssertFalse(upload.contains("submitButton"), "右上の「投稿する」の部品が残っている")
        let bar = slice(upload, from: "private var submitBar: some View {", to: "/// 選んだ写真の帯")
        XCTAssertTrue(bar.contains(".jpPillButton(.primary)"), "主ボタンが白（写真のある画面の主）でない")
        XCTAssertTrue(bar.contains(".jpBottomBar()"), "板の下の帯（黒 55%＋ぼかし）でない")
        XCTAssertTrue(bar.contains("Task { await model.submit() }"))
        XCTAssertTrue(bar.contains(".disabled(!model.canSubmit)"))
        XCTAssertTrue(bar.contains(".accessibilityIdentifier(\"upload.submit\")"), "UI テストが押す名前が無い")
        XCTAssertTrue(bar.contains("UploadSubmitBar.title(count: model.items.count)"))
        XCTAssertEqual(JPPillStyle.primary.height, JPHeight.primaryButton)
        XCTAssertEqual(JPHeight.primaryButton, 50)
    }

    // MARK: - 手伝い

    private func sourcesRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto")
    }

    /// 注記の行を除いた中身
    private func code(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func source(_ path: String) throws -> String {
        code(try String(contentsOf: sourcesRoot().appendingPathComponent(path), encoding: .utf8))
    }

    private func slice(_ text: String, from start: String, to end: String) -> String {
        guard let head = text.range(of: start) else { return "" }
        let rest = text[head.upperBound...]
        guard let tail = rest.range(of: end) else { return String(rest) }
        return String(rest[..<tail.lowerBound])
    }
}
