import XCTest
@testable import JourneyPhoto

/// ストーリーのカメラの仕上げ（2026-11-09・ズーム・フラッシュ・タイマー・ハンズフリー録画）。
/// 本物のカメラ（`AVCaptureDevice`）は実機で確かめる。ここは決まり表と、画面のつなぎ込み（ソースの文字）。
final class StoryCameraPolishTests: XCTestCase {

    // MARK: - フラッシュ

    /// 順は オフ → オン → 自動 → オフ。3つで一周する
    func testFlashCyclesOffOnAuto() {
        XCTAssertEqual(StoryCameraRules.Flash.off.next, .on)
        XCTAssertEqual(StoryCameraRules.Flash.on.next, .auto)
        XCTAssertEqual(StoryCameraRules.Flash.auto.next, .off)
        XCTAssertEqual(StoryCameraRules.Flash.allCases.count, 3)
        XCTAssertFalse(StoryCameraRules.Flash.off.isActive)
        XCTAssertTrue(StoryCameraRules.Flash.on.isActive)
        XCTAssertTrue(StoryCameraRules.Flash.auto.isActive)
    }

    /// 色だけで伝えない: 3つとも記号と読み上げが違う
    func testFlashStatesDifferByShapeAndSpeech() {
        let all = StoryCameraRules.Flash.allCases
        XCTAssertEqual(Set(all.map(\.symbol)).count, 3)
        XCTAssertEqual(Set(all.map(\.accessibilityLabel)).count, 3)
    }

    /// 背面（光るもの）があるときだけ。録画中・数えている間は変えさせない
    func testFlashButtonShowsOnlyWhenUsable() {
        XCTAssertTrue(StoryCameraRules.showsFlash(hasFlash: true, isRecording: false, counting: false))
        XCTAssertFalse(StoryCameraRules.showsFlash(hasFlash: false, isRecording: false, counting: false),
                       "前面にフラッシュを出している")
        XCTAssertFalse(StoryCameraRules.showsFlash(hasFlash: true, isRecording: true, counting: false))
        XCTAssertFalse(StoryCameraRules.showsFlash(hasFlash: true, isRecording: false, counting: true))
    }

    // MARK: - タイマー

    func testTimerCyclesOffThreeTen() {
        XCTAssertEqual(StoryCameraRules.TimerOption.off.next, .three)
        XCTAssertEqual(StoryCameraRules.TimerOption.three.next, .ten)
        XCTAssertEqual(StoryCameraRules.TimerOption.ten.next, .off)
        XCTAssertEqual(StoryCameraRules.TimerOption.allCases.map(\.seconds), [0, 3, 10])
        XCTAssertEqual(Set(StoryCameraRules.TimerOption.allCases.map(\.accessibilityLabel)).count, 3)
    }

    func testCountdownSequenceCountsDownToOne() {
        XCTAssertEqual(StoryCameraRules.countdownSequence(.three), [3, 2, 1])
        XCTAssertEqual(StoryCameraRules.countdownSequence(.ten), Array((1...10).reversed()))
        XCTAssertEqual(StoryCameraRules.countdownSequence(.off), [], "オフなのに数える")
        XCTAssertEqual(StoryCameraRules.countdownStepSeconds, 1)
    }

    /// タイマーなし: 今までどおり。写真はタップで撮る・動画のタップは始める・録画中のタップは止める
    func testPressWithoutTimerKeepsExistingBehavior() {
        XCTAssertEqual(StoryCameraRules.pressIntent(mode: .photo, isRecording: false, timer: .off, counting: false),
                       .perform(.takePhoto))
        XCTAssertEqual(StoryCameraRules.pressIntent(mode: .video, isRecording: false, timer: .off, counting: false),
                       .perform(.startRecording))
        XCTAssertEqual(StoryCameraRules.pressIntent(mode: .video, isRecording: true, timer: .off, counting: false),
                       .perform(.stopRecording))
    }

