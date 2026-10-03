import XCTest
@testable import JourneyPhoto

/// 写真の編集画面の状態（`PhotoEditScreen`）と、投稿画面との決まり（`PhotoEditBadge`・`UploadEditRules`）、
/// 描画の順番待ち（`LatestOnlyQueue`）。どれも純関数なので Linux で走る（Phase 2・2026-10-02）
final class PhotoEditScreenTests: XCTestCase {

    typealias Adjustment = PhotoEditScreen.Adjustment

    // MARK: - つまみ ↔ レシピ

    func testSliderMapsToRecipeRanges() {
        // 露出は ±100 → ±2EV、ほかは ±100 → ±1
        XCTAssertEqual(Adjustment.exposure.recipeValue(slider: 50), 1, accuracy: 1e-9)
        XCTAssertEqual(Adjustment.exposure.recipeValue(slider: -100), -2, accuracy: 1e-9)
        XCTAssertEqual(Adjustment.contrast.recipeValue(slider: -30), -0.3, accuracy: 1e-9)
        XCTAssertEqual(Adjustment.shadows.recipeValue(slider: 250), 1, accuracy: 1e-9, "幅の外は端に収める")
        XCTAssertEqual(Adjustment.saturation.recipeValue(slider: .nan), 0, "NaN は無変更")
        // 往復
        for item in Adjustment.allCases {
            let recipe = item.setting(item.recipeValue(slider: 37), in: .identity)
            XCTAssertEqual(item.sliderValue(in: recipe), 37, accuracy: 1e-9, item.rawValue)
        }
    }

    func testOnlyTheChosenFieldMoves() {
        var screen = PhotoEditScreen()
        screen.adjustment = .temperature
        screen.dragAdjustment(40)
        screen.endDrag()
        XCTAssertEqual(screen.current, PhotoRecipe(temperature: 0.4))
    }

    func testChangedMarkAndSpokenLabel() {
        let recipe = PhotoRecipe(exposure: 0.5)
        XCTAssertTrue(Adjustment.exposure.isChanged(in: recipe))
        XCTAssertFalse(Adjustment.contrast.isChanged(in: recipe))
        XCTAssertEqual(Adjustment.exposure.accessibilityLabel(changed: true), "露出・変えてあります")
        XCTAssertEqual(Adjustment.exposure.accessibilityLabel(changed: false), "露出")
        // つまみの表示で 0 に丸まる小ささは「変えていない」（点が付いたのに 0 と出さない）
        XCTAssertFalse(Adjustment.contrast.isChanged(in: PhotoRecipe(contrast: 0.004)))
    }

    func testValueText() {
        XCTAssertEqual(PhotoEditScreen.valueText(12), "+12")
        XCTAssertEqual(PhotoEditScreen.valueText(0), "0")
        XCTAssertEqual(PhotoEditScreen.valueText(-5), "−5")
        XCTAssertEqual(PhotoEditScreen.valueText(-0.4), "0", "−0 と出さない")
    }

    // MARK: - 指を離したら1手（preview / commit）

    func testDragIsOneStepWhenReleased() {
        var screen = PhotoEditScreen()
        screen.adjustment = .contrast
        for value in stride(from: 1.0, through: 60, by: 1) { screen.dragAdjustment(value) }
        screen.endDrag()
        XCTAssertEqual(screen.current.contrast, 0.6, accuracy: 1e-9)
        screen.undo()
        XCTAssertEqual(screen.current, .identity, "途中の値を積まず、1回の取り消しで戻る")
        XCTAssertFalse(screen.canUndo)
        XCTAssertTrue(screen.canRedo)
    }

    func testFinishedIncludesAnUnreleasedDrag() {
        var screen = PhotoEditScreen()
        screen.dragAdjustment(20)
        XCTAssertEqual(screen.finished.exposure, 0.4, accuracy: 1e-9)
    }

    func testResetAdjustmentIsOneUndoableStep() {
        var screen = PhotoEditScreen(original: PhotoRecipe(exposure: 1, contrast: 0.2))
        screen.adjustment = .exposure
        screen.resetAdjustment()
        XCTAssertEqual(screen.current, PhotoRecipe(contrast: 0.2), "選んでいる項目だけ 0 に")
        screen.undo()
        XCTAssertEqual(screen.current.exposure, 1, accuracy: 1e-9)
        // 0 の項目で押しても手を増やさない
        screen.adjustment = .shadows
        screen.resetAdjustment()
        XCTAssertFalse(screen.canUndo)
    }

    // MARK: - フィルム

