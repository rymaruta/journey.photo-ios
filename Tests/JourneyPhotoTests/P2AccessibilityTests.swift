import XCTest
@testable import JourneyPhoto

/// 完成度レビューの P2 の残り（2026-10-17）。
///
/// 1. 写真の編集の「編集前と比べる」を読み上げ（VoiceOver）でも使える
/// 2. 投稿・編集のタグとカテゴリの札は、見た目 32・当たり 44
/// 3. 写真の編集画面の字が文字の大きさの設定に付いてくる・入力欄の縁が見える
/// 4. 空の画面の次の一手（行き先がはっきりしている所だけ）
///
/// 画面は Linux で描けないので、判断は値で、配線は元のコードを読んで確かめる
@MainActor
final class P2AccessibilityTests: XCTestCase {

    // MARK: - 道具

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path),
                              encoding: .utf8)
        // 注記（`//`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    // MARK: - 1. 読み上げで編集前と比べる

    /// 操作を押すたびに編集前と編集後が入れ替わり、操作の名前も入れ替わる
    func testAccessibilityActionTogglesTheOriginal() async {
        var screen = PhotoEditScreen(original: PhotoRecipe(exposure: 0.4))
        XCTAssertFalse(screen.showsBeforeLabel)
        XCTAssertEqual(screen.compareActionName, "編集前を見る")
        screen.toggleCompare()
        XCTAssertTrue(screen.showsBeforeLabel, "操作で編集前が出ない")
        XCTAssertEqual(screen.displayed, .identity, "出すのは元の写真（無編集）")
        XCTAssertEqual(screen.compareActionName, "編集後に戻す")
        XCTAssertEqual(screen.compareAnnouncement, "編集前の写真を表示しています")
        screen.toggleCompare()
        XCTAssertFalse(screen.showsBeforeLabel, "もう一度の操作で編集後に戻らない")
        XCTAssertEqual(screen.displayed, screen.current)
        XCTAssertEqual(screen.compareAnnouncement, "編集後の写真を表示しています")
    }

    /// 🔴 **操作で編集前を出したまま編集したら、編集後に戻す**（写真が動かず「効かない」と取り違える）
    func testEditingEndsTheActionComparison() async {
        var screen = PhotoEditScreen()
        screen.toggleCompare()
        screen.dragAdjustment(30)
        XCTAssertFalse(screen.showsBeforeLabel, "つまみを動かしても編集前のまま")
        screen.endDrag()

        screen.toggleCompare()
        screen.selectPreset(PhotoPresets.all[0].id)
        XCTAssertFalse(screen.showsBeforeLabel, "プリセットを選んでも編集前のまま")

        screen.toggleCompare()
        screen.dragStrength(40)
        XCTAssertFalse(screen.showsBeforeLabel, "強さを動かしても編集前のまま")
        screen.endDrag()

        screen.toggleCompare()
        screen.undo()
        XCTAssertFalse(screen.showsBeforeLabel, "取り消しても編集前のまま")

        screen.toggleCompare()
        screen.redo()
        XCTAssertFalse(screen.showsBeforeLabel, "やり直しても編集前のまま")

        screen.adjustment = .exposure
        screen.dragAdjustment(20)
        screen.endDrag()
        screen.toggleCompare()
        screen.resetAdjustment()
        XCTAssertFalse(screen.showsBeforeLabel, "0に戻しても編集前のまま")
    }

    /// 指の長押しは今までどおり: 長押しの最中に（二本指で）つまみを動かしても、離すまで編集前
    func testLongPressIsUnchangedByTheAction() async {
        var screen = PhotoEditScreen()
        let t0 = Date(timeIntervalSince1970: 1000)
        screen.press(.began(at: t0))
        screen.press(.tick(now: t0.addingTimeInterval(PhotoEditScreen.holdDelay)))
        XCTAssertTrue(screen.showsBeforeLabel)
        screen.dragAdjustment(10)
        XCTAssertTrue(screen.showsBeforeLabel, "長押しの比べまで編集で止まった")
        screen.press(.ended)
        XCTAssertFalse(screen.showsBeforeLabel)

        // 操作で出したあと指で触れて離しても、編集前は残らない
        screen.toggleCompare()
        screen.press(.began(at: t0.addingTimeInterval(5)))
        screen.press(.ended)
        XCTAssertFalse(screen.showsBeforeLabel)
        XCTAssertFalse(screen.comparingByAction)
    }

    /// 写真に読み上げの操作が付いている。指の長押し（距離 0 の DragGesture）はそのまま
    func testPhotoHasTheAccessibilityAction() async throws {
        let view = try source("Features/Upload/PhotoEditView.swift")
        XCTAssertTrue(view.contains(".accessibilityAction(named: screen.compareActionName) {\n                screen.toggleCompare()"),
                      "写真に読み上げの操作が無い")
        XCTAssertTrue(view.contains("UIAccessibility.post(notification: .announcement, argument: screen.compareAnnouncement)"))
        XCTAssertTrue(view.contains("DragGesture(minimumDistance: 0)"), "指の長押しの作りが変わった")
    }

    // MARK: - 2. タグとカテゴリの札の当たり

    func testFormChipIsVisually32AndTaps44() async {
        XCTAssertEqual(FormChip.height, 32)
        XCTAssertEqual(FormChip.height + FormChip.tapSlack * 2, WebTheme.minTapTarget)
        XCTAssertEqual(FormChip.lineSpacing, 0)
        XCTAssertEqual(FormChip.spacing, 6)
        // 🔴 1文字の札（字 12＋左右 10 ≈ 32）でも、当たりの幅は 44 以上
        XCTAssertEqual(FormChip.minWidth, 38)
        let oneChar: CGFloat = 12 + 10 * 2
        XCTAssertGreaterThanOrEqual(max(oneChar, FormChip.minWidth) + FormChip.sideSlack * 2, WebTheme.minTapTarget,
                                    "1文字の札の当たりの幅が 44 に届かない")
    }

    /// 🔴 **当たりの箱（44）が隣の行と重ならない。** 重なると、下の行の札が上の札の押し下げを奪う
    func testChipRowsDoNotOverlap() async {
        let box = CGSize(width: 60, height: FormChip.height + FormChip.tapSlack * 2)
        let placed = FlowLayout.arrange(Array(repeating: box, count: 7), width: 200,
                                        spacing: FormChip.spacing, lineSpacing: FormChip.lineSpacing)
        let rows = Set(placed.origins.map(\.y)).sorted()
        XCTAssertEqual(rows, [0, 44, 88], "行の間が当たりの高さになっていない")
        XCTAssertEqual(placed.size.height, 132)
        // 同じ行の札は左右 6 ずつ空く
        XCTAssertEqual(placed.origins[1].x - placed.origins[0].x, 60 + FormChip.spacing)
    }

    /// ほかの並び（写真の詳細のタグ）は今のまま（行の間 = 左右の間）
    func testFlowLayoutDefaultKeepsLineSpacing() async {
        XCTAssertNil(FlowLayout(spacing: 6).lineSpacing)
        let placed = FlowLayout.arrange(Array(repeating: CGSize(width: 60, height: 26), count: 4), width: 130,
                                        spacing: 6, lineSpacing: 6)
        XCTAssertEqual(placed.origins.map(\.y), [0, 0, 32, 32])
        XCTAssertEqual(placed.size, CGSize(width: 126, height: 58))
    }

    func testTagAndCategoryFieldsUseTheChipFace() async throws {
        for file in ["Features/Common/TagField.swift", "Features/Common/CategoryField.swift"] {
            let code = try source(file)
            XCTAssertTrue(code.contains("FlowLayout(spacing: FormChip.spacing, lineSpacing: FormChip.lineSpacing)"),
                          "\(file) の行の間が当たりに合っていない")
            XCTAssertTrue(code.contains(".formChipFace(fill: chosen ? WebTheme.accentBackground : WebTheme.surface)"),
                          "\(file) の札が 44 の当たりを持たない")
            XCTAssertFalse(code.contains(".padding(-Self.tapSlack)"), "\(file) が前の 3pt だけの当たりに戻っている")
        }
        let face = try source("Features/Common/TagField.swift")
        XCTAssertTrue(face.contains(".frame(minWidth: FormChip.minWidth, minHeight: FormChip.height)"),
                      "1文字の札の当たりの幅が 44 に届かない")
        XCTAssertTrue(face.contains(".padding(.vertical, FormChip.tapSlack)\n"))
    }

    // MARK: - 3. 写真の編集画面の字・入力欄の縁

    /// 🔴 **写真の編集画面の字は文字の大きさの設定に付いてくる**（`.system(size:)` の固定を残さない）
    func testPhotoEditTextFollowsDynamicType() async throws {
        let code = try source("Features/Upload/PhotoEditView.swift")
        let fixed = code.components(separatedBy: "\n").enumerated()
            .filter { $0.element.contains(".system(size:") }
            .map { "\($0.offset + 1)行" }
        XCTAssertTrue(fixed.isEmpty, "固定の大きさの字が残っている: " + fixed.joined(separator: ", "))
        XCTAssertTrue(code.contains(".dynamicTypeSize(...Self.typeLimit)"), "大きすぎる段で写真を押しつぶす")
        XCTAssertTrue(code.contains(".frame(minHeight: Self.panelHeight, alignment: .top)"),
                      "道具の段が固定の高さのままで、大きな字がはみ出す")
        XCTAssertGreaterThanOrEqual(PhotoEditView.typeLimit, .xxLarge, "上限が小さすぎる")
        XCTAssertEqual(PhotoEditView.panelHeight, 150)
    }

    /// 🔴 **入力欄の縁は `outline`（部品の縁の 3:1）。** 白 12%（`border`）は黒の上で 1.27 で、欄が見えない
    func testInputFieldBordersAreVisible() async throws {
        let parts = try source("Core/Design/FormParts.swift")
        guard let start = parts.range(of: "struct JPField<Content: View>: View {"),
              let end = parts.range(of: "enum JPPillStyle") else { return XCTFail("JPField が無い") }
        let field = String(parts[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(field.contains(".strokeBorder(WebTheme.outline, lineWidth: 1)"), "見出し付きの欄の縁が薄い")
        XCTAssertFalse(field.contains("WebTheme.border"))

        let edit = try source("Features/Profile/EditPhotoView.swift")
        XCTAssertTrue(edit.contains(".strokeBorder(WebTheme.outline, lineWidth: 1)"), "撮影日の欄の縁が薄い")
        XCTAssertFalse(edit.contains("strokeBorder(WebTheme.border"))
    }

    // MARK: - 4. 空の画面の次の一手

    func testEmptyStatesWithAClearDestinationOfferIt() async throws {
        let favorites = try source("Features/Profile/FavoritesView.swift")
        XCTAssertTrue(favorites.contains(
            "actionTitle: MyPageEmpty.browseTitle, actionIdentifier: \"favorites.emptyBrowse\") {\n                        TabRouter.shared.openHome()"),
            "いいね0枚にホームへの一手が無い")

        let saved = try source("Features/Profile/SavedPhotosView.swift")
        XCTAssertTrue(saved.contains(
            "actionTitle: MyPageEmpty.browseTitle, actionIdentifier: \"savedPhotos.emptyBrowse\") {\n                        TabRouter.shared.openHome()"),
            "保存0枚にホームへの一手が無い")

        let offline = try source("Features/Trips/OfflineSavedView.swift")
        XCTAssertTrue(offline.contains(
            "actionTitle: Self.openPlansTitle, actionIdentifier: \"offlineSaved.emptyPlans\") {\n                        showPlans = true"),
            "保存した旅0件に旅行プランへの一手が無い")
        XCTAssertTrue(offline.contains(".navigationDestination(isPresented: $showPlans) { TripPlansView() }"))
        XCTAssertEqual(OfflineSavedView.openPlansTitle, "旅行プランを開く")
        XCTAssertEqual(MyPageEmpty.browseTitle, "写真を見に行く")
    }
}