    /// タイマーあり: 数えてから撮る。**動画は押さずに始まる（ハンズフリー）**。録画中のタップは数えずに止める
    func testPressWithTimerCountsThenActs() {
        XCTAssertEqual(StoryCameraRules.pressIntent(mode: .photo, isRecording: false, timer: .three, counting: false),
                       .startCountdown(then: .takePhoto))
        XCTAssertEqual(StoryCameraRules.pressIntent(mode: .video, isRecording: false, timer: .ten, counting: false),
                       .startCountdown(then: .startRecording))
        XCTAssertEqual(StoryCameraRules.pressIntent(mode: .video, isRecording: true, timer: .ten, counting: false),
                       .perform(.stopRecording), "ハンズフリーで始めた録画を止められない")
    }

    /// 数えている間のタップは取り消し（どちらのモードでも・どの秒数でも）
    func testPressWhileCountingCancels() {
        for mode in [StoryCameraRules.Mode.photo, .video] {
            for timer in [StoryCameraRules.TimerOption.three, .ten] {
                XCTAssertEqual(
                    StoryCameraRules.pressIntent(mode: mode, isRecording: false, timer: timer, counting: true),
                    .cancelCountdown)
            }
        }
    }

    /// タイマーが入っている・数えている間は、長押しを動画にしない。入っていなければ今までどおり
    func testHoldIsDisabledWithTimer() {
        XCTAssertEqual(StoryCameraRules.holdAction(isRecording: false, timer: .off, counting: false), .startRecording)
        XCTAssertNil(StoryCameraRules.holdAction(isRecording: false, timer: .three, counting: false))
        XCTAssertNil(StoryCameraRules.holdAction(isRecording: false, timer: .off, counting: true))
        XCTAssertNil(StoryCameraRules.holdAction(isRecording: true, timer: .off, counting: false))
    }

    /// アプリが前面でなくなった・撮影の場が中断された・映像が出ていないときは取り消す
    func testCountdownCancelsWhenTheAppLeavesTheFront() {
        XCTAssertTrue(StoryCameraRules.countdownContinues(sceneActive: true, sessionInterrupted: false,
                                                          cameraReady: true))
        XCTAssertFalse(StoryCameraRules.countdownContinues(sceneActive: false, sessionInterrupted: false,
                                                           cameraReady: true), "裏へ行ったのに数え続けて撮る")
        XCTAssertFalse(StoryCameraRules.countdownContinues(sceneActive: true, sessionInterrupted: true,
                                                           cameraReady: true), "電話が来たのに数え続ける")
        XCTAssertFalse(StoryCameraRules.countdownContinues(sceneActive: true, sessionInterrupted: false,
                                                           cameraReady: false))
    }

    func testCountdownAnnouncementsAreSpoken() {
        XCTAssertTrue(StoryCameraRules.countdownAnnouncement(seconds: 3, action: .takePhoto).contains("3"))
        XCTAssertTrue(StoryCameraRules.countdownAnnouncement(seconds: 10, action: .startRecording).contains("10"))
        XCTAssertNotEqual(StoryCameraRules.countdownAnnouncement(seconds: 3, action: .takePhoto),
                          StoryCameraRules.countdownAnnouncement(seconds: 3, action: .startRecording))
        XCTAssertFalse(StoryCameraRules.countdownCancelledAnnouncement.isEmpty)
    }

    // MARK: - ズーム・切り替え

    func testZoomPillsNeedMoreThanOneStep() {
        XCTAssertFalse(StoryCameraRules.showsZoomPills(presetCount: 1))
        XCTAssertTrue(StoryCameraRules.showsZoomPills(presetCount: 2))
        // 倍率の刻みは写しを作らず `ComposeControls` を使い回す（三眼は 0.5 / 1 / 2 / 3）
        XCTAssertEqual(ComposeControls.zoomLevels(hasUltraWide: true, switchOver: [2, 6],
                                                  minFactor: 1, maxFactor: 123).presets,
                       [0.5, 1, 2, 3])
    }

    func testModeAndFlipLockedWhileRecordingOrCounting() {
        XCTAssertTrue(StoryCameraRules.allowsModeAndFlip(isRecording: false, counting: false))
        XCTAssertFalse(StoryCameraRules.allowsModeAndFlip(isRecording: true, counting: false))
        XCTAssertFalse(StoryCameraRules.allowsModeAndFlip(isRecording: false, counting: true),
                       "数えている間にモードが替わると撮るものが変わる")
    }