    func testPresetStartsAt80AndKeepsAdjustments() {
        var screen = PhotoEditScreen(original: PhotoRecipe(exposure: 0.5))
        screen.selectPreset("dusk")
        XCTAssertEqual(screen.current.preset, .init(id: "dusk", strength: 0.8))
        XCTAssertEqual(screen.strengthSlider, 80)
        XCTAssertEqual(screen.current.exposure, 0.5, accuracy: 1e-9, "調整はプリセットの上に足したまま")
        screen.selectPreset("dusk")
        screen.undo()
        XCTAssertNil(screen.current.preset, "同じものを押し直しても手を増やさない")
        screen.redo()
        screen.selectPreset(nil)
        XCTAssertNil(screen.current.preset)
        XCTAssertNil(screen.strengthSlider, "なしでは強さを出さない")
        XCTAssertEqual(screen.current.exposure, 0.5, accuracy: 1e-9)
    }

    func testStrengthDrag() {
        var screen = PhotoEditScreen()
        screen.dragStrength(30)
        XCTAssertNil(screen.current.preset, "プリセットが無ければ何もしない")
        screen.selectPreset("sumi")
        screen.dragStrength(45)
        screen.dragStrength(25)
        screen.endDrag()
        XCTAssertEqual(screen.current.preset?.strength ?? -1, 0.25, accuracy: 1e-9)
        screen.undo()
        XCTAssertEqual(screen.current.preset?.strength ?? -1, 0.8, accuracy: 1e-9)
    }

    // MARK: - 長押しで比べる

    private let t0 = Date(timeIntervalSince1970: 1_000)

    /// 長押しと認めたら**元の写真（無編集）**を、指を離すまで出す（owner の Before/After）
    func testLongPressShowsTheUneditedPhotoUntilReleased() {
        var screen = PhotoEditScreen(original: PhotoRecipe(exposure: 0.2))
        screen.selectPreset("haze")
        screen.press(.began(at: t0))
        XCTAssertFalse(screen.showsBeforeLabel, "触れただけでは比べない")
        screen.press(.tick(now: t0.addingTimeInterval(PhotoEditScreen.holdDelay)))
        XCTAssertTrue(screen.showsBeforeLabel)
        XCTAssertEqual(screen.displayed, .identity, "編集を始めたときの姿ではなく、元の写真")
        XCTAssertEqual(screen.current.preset?.id, "haze", "比べても編集は動かさない")
        // 触れたまま時間がたっても（指が少し動いて began がまた来ても）出し続ける
        screen.press(.began(at: t0.addingTimeInterval(2)))
        screen.press(.tick(now: t0.addingTimeInterval(3)))
        XCTAssertTrue(screen.showsBeforeLabel, "離すまで出し続ける")
        screen.press(.ended)
        XCTAssertFalse(screen.showsBeforeLabel, "離したら必ず戻す")
        XCTAssertEqual(screen.displayed.preset?.id, "haze")
        XCTAssertTrue(screen.canUndo, "比べても履歴は動かない")
    }

    /// 時間の扱い: 認めるのは触れてから `holdDelay` たってから。離したあとに届いた古い時計・
    /// 触れ直した直後に届いた前の時計では比べない
    func testHoldDelayIsMeasuredFromTheCurrentTouch() {
        var screen = PhotoEditScreen()
        screen.press(.began(at: t0))
        screen.press(.tick(now: t0.addingTimeInterval(PhotoEditScreen.holdDelay - 0.01)))
        XCTAssertFalse(screen.showsBeforeLabel, "まだ短い")
        screen.press(.ended)
        screen.press(.tick(now: t0.addingTimeInterval(1)))
        XCTAssertFalse(screen.showsBeforeLabel, "離したあとの時計で比べない")
        // 素早く触れ直した: 前の指の時計（t0 + 0.25）が、新しい指（t0 + 0.2）の直後に届く
        screen.press(.began(at: t0.addingTimeInterval(0.2)))
        screen.press(.tick(now: t0.addingTimeInterval(PhotoEditScreen.holdDelay)))
        XCTAssertFalse(screen.showsBeforeLabel, "新しい指からはまだ時間がたっていない")
        screen.press(.tick(now: t0.addingTimeInterval(0.2 + PhotoEditScreen.holdDelay)))
        XCTAssertTrue(screen.showsBeforeLabel)
    }

    func testFailureAndShareMessages() {
        XCTAssertEqual(UploadEditRules.exportFailureMessage("画像を変換できませんでした"),
                       "画像を変換できませんでした。編集を「なし」に戻すと元の写真で送れます")
        XCTAssertTrue(UploadEditRules.exportFailureMessage(nil).hasSuffix("編集を「なし」に戻すと元の写真で送れます"))
        XCTAssertNil(UploadEditRules.withShareSkipped(nil, skipped: 0))
        XCTAssertEqual(UploadEditRules.withShareSkipped("x", skipped: 0), "x")
        XCTAssertTrue(UploadEditRules.withShareSkipped(nil, skipped: 2)?.contains("2 枚を共有用に用意できなかったため、SNS への共有は開いていません") ?? false)
        XCTAssertTrue(UploadEditRules.withShareSkipped("x", skipped: 1)?.hasPrefix("x") ?? false)
    }

