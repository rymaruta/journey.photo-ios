import XCTest
@testable import JourneyPhoto

/// 点検「人間工学アーティファクト」（2026-11-14）の直し（入力欄の見本の字・探すの押し直し以外）と、
/// 前回の点検（2026-11-13）の残りの直し。画面は Linux で描けないので、値と書いてあるもので固定する
/// （`SheetClosePlacementTests` と同じ作り）。どれも直しを戻すと落ちる
@MainActor
final class ErgonomicsRestTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// `marker` から `length` 字の中身
    private func slice(_ text: String, from marker: String, length: Int = 1500) -> String {
        guard let start = text.range(of: marker) else { return "" }
        return String(text[start.lowerBound...].prefix(length))
    }

    // MARK: - 投稿の終わりの触覚

    /// 全部上がったら成功、送れなかった写真があれば失敗、やめた回・何も送っていない回は鳴らさない
    func testSubmitHapticFollowsTheOutcome() async {
        XCTAssertEqual(UploadViewModel.submitHaptic(posted: 3, failed: 0, cancelled: false), .success)
        XCTAssertEqual(UploadViewModel.submitHaptic(posted: 2, failed: 1, cancelled: false), .failure)
        XCTAssertEqual(UploadViewModel.submitHaptic(posted: 0, failed: 2, cancelled: false), .failure)
        XCTAssertNil(UploadViewModel.submitHaptic(posted: 1, failed: 1, cancelled: true))
        XCTAssertNil(UploadViewModel.submitHaptic(posted: 0, failed: 0, cancelled: false))
    }

    /// 送り終えた所で数を進め、投稿画面がその数で成功・失敗の触覚を1回だけ鳴らす
    func testUploadWiresSubmitHaptics() async throws {
        let model = try source("Features/Upload/UploadViewModel.swift")
        let submit = slice(model, from: "func submit() async {", length: 12000)
        XCTAssertTrue(submit.contains("Self.submitHaptic(posted: done.count, failed: failures.count, cancelled: cancelled)"))
        XCTAssertTrue(submit.contains("postSucceededTicks += 1"))
        XCTAssertTrue(submit.contains("postFailedTicks += 1"))
        let view = try source("Features/Upload/UploadView.swift")
        XCTAssertTrue(view.contains(".sensoryFeedback(.success, trigger: model.postSucceededTicks)"))
        XCTAssertTrue(view.contains(".sensoryFeedback(.error, trigger: model.postFailedTicks)"))
    }

    /// 2026-11-14（追加の点検・HIG Playing haptics）: **いいねには触覚を付けない**（いちばん回数の多い操作。触覚は投稿の完了と失敗だけ）
    func testLikeHasNoHaptic() async throws {
        for path in ["Features/PhotoDetail/PhotoViewerView.swift", "Features/PhotoDetail/PhotoDetailView.swift"] {
            XCTAssertFalse(try source(path).contains("sensoryFeedback"), "\(path) に触覚がある（いいねに付けない）")
        }
    }

    // MARK: - 会話の入力欄と下の札の間

    /// 2026-11-14（追加の点検・HIG Tab bars）: 会話の画面で下の札を**隠さない**。代わりに入力欄の下を 12pt 空ける
    /// （HIG Accessibility「縁のある部品のまわりに約 12pt」。前は 8pt で、送るの丸と札の間が約 10〜15pt）
    func testConversationKeepsTabBarAndLeaves12ptBelowComposer() async throws {
        XCTAssertGreaterThanOrEqual(DMLook.composerBottomGap, 12)
        let dm = try source("Features/Messages/DMConversationView.swift")
        XCTAssertFalse(dm.contains(".toolbar(.hidden, for: .tabBar)"), "会話の画面で下の札を隠している（HIG Tab bars）")
        let composer = slice(dm, from: "private var composer: some View {", length: 4000)
        XCTAssertTrue(composer.contains(".padding(.bottom, DMLook.composerBottomGap)"), "DM の入力欄の下が 12pt でない")
        let trip = try source("Features/Trips/TripShareViews.swift")
        let bar = slice(trip, from: "private var inputBar: some View {", length: 2500)
        XCTAssertTrue(bar.contains(".padding(.bottom, DMLook.composerBottomGap)"), "旅行プランの会話の入力欄の下が 12pt でない")
        XCTAssertFalse(try source("Features/Trips/TripPlanDetailView.swift").contains(".toolbar(.hidden, for: .tabBar)"))
    }

    // MARK: - 送るシートの閉じる

    /// 送るシートにも見出しの左にシートの「閉じる」（投稿の選択の短いシートと同じ・`SheetCloseButton(onContent: true)`）
    func testSendSheetHasCloseOnTheLeft() async throws {
        let text = try source("Features/Common/SendSheet.swift")
        let body = slice(text, from: "var body: some View {", length: 1200)
        let close = try XCTUnwrap(body.range(of: "SheetCloseButton(onContent: true)"))
        let spacer = try XCTUnwrap(body.range(of: "Spacer(minLength: 0)"))
        XCTAssertLessThan(close.lowerBound, spacer.lowerBound, "閉じるが左端にない")
    }

    // MARK: - 探すの人の0件

    /// 人の0件は空の部品（印・明朝の見出し・説明・一手）。打つ前・探している最中・読めなかった・短すぎるは別の文
    func testPeopleNoHitUsesEmptyState() async throws {
        XCTAssertTrue(SearchView.showsPeopleNoHit(query: "ka", searching: false, failed: false, tooShort: false))
        XCTAssertFalse(SearchView.showsPeopleNoHit(query: "", searching: false, failed: false, tooShort: false))
        XCTAssertFalse(SearchView.showsPeopleNoHit(query: "ka", searching: true, failed: false, tooShort: false))
        XCTAssertFalse(SearchView.showsPeopleNoHit(query: "ka", searching: false, failed: true, tooShort: false))
        XCTAssertFalse(SearchView.showsPeopleNoHit(query: "k", searching: false, failed: false, tooShort: true))
        let text = try source("Features/Search/SearchView.swift")
        let branch = slice(text, from: "} else if users.isEmpty, Self.showsPeopleNoHit(", length: 900)
        XCTAssertTrue(branch.contains("EmptyState("))
        XCTAssertTrue(branch.contains("model.select(scope: .all)"), "一手（すべてで探す）が無い")
    }

    // MARK: - 投稿と編集の欄

    /// 欄の名前は投稿も編集も「題」「説明」。編集の撮影地も投稿と同じ枠の欄
    func testUploadAndEditShareFieldNames() async throws {
        let upload = try source("Features/Upload/UploadView.swift")
        XCTAssertTrue(upload.contains("JPField(L(\"題\", \"Title\"))"))
        XCTAssertTrue(upload.contains("JPField(L(\"説明\", \"Description\"), multiline: true)"))
        XCTAssertFalse(upload.contains("L(\"タイトル\""))
        XCTAssertFalse(upload.contains("L(\"説明文\""))
        let edit = try source("Features/Profile/EditPhotoView.swift")
        XCTAssertTrue(edit.contains("JPField(L(\"題\", \"Title\"))"))
        XCTAssertTrue(edit.contains("JPField(L(\"説明\", \"Description\"), multiline: true)"))
        XCTAssertTrue(edit.contains("PlaceSearchField(location: $location, coords: $pickedCoords, boxed: true)"))
    }

    // MARK: - 旅行プラン

    /// 日付の選択: 端の日は白 94% の丸に墨、間の日は白 8% の帯（真鍮の塗りの丸にしない・板 04）
    func testTripCalendarSelectionIsWhite() async throws {
        let text = try source("Features/Trips/TripCreateView.swift")
        XCTAssertTrue(text.contains("static let endFill = WebTheme.accentBackground"))
        XCTAssertTrue(text.contains("static let insideFill = Color.white.opacity(0.08)"))
        let cell = slice(text, from: "private func cell(_ day: String) -> some View {", length: 1600)
        XCTAssertTrue(cell.contains("Circle().fill(Self.endFill)"))
        XCTAssertTrue(cell.contains("Rectangle().fill(Self.insideFill)"))
        XCTAssertFalse(cell.contains("WebTheme.accentFill"), "端の日が真鍮の塗りのまま")
        XCTAssertFalse(cell.contains("WebTheme.accent.opacity"), "間の日が真鍮の帯のまま")
    }

    /// 見本の「送った回数 / lift=…」は画面に字で出さず、見えない要素の値だけ（UI テストは値で読む）
    func testTripFixtureCountsAreInvisible() async throws {
        let text = try source("Features/Trips/TripPlanDetailView.swift")
        let label = slice(text, from: "private struct TripPlanFixtureSendsLabel: View {", length: 2200)
        XCTAssertFalse(label.contains("Text(L(\"送った回数"), "送った回数が画面に字で出る")
        XCTAssertFalse(label.contains("Text(counter.dragLine)"))
        XCTAssertTrue(label.contains(".foregroundStyle(Color.clear)"))
        for id in ["tripPlan.fixtureSends", "tripPlan.fixtureDrag", "tripPlan.fixtureDragTrail"] {
            XCTAssertTrue(label.contains("\"\(id)\""), "UI テストが読む \(id) が無い")
        }
        XCTAssertTrue(text.contains(".overlay(alignment: .topLeading) { fixtureSendsLabel }"), "並びの中に置いていて高さを取る")
    }

    // MARK: - 言葉と色

    /// メニューも「光と天気の知らせ」（押した先の題・設定の行と同じ）
    func testMenuNamesLightAlertsLikeItsScreen() async throws {
        let menu = try source("Features/Common/SiteMenuView.swift")
        XCTAssertTrue(menu.contains("SiteMenuRow(title: L(\"光と天気の知らせ\""))
        XCTAssertFalse(menu.contains("L(\"光と天気の予報\""))
    }

    /// すれちがいの注意は text-2 の字に注意の印（真鍮にしない・板 04「警告は白＋アイコン」）
    func testPassWarningIsNotBrass() async throws {
        XCTAssertEqual(PassSettingsView.warningSymbol, "exclamationmark.triangle")
        let text = try source("Features/Pass/PassSettingsView.swift")
        XCTAssertTrue(text.contains("static let warningColor = WebTheme.text2"))
        let when = slice(text, from: "private var whenSection: some View {", length: 2200)
        XCTAssertFalse(when.contains(".foregroundStyle(WebTheme.accent)"), "注意の文が真鍮のまま")
        XCTAssertTrue(when.contains("NavigationLink { ProfileEditView() }"), "居住地を入れる道が無い")
    }

    /// 探すの観光スポットの段の眉は「SPOTS」（「PHOTO SPOTS」は前の呼び名）
    func testSpotIndexEyebrow() async throws {
        XCTAssertEqual(SearchSpotIndexSection.eyebrow, "SPOTS")
        XCTAssertFalse(try source("Features/Search/SearchSpotIndexSection.swift").contains("\"PHOTO SPOTS\""))
    }

    /// ストーリーハイライトの見出しは眉ラベル（板 06「段の見出しは眉ラベル」・すぐ上の旅の記録と同じ）
    func testHighlightsHeadingIsEyebrow() async throws {
        let text = try source("Features/Profile/HighlightsRow.swift")
        let header = slice(text, from: "private var header: some View {", length: 800)
        XCTAssertTrue(header.contains("JPEyebrowLine(L(\"ストーリーハイライト\""))
        XCTAssertFalse(header.contains("JPFont.footnote.weight(.semibold)"))
    }

    /// 退会した人との会話の「会話を削除」は危険の線のボタン（赤の字）
    func testDeletedPeerRemoveIsDanger() async throws {
        let text = try source("Features/Messages/DMConversationView.swift")
        let footer = slice(text, from: "private var footer: some View {", length: 1500)
        XCTAssertTrue(footer.contains("jpOutlineButton(.regular, tone: .danger, fullWidth: true)"))
        XCTAssertFalse(footer.contains("jpPillButton(.outline)"))
    }
}
