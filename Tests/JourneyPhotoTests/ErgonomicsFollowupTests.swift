import Foundation
import XCTest
@testable import JourneyPhoto

/// 人間工学の点検「追加の点検」2〜5（2026-11-14・Artifact「人間工学アーティファクト」）の直しを見張る。
///
/// - 2: 送っていない変更がある間の自前の戻るも、標準と同じ丸い矢印（題を添えない）
/// - 3: 「コントラストを上げる」がオンのときだけ text-3・髪線・見本の字を濃くする（ふだんの値は変えない）
/// - 4: 文字の大きさの上限は写真の上の字・大きくできない帯だけに残し、そこは長押しで大きく見せる
/// - 5: 画面の角の「閉じる」「×」は、見た目はそのまま当たりを角の側へ 60pt 四方まで広げる
///
/// 画面は Linux で描けないので、決まりの値（純な関数）とソースの形を見る。本物の当たり・見た目は
/// UI テスト（`ScreenshotTests.testCornerTapArea…`・`…LargestText`）が Mac で確かめる
final class ErgonomicsFollowupTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto").appendingPathComponent(path),
                          encoding: .utf8)
    }

    // MARK: - 5. 角の当たり

    /// 左上の物は、見た目の右下の角を残して左と上へ伸ばす（内側＝右・下の隣の物へは伸ばさない）
    func testCornerHitRectGrowsTowardTheTopLeadingCorner() {
        let rect = CGRect(x: 0, y: 0, width: 44, height: 44)
        let hit = CornerTapArea.hitRect(rect, corner: .topLeading)
        XCTAssertEqual(hit, CGRect(x: -16, y: -16, width: 60, height: 60))
        XCTAssertEqual(hit.maxX, rect.maxX, "内側（右）へ伸びている")
        XCTAssertEqual(hit.maxY, rect.maxY, "下へ伸びている")
    }

    /// 右上の物は、見た目の左下の角を残して右と上へ伸ばす
    func testCornerHitRectGrowsTowardTheTopTrailingCorner() {
        let rect = CGRect(x: 0, y: 0, width: 44, height: 44)
        let hit = CornerTapArea.hitRect(rect, corner: .topTrailing)
        XCTAssertEqual(hit, CGRect(x: 0, y: -16, width: 60, height: 60))
        XCTAssertEqual(hit.minX, rect.minX, "内側（左）へ伸びている")
        XCTAssertEqual(hit.maxY, rect.maxY, "下へ伸びている")
    }

    /// もとが 60 より大きい物（「閉じる」の字のガラス 84×44 など）は、足りない向きだけ伸ばす
    func testCornerHitRectKeepsWideButtons() {
        let hit = CornerTapArea.hitRect(CGRect(x: 0, y: 0, width: 84, height: 44), corner: .topLeading)
        XCTAssertEqual(hit, CGRect(x: 0, y: -16, width: 84, height: 60))
        XCTAssertEqual(CornerTapArea.side, 60)
    }

    /// 画面の角の「閉じる」「×」は、どれも共通の当たり（`cornerTapArea`）を使う。1か所でも前の円・44 の四角に戻ると落ちる
    func testCornerButtonsUseTheSharedCornerTapArea() throws {
        let expected: [(file: String, corner: String, count: Int)] = [
            ("Features/PhotoDetail/PhotoViewerView.swift", ".cornerTapArea(.topLeading)", 1),   // 写真を大きく見るの ×
            ("Features/Trips/DevelopView.swift", ".cornerTapArea(.topLeading)", 2),             // 現像の ×（払う画面・表紙）
            ("Features/Common/SheetCloseButton.swift", ".cornerTapArea(.topLeading)", 1),       // バーの外の「閉じる」
            ("Features/Stories/StoryCameraView.swift", ".cornerTapArea(.topLeading)", 2),
            ("Features/Stories/StoryComposerView.swift", ".cornerTapArea(.topLeading)", 2),
            ("Features/Spots/ComposeGuideView.swift", "roundIcon(\"xmark\", corner: .topLeading)", 1),
            ("Features/Stories/StoryViewerView.swift", ".cornerTapArea(.topTrailing)", 1),       // ストーリーの ×
            ("Features/Profile/HighlightPlayerView.swift", ".cornerTapArea(.topTrailing)", 1),
            ("Features/Stories/YearAgoStoryView.swift", ".cornerTapArea(.topTrailing)", 1),
            ("Features/Profile/MedalViewerView.swift", ".cornerTapArea(.topTrailing)", 1),
            ("Features/Trunk/TrunkSpinViewer.swift", ".cornerTapArea(.topTrailing)", 1),
            ("Features/Pro/SupporterCardView.swift", ".cornerTapArea(.topTrailing)", 1),
            ("Features/Pro/PaywallView.swift", ".cornerTapArea(.topTrailing)", 1),
            ("Features/Pass/PassCards.swift", ".cornerTapArea(.topTrailing)", 1),
            ("Features/Trips/OfflineTripView.swift", ".cornerTapArea(.topTrailing)", 1),
        ]
        for item in expected {
            let code = try source(item.file)
            XCTAssertEqual(code.components(separatedBy: item.corner).count - 1, item.count,
                           "\(item.file) の角の物が共通の当たり（\(item.corner)）を使っていない")
        }
        // 写真を大きく見るの × は、前の円の当たり（44 の丸）に戻らない
        let viewer = try source("Features/PhotoDetail/PhotoViewerView.swift")
        guard let close = viewer.range(of: "accessibilityIdentifier(\"viewer.close\")") else { return XCTFail("× が無い") }
        let before = viewer[viewer.index(close.lowerBound, offsetBy: -600)..<close.lowerBound]
        XCTAssertFalse(before.contains(".contentShape(Circle())"), "大きく見るの × が 44 の丸の当たりに戻っている")
    }

    // MARK: - 2. 戻るの形

    /// 自前の戻るは題を添えない（標準の戻ると同じ丸い矢印）。題を渡す口ごと無い
    func testUnsavedLeaveBackHasNoTitle() throws {
        let guardCode = try source("Features/Common/UnsavedLeaveGuard.swift")
        XCTAssertFalse(guardCode.contains("backTitle: String"), "自前の戻るに題を添える口が戻っている")
        XCTAssertFalse(guardCode.contains("Text(backTitle)"), "自前の戻るに題を添えている")
        XCTAssertTrue(guardCode.contains(".accessibilityLabel(L(\"戻る\", \"Back\"))"), "戻るの読み上げが「戻る」でない")
        XCTAssertTrue(guardCode.contains("accessibilityIdentifier(\"unsavedLeave.back\")"))
        for file in ["Features/Trips/TripPlanDetailView.swift", "Features/Profile/ProfileEditView.swift"] {
            XCTAssertFalse(try source(file).contains("backTitle:"), "\(file) が戻るに題を渡している")
        }
    }

    // MARK: - 3. コントラストを上げる

    /// オンのときの値と比（WCAG 2.x）。ふだんの値（板）は変えない
    func testIncreasedContrastValues() {
        let boost = BrandPalette.IncreasedContrast.self
        // 注記の字: text-3（黒 7.46）→ text-2（黒 10.59）
        XCTAssertEqual(boost.text3, BrandPalette.text2)
        XCTAssertEqual(BrandPalette.contrast(BrandPalette.text3, BrandPalette.background), 7.46, accuracy: 0.01)
        XCTAssertEqual(BrandPalette.contrast(boost.text3, BrandPalette.background), 10.59, accuracy: 0.01)
        // 髪線: 白 8%（黒 1.14）→ 白 20%（黒 1.66）
        XCTAssertEqual(boost.normalHairlineOpacity, 0.08)
        XCTAssertEqual(boost.hairlineOpacity, 0.20)
        let hairNormal = BrandPalette.contrast(boost.whiteOver(BrandPalette.background, opacity: 0.08), BrandPalette.background)
        let hairHigh = BrandPalette.contrast(boost.whiteOver(BrandPalette.background, opacity: 0.20), BrandPalette.background)
        XCTAssertEqual(hairNormal, 1.14, accuracy: 0.01)
        XCTAssertEqual(hairHigh, 1.66, accuracy: 0.01)
        // 見本の字: 入力欄（surface-2）の上で 白 50%（5.31）→ 白 62%（7.43）
        XCTAssertEqual(boost.normalPlaceholderOpacity, 0.5)
        XCTAssertEqual(boost.placeholderOpacity, 0.62)
        let phNormal = BrandPalette.contrast(boost.whiteOver(BrandPalette.surface2, opacity: 0.5), BrandPalette.surface2)
        let phHigh = BrandPalette.contrast(boost.whiteOver(BrandPalette.surface2, opacity: 0.62), BrandPalette.surface2)
        XCTAssertEqual(phNormal, 5.31, accuracy: 0.01)
        XCTAssertEqual(phHigh, 7.43, accuracy: 0.01)
        XCTAssertGreaterThan(phHigh, phNormal)
    }

    /// 切り替えは `WebTheme` の3つの値の1か所だけ。端末の「コントラストを上げる」（`accessibilityContrast == .high`）を読む
    func testWebThemeSwitchesOnIncreasedContrast() throws {
        let theme = try source("Core/Design/WebTheme.swift")
        XCTAssertTrue(theme.contains("static let text3 = contrastAware("), "text-3 が設定に付いてこない")
        XCTAssertTrue(theme.contains("static let hairline = contrastAware("), "髪線が設定に付いてこない")
        XCTAssertTrue(theme.contains("static let placeholder = contrastAware("), "見本の字が設定に付いてこない")
        XCTAssertTrue(theme.contains("traits.accessibilityContrast == .high ? increased : normal"),
                      "「コントラストを上げる」を読んでいない")
    }

    // MARK: - 4. 文字の大きさの上限

    /// 撮影情報の升: ふだんは1段、アクセシビリティの大きさでは2列ずつ
    func testSettingsRowsStackAtAccessibilitySizes() {
        XCTAssertEqual(PhotoMetaLine.settingsRows(count: 4, accessibilitySize: false), [[0, 1, 2, 3]])
        XCTAssertEqual(PhotoMetaLine.settingsRows(count: 4, accessibilitySize: true), [[0, 1], [2, 3]])
        XCTAssertEqual(PhotoMetaLine.settingsRows(count: 3, accessibilitySize: true), [[0, 1], [2]])
        XCTAssertEqual(PhotoMetaLine.settingsRows(count: 0, accessibilitySize: true), [])
        XCTAssertEqual(PhotoMetaLine.settingsColumns(count: 4, accessibilitySize: false), 4)
        XCTAssertEqual(PhotoMetaLine.settingsColumns(count: 3, accessibilitySize: true), 2)
        XCTAssertEqual(PhotoMetaLine.settingsColumns(count: 1, accessibilitySize: true), 1)
    }

    /// 上限を外した所（ボタン・説明の字）に上限が戻っていない
    func testCapsAreRemovedFromButtonsAndExplanations() throws {
        let story = try source("Features/Stories/StoryViewerView.swift")
        XCTAssertFalse(story.contains(".dynamicTypeSize(...DynamicTypeSize.accessibility1)"),
                       "ストーリーの「…」のシート・削除の確認に上限が戻っている")
        XCTAssertTrue(story.contains("ScrollView { panel }"), "「…」のシートが入りきらない大きさで送れない")
        XCTAssertTrue(story.contains("ScrollView { card.padding(.vertical, JPSpace.m) }"), "削除の確認が入りきらない大きさで送れない")

        let detail = try source("Features/PhotoDetail/PhotoDetailView.swift")
        XCTAssertFalse(detail.contains(".dynamicTypeSize(...DynamicTypeSize.xxxLarge)"), "撮影情報の升に上限が戻っている")
        XCTAssertTrue(detail.contains("PhotoMetaLine.settingsRows(count: cells.count, accessibilitySize: accessibility)"))

        let edit = try source("Features/Upload/PhotoEditView.swift")
        // 画面まるごとの上限（本文の VStack の後ろ）に戻っていない
        XCTAssertFalse(edit.contains(".padding(.top, 10)\n        }\n        .dynamicTypeSize(...Self.typeLimit)"),
                       "写真の編集の画面まるごとに上限が戻っている")
        // 上限を外した数の欄は、字が伸びたら幅も伸びる
        XCTAssertFalse(edit.contains(".frame(width: 34, alignment: .trailing)"))
        XCTAssertFalse(edit.contains(".frame(width: 44, alignment: .trailing)"))
    }

    /// 上限を残した所の押せる字は、長押しで大きく見せる（Large Content Viewer）
    func testCappedControlsShowTheLargeContentViewer() throws {
        let lcv = ".accessibilityShowsLargeContentViewer()"
        let checks: [(String, Int)] = [
            ("Features/Stories/StoryViewerView.swift", 4),   // 名前・送りました・写真を見る・読み直す
            ("Features/Upload/PhotoEditView.swift", 5),      // キャンセル・完了・元の写真・フィルム・調整
            ("Features/Stories/StoriesRow.swift", 1),        // 輪の名前
        ]
        for (file, count) in checks {
            let code = try source(file)
            XCTAssertGreaterThanOrEqual(code.components(separatedBy: lcv).count - 1, count,
                                        "\(file) の上限を残した押せる字に、長押しで大きく見せる仕組みが無い")
        }
    }

    /// 束の画面の上限は `PassViewerTypeLimit` の1か所で決める（画面は上限の1行だけ）。見本の差し替えの鍵も読める
    func testPassViewerTypeLimitIsDecidedInOnePlace() throws {
        XCTAssertEqual(PassViewerView.typeLimit, PassViewerTypeLimit.decided)
        XCTAssertEqual(PassViewerTypeLimit.parse("ax3"), .accessibility3)
        XCTAssertEqual(PassViewerTypeLimit.parse("AX5"), .accessibility5)
        XCTAssertEqual(PassViewerTypeLimit.parse("xxxl"), .xxxLarge)
        XCTAssertNil(PassViewerTypeLimit.parse("huge"))
        XCTAssertNil(PassViewerTypeLimit.parse(nil))
        let viewer = try source("Features/Pass/PassViewerView.swift")
        XCTAssertTrue(viewer.contains("static let typeLimit: DynamicTypeSize = PassViewerTypeLimit.value"))
    }
}