    func testCancelAsksOnlyWhenChanged() {
        var screen = PhotoEditScreen(original: PhotoRecipe(contrast: 0.3))
        XCTAssertFalse(screen.asksBeforeDiscard)
        screen.selectPreset("silver")
        XCTAssertTrue(screen.asksBeforeDiscard)
        screen.undo()
        XCTAssertFalse(screen.asksBeforeDiscard)
    }

    // MARK: - 帯の札

    func testBadge() {
        XCTAssertNil(PhotoEditBadge.text(for: .identity))
        XCTAssertEqual(PhotoEditBadge.text(for: PhotoRecipe(preset: .init(id: "dusk", strength: 0.8))), "夕凪")
        XCTAssertEqual(PhotoEditBadge.text(for: PhotoRecipe(exposure: 0.3, preset: .init(id: "postcard"))), "旅の葉書",
                       "プリセット＋調整はプリセット名")
        XCTAssertEqual(PhotoEditBadge.text(for: PhotoRecipe(exposure: 0.3)), "調整")
        XCTAssertEqual(PhotoEditBadge.text(for: PhotoRecipe(shadows: 0.1, preset: .init(id: "dusk", strength: 0))), "調整",
                       "強さ 0 のプリセットは効いていない")
        XCTAssertNil(PhotoEditBadge.text(for: PhotoRecipe(preset: .init(id: "dusk", strength: 0))))
        XCTAssertNil(PhotoEditBadge.text(for: PhotoRecipe(preset: .init(id: "no-such"))), "知らないプリセットは無編集")
    }

    // MARK: - 投稿画面との決まり

    func testExportOnlyWhenEdited() {
        XCTAssertFalse(UploadEditRules.needsExport(.identity))
        XCTAssertFalse(UploadEditRules.needsExport(PhotoRecipe(preset: .init(id: "dusk", strength: 0))))
        XCTAssertTrue(UploadEditRules.needsExport(PhotoRecipe(saturation: -0.2)))
        XCTAssertTrue(UploadEditRules.needsExport(PhotoRecipe(preset: .init(id: "sumi"))))
    }

    func testEditIsLockedWhileStagedOrSending() {
        XCTAssertTrue(UploadEditRules.canEdit(isStaged: false, isWorking: false))
        XCTAssertFalse(UploadEditRules.canEdit(isStaged: true, isWorking: false), "二重投稿の守り（#136）")
        XCTAssertFalse(UploadEditRules.canEdit(isStaged: false, isWorking: true))
    }

    func testStagedKeyIsReusedOnlyForTheSamePicture() {
        XCTAssertTrue(UploadEditRules.reusesStaged(stagedWith: nil, current: .identity))
        XCTAssertTrue(UploadEditRules.reusesStaged(stagedWith: .identity,
                                                   current: PhotoRecipe(preset: .init(id: "dusk", strength: 0))),
                      "どちらも無編集")
        XCTAssertTrue(UploadEditRules.reusesStaged(stagedWith: PhotoRecipe(exposure: 0.5), current: PhotoRecipe(exposure: 0.5)))
        XCTAssertFalse(UploadEditRules.reusesStaged(stagedWith: nil, current: PhotoRecipe(exposure: 0.5)),
                       "無編集で置いた鍵を、編集後の絵に使わない")
        XCTAssertFalse(UploadEditRules.reusesStaged(stagedWith: PhotoRecipe(exposure: 0.5), current: .identity))
        XCTAssertFalse(UploadEditRules.reusesStaged(stagedWith: PhotoRecipe(exposure: 0.5), current: PhotoRecipe(exposure: 0.6)))
    }

    // MARK: - 最新だけを描く

    func testQueueDropsIntermediateJobs() {
        var queue = LatestOnlyQueue<Int>()
        XCTAssertEqual(queue.submit(1), 1, "空いていれば今すぐ")
        XCTAssertNil(queue.submit(2))
        XCTAssertNil(queue.submit(3))
        XCTAssertNil(queue.submit(4))
        XCTAssertEqual(queue.finish(), 4, "途中の 2・3 は描かない")
        XCTAssertNil(queue.finish())
        XCTAssertNil(queue.running)
        XCTAssertEqual(queue.submit(5), 5, "空いたらまた今すぐ")
    }
}