    // MARK: - 触覚

    /// タイマーの刻みは軽く・取り消しと選択は切り替えと同じ。既存の対応は変えない
    func testNewHaptics() {
        XCTAssertEqual(StoryCameraRules.haptic(for: .countdownTick), .impactLight)
        XCTAssertEqual(StoryCameraRules.haptic(for: .countdownCancelled), .selection)
        XCTAssertEqual(StoryCameraRules.haptic(for: .optionChanged), .selection)
        XCTAssertEqual(StoryCameraRules.haptic(for: .recordingStarted), .impactHeavy)
        XCTAssertEqual(StoryCameraRules.haptic(for: .recordingStopped), .impactLight)
        XCTAssertEqual(StoryCameraRules.haptic(for: .modeSwitched), .selection)
    }

    // MARK: - 画面のつなぎ込み（ソースの文字）

    private static var repo: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func view() throws -> String {
        try String(contentsOf: Self.repo.appendingPathComponent("Sources/JourneyPhoto/Features/Stories/StoryCameraView.swift"),
                   encoding: .utf8)
    }

    /// ズーム: ピンチ・倍率の丸・仮想カメラ（0.5×）・流し始める前に 1×・前後の切り替えで段を作り直す
    func testZoomWiring() throws {
        let source = try view()
        XCTAssertTrue(source.contains("MagnifyGesture()"), "ピンチが無い")
        XCTAssertTrue(source.contains("ComposeControls.pinchedFactor("))
        XCTAssertTrue(source.contains("Compose" + "Camera.backCamera()"), "背面が広角1つのまま（0.5× が出ない）")
        XCTAssertTrue(source.contains("Compose" + "Camera.levels(for: device)"))
        XCTAssertTrue(source.contains("device.videoZoomFactor = CGFloat(levels.factor(display: 1))"),
                      "開いた瞬間に 0.5× が見える")
        XCTAssertGreaterThanOrEqual(source.components(separatedBy: "applyOneTimesZoom(to: device)").count - 1, 2,
                                    "最初と前後の切り替えの両方で段を作り直す")
        XCTAssertTrue(source.contains("ramp(toVideoZoomFactor"))
        XCTAssertTrue(source.contains("animated: !reduceMotion"), "動きを減らす設定でも滑らかに寄る")
        XCTAssertTrue(source.contains("ComposeControls.zoomAccessibility(preset)"), "倍率を読み上げない")
    }

    /// フラッシュ: 写真は許された設定だけ・動画はライト（録画の終わり・画面を閉じるときに消す）
    func testFlashWiring() throws {
        let source = try view()
        XCTAssertTrue(source.contains("photoOutput.supportedFlashModes.contains(flash.captureMode)"),
                      "許さない設定を渡すと撮影が例外で落ちる")
        XCTAssertTrue(source.contains("settings.flashMode = flash.captureMode"))
        XCTAssertTrue(source.contains("setTorch(flash.torchMode)"))
        XCTAssertGreaterThanOrEqual(source.components(separatedBy: "setTorch(.off)").count - 1, 2,
                                    "録画が終わっても・画面を閉じてもライトが点いたまま")
        XCTAssertTrue(source.contains("camera.capturePhoto(flash: flash)"))
        XCTAssertTrue(source.contains("camera.startRecording(flash: flash)"))
        XCTAssertTrue(source.contains("device.position == .back"), "前面にフラッシュを出している")
    }

    /// タイマー: 取り消し（裏・中断・閉じる・もう一度押す）・数える前にマイク・触覚・読み上げ・動きを減らす
    func testTimerWiring() throws {
        let source = try view()
        XCTAssertTrue(source.contains("@Environment(\\.scenePhase)"))
        XCTAssertTrue(source.contains("StoryCameraRules.countdownContinues(sceneActive: phase == .active"),
                      "裏へ行ったときに取り消さない")
        XCTAssertTrue(source.contains(".onChange(of: camera.interruptions)"), "電話が来たときに取り消さない")
        XCTAssertTrue(source.contains("AVCaptureSession.wasInterruptedNotification"))
        let disappear = try XCTUnwrap(source.range(of: ".onDisappear {"))
        // 閉じる処理の本体（`camera.stop()` まで）の中に取り消しがあること。固定の文字数では行が増えるたびにずれる
        let closing = try XCTUnwrap(source.range(of: "camera.stop()", range: disappear.lowerBound..<source.endIndex))
        XCTAssertTrue(String(source[disappear.lowerBound..<closing.upperBound]).contains("cancelCountdown()"),
                      "画面を閉じても数え続けて撮る")
        XCTAssertTrue(source.contains("if action == .startRecording { await camera.prepareAudio() }"),
                      "数えている途中でマイクのダイアログが出る")
        XCTAssertTrue(source.contains("countdownTask?.cancel()"))
        XCTAssertTrue(source.contains("press(currentPressIntent)"), "読み上げの操作がタイマーを通らない")
        XCTAssertTrue(source.contains("StoryCameraRules.pressIntent("))
        XCTAssertTrue(source.contains(
            ".sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: countdownTickCount)"))
        XCTAssertTrue(source.contains("AccessibilityNotification.Announcement("))
        XCTAssertTrue(source.contains("if reduceMotion {"), "カウントダウンが動きを減らす設定を見ない")
    }

    /// 押せる所 44pt・真鍮を映像の上に置かない・禁止語・現在地・タブの選択に触らない
    func testDesignRulesStillHold() throws {
        let source = try view()
        for part in ["private var flashButton", "private var timerButton", "private var zoomPills"] {
            let start = try XCTUnwrap(source.range(of: part), part)
            let body = String(source[start.lowerBound...].prefix(1800))
            XCTAssertTrue(body.contains("WebTheme.minTapTarget"), "\(part) の当たりが 44pt に足りない")
            XCTAssertFalse(body.contains("WebTheme.accent"), "\(part) が写真の上に真鍮を置いている")
        }
        for line in source.components(separatedBy: "\n") where line.contains(".system(size:") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            XCTAssertTrue(trimmed.hasPrefix("//"), "固定の大きさの字は使わない（文字サイズに付いてこない）: \(line)")
        }
        for word in ["撮りどき", "捨てる", "注目スポット", "撮影地ガイド", "ガイドを見る", "この場所"] {
            XCTAssertFalse(source.contains(word), word)
        }
        XCTAssertFalse(source.contains("CoreLocation"))
        XCTAssertFalse(source.contains("selection =") || source.contains("select("), "#435: タブの選択に触らない")
    }

    /// 長押しの待ち・モード切り替えの場所・ライトの使えるか（確かめ役の指摘3点）
    func testReviewFixes() throws {
        let source = try view()
        let disappear = try XCTUnwrap(source.range(of: ".onDisappear {"))
        let block = String(source[disappear.lowerBound...].prefix(400))
        let hold = try XCTUnwrap(block.range(of: "holdTask?.cancel()"), "閉じたあとに長押しの待ちが録画を始める")
        let stop = try XCTUnwrap(block.range(of: "camera.stop()"))
        XCTAssertLessThan(hold.lowerBound, stop.lowerBound)
        XCTAssertFalse(source.contains("{\n                modePicker.padding(.bottom, 14)"),
                       "録画中にモード切り替えを消すと倍率の丸が下へ落ちる")
        XCTAssertTrue(source.contains(".opacity(modeLocked ? 0 : 1)"))
        XCTAssertTrue(source.contains(".allowsHitTesting(!modeLocked)"))
        XCTAssertTrue(source.contains(".accessibilityHidden(modeLocked)"))
        XCTAssertTrue(source.contains("device.isTorchAvailable, device.isTorchModeSupported(mode)"))
    }

    /// 録画の後始末（✕・孤児ファイル）とマイクの許可の流れを壊していない
    func testExistingRecordingCleanupIsKept() throws {
        let source = try view()
        XCTAssertTrue(source.contains("abandoned = true"))
        XCTAssertTrue(source.contains("await camera.prepareAudio()\n                // 長押しで始めるはずが"))
        XCTAssertTrue(source.contains("case .denied:"))
        XCTAssertTrue(source.contains("case .unavailable:"))
        XCTAssertTrue(source.contains("micDenied"))
    }
}
