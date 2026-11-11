import XCTest
@testable import JourneyPhoto

/// ストーリーの撮影の入口（札 #500・デザイナーのモック A 案）。カメラの本物（`AVCaptureSession`）は実機で確かめる。
/// ここは、シャッターの決まり・触覚の対応・アイコン長押しを受けてよい条件・設定ファイル（マイクの文言・項目）。
final class StoryCameraEntryTests: XCTestCase {

    // MARK: - シャッター

    func testTapTakesAPhotoInPhotoModeAndTogglesInVideoMode() {
        XCTAssertEqual(StoryCameraRules.tapAction(mode: .photo, isRecording: false), .takePhoto)
        XCTAssertEqual(StoryCameraRules.tapAction(mode: .video, isRecording: false), .startRecording)
        // 撮っている最中のタップは、どちらのモードでも止める
        XCTAssertEqual(StoryCameraRules.tapAction(mode: .photo, isRecording: true), .stopRecording)
        XCTAssertEqual(StoryCameraRules.tapAction(mode: .video, isRecording: true), .stopRecording)
    }

    /// 長押しはどちらのモードでも動画。すでに撮っていれば二重に始めない
    func testHoldStartsRecordingOnce() {
        XCTAssertEqual(StoryCameraRules.holdAction(isRecording: false), .startRecording)
        XCTAssertNil(StoryCameraRules.holdAction(isRecording: true))
        XCTAssertGreaterThan(StoryCameraRules.holdThreshold, 0.2, "短すぎるとタップが動画になる")
        XCTAssertLessThan(StoryCameraRules.holdThreshold, 0.8, "長すぎると長押しに気づかない")
    }

    /// 2026-11-11（owner「ずっと押さないといけないのは嫌」）: 長押しで始めた録画は、指を離しても止めない。
    /// 長押しにならなかった押しは、離したときにタップとして扱う
    func testReleaseNeverStopsAHoldRecording() {
        XCTAssertEqual(StoryCameraRules.releaseOutcome(startedByHold: true), .keepRecording,
                       "長押しの録画が指を離すと止まる（撮っている間ずっと押していなければならない）")
        XCTAssertEqual(StoryCameraRules.releaseOutcome(startedByHold: false), .tap)
    }

    /// 長押しで始めた録画は、もう一度押す（タップ）と止まる。どちらのモードでも同じ
    func testTapStopsAHoldRecording() {
        for mode in [StoryCameraRules.Mode.photo, .video] {
            XCTAssertEqual(StoryCameraRules.pressIntent(mode: mode, isRecording: true, recordedSeconds: 3,
                                                        starting: false, timer: .off, counting: false),
                           .perform(.stopRecording), "\(mode)")
        }
    }

    /// 始めた直後の二度押し（長押しを離した直後のもう一押し・動画モードの続けての2回タップ）では止めない。
    /// 始めている途中（マイクの用意の間）のタップも受けない——写真モードで写真を撮って閉じてしまう
    func testDoublePressDoesNotStopRightAway() {
        XCTAssertEqual(StoryCameraRules.pressIntent(mode: .photo, isRecording: true, recordedSeconds: 0.1,
                                                    starting: false, timer: .off, counting: false),
                       .ignore, "始めてすぐの二度押しで 0 秒の動画になって閉じる")
        XCTAssertEqual(StoryCameraRules.pressIntent(mode: .video, isRecording: true, recordedSeconds: 0.2,
                                                    starting: false, timer: .off, counting: false), .ignore)
        XCTAssertEqual(StoryCameraRules.pressIntent(mode: .photo, isRecording: false, recordedSeconds: 0,
                                                    starting: true, timer: .off, counting: false),
                       .ignore, "録画を始めている途中のタップで写真を撮って閉じる")
        XCTAssertTrue(StoryCameraRules.acceptsStopTap(recordedSeconds: StoryCameraRules.stopGuardSeconds))
        XCTAssertFalse(StoryCameraRules.acceptsStopTap(recordedSeconds: 0))
        XCTAssertLessThanOrEqual(StoryCameraRules.stopGuardSeconds, 1, "長すぎると止めたいのに止まらない")
        XCTAssertTrue(StoryCameraRules.acceptsStopTap(recordedSeconds: .nan), "時間が分からないときは止められること")
        // 数えている間のタップは、始めている途中でも取り消し
        XCTAssertEqual(StoryCameraRules.pressIntent(mode: .video, isRecording: false, recordedSeconds: 0,
                                                    starting: true, timer: .three, counting: true), .cancelCountdown)
    }

    /// 案内は「押すと止まります」。「指を離すと」の言い方を残さない
    func testStopHintWording() throws {
        XCTAssertEqual(StoryCameraRules.stopHint, L("押すと止まります", "Tap to stop"))
        for path in ["Sources/JourneyPhoto/Features/Stories/StoryCameraView.swift",
                     "Sources/JourneyPhoto/Core/Text/StoryCameraRules.swift"] {
            let source = try read(path)
            // 表の言葉（`L(` の行）に「離すと」を出さない（注記の中の owner の声は残す）
            for line in source.split(separator: "\n") where line.contains("L(\"") {
                XCTAssertFalse(line.contains("離すと"), "\(path): \(line)")
            }
            XCTAssertFalse(source.contains("releaseStopsRecording"), path)
        }
    }

    /// 画面の配線: 離したときは `releaseOutcome` を通す（止めない）・録画中の案内・読み上げのヒント・
    /// アプリが前面でなくなった／撮影の場が中断されたら録画を止める・始めている途中を数える
    func testHoldRecordingWiring() throws {
        let source = try read("Sources/JourneyPhoto/Features/Stories/StoryCameraView.swift")
        let ended = try XCTUnwrap(source.range(of: ".onEnded { _ in\n                let held"))
        let endBody = String(source[ended.lowerBound...].prefix(500))
        XCTAssertTrue(endBody.contains("StoryCameraRules.releaseOutcome(startedByHold: held)"))
        XCTAssertFalse(endBody.contains("perform(.stopRecording)"), "指を離すと録画が止まる")
        XCTAssertTrue(source.contains("if camera.isRecording { stopHint }"), "録画中に止め方の案内が無い")
        XCTAssertTrue(source.contains(".accessibilityHint(shutterHint)"))
        let scene = try XCTUnwrap(source.range(of: ".onChange(of: scenePhase)"))
        let interrupted = try XCTUnwrap(source.range(of: ".onChange(of: camera.interruptions)"))
        XCTAssertTrue(String(source[scene.lowerBound..<interrupted.lowerBound]).contains("perform(.stopRecording)"),
                      "裏へ行っても録画が続く")
        XCTAssertTrue(String(source[interrupted.lowerBound...].prefix(300)).contains("perform(.stopRecording)"),
                      "電話が来ても録画が続く")
        XCTAssertTrue(source.contains("guard !recordingStarting, !camera.isRecording else { return }"),
                      "二度押しで録画を二度始める")
        XCTAssertTrue(source.contains("starting: recordingStarting"))
        // 長押しでも、ダイアログの間に指が離れていたら始めない（今までどおり）
        XCTAssertTrue(source.contains("StoryCameraRules.startsAfterPermission(fromHold: fromHold, stillPressing: pressing)"))
    }

    func testProgressStopsAtTheLimit() {
        XCTAssertEqual(StoryCameraRules.progress(elapsed: 0), 0)
        XCTAssertEqual(StoryCameraRules.progress(elapsed: 30), 0.5, accuracy: 0.001)
        XCTAssertEqual(StoryCameraRules.progress(elapsed: 90), 1)
        XCTAssertEqual(StoryCameraRules.progress(elapsed: .nan), 0)
        XCTAssertFalse(StoryCameraRules.reachedLimit(elapsed: 59))
        XCTAssertTrue(StoryCameraRules.reachedLimit(elapsed: 60))
    }

    // MARK: - 触覚

    /// 写真 impact(medium)・録画開始 heavy・停止 light・切り替え selection・上限 warning・失敗 error・投稿完了 success
    func testHapticsMapping() {
        let expected: [(StoryCameraRules.Event, StoryCameraRules.Haptic)] = [
            (.photoTaken, .impactMedium), (.recordingStarted, .impactHeavy), (.recordingStopped, .impactLight),
            (.modeSwitched, .selection), (.limitReached, .warning), (.failed, .error), (.posted, .success),
        ]
        for (event, haptic) in expected {
            XCTAssertEqual(StoryCameraRules.haptic(for: event), haptic, "\(event)")
        }
    }

    // MARK: - アイコン長押し

    /// ログイン済みで、タブが出ていて、ほかの画面が無いときだけ受ける。それまでは持ち越す
    func testShortcutIsAcceptedOnlyWhenTheAppIsSettled() {
        XCTAssertTrue(StoryCameraRules.canOpenCamera(signedIn: true, tabsShown: true, anotherScreenShown: false))
        XCTAssertFalse(StoryCameraRules.canOpenCamera(signedIn: false, tabsShown: true, anotherScreenShown: false),
                       "ログインしていないのに作る画面を開いている")
        XCTAssertFalse(StoryCameraRules.canOpenCamera(signedIn: true, tabsShown: false, anotherScreenShown: false))
        XCTAssertFalse(StoryCameraRules.canOpenCamera(signedIn: true, tabsShown: true, anotherScreenShown: true),
                       "投稿やお知らせの上に重ねて開いている")
    }

    func testSettleWaitCoversTheColdStartStall() {
        XCTAssertEqual(StoryCameraRules.settleWait(sinceLaunch: 0), StoryCameraRules.settleSeconds)
        XCTAssertEqual(StoryCameraRules.settleWait(sinceLaunch: 1.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(StoryCameraRules.settleWait(sinceLaunch: 10), 0)
        XCTAssertEqual(StoryCameraRules.settleWait(sinceLaunch: -3), StoryCameraRules.settleSeconds, "時計が戻っても待ちが伸びない")
        XCTAssertGreaterThan(StoryCameraRules.settleSeconds, 1.6, "#435 の計測の最大の停止（1.6秒）より長く待つ")
    }

    @MainActor
    func testShortcutCenterCarriesOverAndDeliversOnce() async {
        let center = StoryShortcutCenter()
        XCTAssertFalse(center.pending)
        center.request()
        center.request() // 冷えた起動は AppDelegate と場面の係の両方から届く
        XCTAssertTrue(center.pending)
        XCTAssertEqual(center.requests, 1, "同じ依頼を2回数えて、開いたあとにもう一度開く")
        XCTAssertTrue(center.take(), "持ち越した依頼を受け取れない")
        XCTAssertFalse(center.take(), "二重に開く")
        XCTAssertFalse(center.pending)
    }

    // MARK: - 設定ファイル

    private static var repo: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: Self.repo.appendingPathComponent(path), encoding: .utf8)
    }

    /// アイコン長押しの項目は project.yml に1つ、種類は決まりと同じ。題は英語版もある。拡張は足さない
    func testShortcutItemIsDeclaredAndLocalized() throws {
        let yml = try read("project.yml")
        XCTAssertTrue(yml.contains("UIApplicationShortcutItems:"))
        XCTAssertTrue(yml.contains("UIApplicationShortcutItemType: \(StoryCameraRules.shortcutType)"),
                      "項目の種類が決まりとずれている（長押しを受けても開かない）")
        XCTAssertTrue(yml.contains("UIApplicationShortcutItemTitle: ストーリーを撮る"))
        XCTAssertTrue(try read("Sources/JourneyPhoto/Resources/en.lproj/InfoPlist.strings")
            .contains("\"ストーリーを撮る\" = \"Shoot a story\";"), "英語の題が無い")
        XCTAssertTrue(try read("Sources/JourneyPhoto/Resources/ja.lproj/InfoPlist.strings")
            .contains("\"ストーリーを撮る\""))
        XCTAssertFalse(yml.contains("AppIntents"), "拡張・インテントは足さない決め")
    }

    /// 動画に音を入れるのでマイクの文言が要る（審査官が読む）。日本語・英語・project.yml の3か所
    func testMicrophoneUsageDescriptionIsDeclared() throws {
        XCTAssertTrue(try read("project.yml")
            .contains("NSMicrophoneUsageDescription: ストーリーの動画に音声を録音するために使います。"))
        XCTAssertTrue(try read("Sources/JourneyPhoto/Resources/ja.lproj/InfoPlist.strings")
            .contains("\"NSMicrophoneUsageDescription\" = \"ストーリーの動画に音声を録音するために使います。\";"))
        let en = try read("Sources/JourneyPhoto/Resources/en.lproj/InfoPlist.strings")
        XCTAssertTrue(en.contains("\"NSMicrophoneUsageDescription\" = \"Used to record sound for the videos you shoot for your story.\";"))
    }

    /// 現在地は撮影地の候補に使わない（位置情報の許可を増やさない）。カメラの画面は CoreLocation を読まない
    func testCameraDoesNotTouchLocation() throws {
        for path in ["Sources/JourneyPhoto/Features/Stories/StoryCameraView.swift",
                     "Sources/JourneyPhoto/Services/StoryVideoPipeline.swift",
                     "Sources/JourneyPhoto/App/StoryShortcut.swift"] {
            let source = try read(path)
            XCTAssertFalse(source.contains("CoreLocation") || source.contains("CLLocationManager"), path)
        }
    }

    /// 起動直後の受け口は、タブの選択（#435 の書き込み）に触らない
    func testShortcutDoesNotWriteTheTabSelection() throws {
        let source = try read("Sources/JourneyPhoto/App/StoryShortcut.swift")
        XCTAssertFalse(source.contains("selection =") || source.contains("select("), "起動直後にタブの選択を書くと #435 と競う")
        let root = try read("Sources/JourneyPhoto/App/RootView.swift")
        let start = try XCTUnwrap(root.range(of: ".modifier(StoryShortcutOpener("))
        let block = String(root[start.lowerBound...].prefix(500))
        XCTAssertFalse(block.contains("select("), "アイコン長押しの受け口がタブを切り替えている")
    }

    /// 作る画面の入口は2つ（`RootView`・`StoriesRow`）。どちらも全画面のまま、カメラ先頭の旗を渡す
    func testComposerEntriesPassTheCameraFirstFlag() throws {
        XCTAssertTrue(try read("Sources/JourneyPhoto/Features/Stories/StoriesRow.swift")
            .contains("StoryComposerView(startsWithCamera: StoryCameraView.isAvailable)"))
        XCTAssertTrue(try read("Sources/JourneyPhoto/App/RootView.swift")
            .contains("StoryComposerView(openDraft: openStoryDraftId, startsWithCamera: storyStartsWithCamera)"))
    }

    // MARK: - 札 #500 の直し(カメラ)

    /// 長押しの録画は、マイクの許可のダイアログの間に指が離れていたら始めない。タップの録画は始める
    func testRecordingStartsAfterPermissionOnlyIfStillHeld() {
        XCTAssertTrue(StoryCameraRules.startsAfterPermission(fromHold: true, stillPressing: true))
        XCTAssertFalse(StoryCameraRules.startsAfterPermission(fromHold: true, stillPressing: false),
                       "指が離れたのに録画が始まって止まらなくなる")
        XCTAssertTrue(StoryCameraRules.startsAfterPermission(fromHold: false, stillPressing: false))
    }

    /// 音なしの注記: 動画モード、または写真モードの長押しで録っている最中にも出す
    func testMicNoteShowsForHoldRecordingInPhotoMode() {
        XCTAssertTrue(StoryCameraRules.showsMicNote(micDenied: true, mode: .video, isRecording: false))
        XCTAssertTrue(StoryCameraRules.showsMicNote(micDenied: true, mode: .photo, isRecording: true),
                      "写真モードの長押しで音なしなのに知らせない")
        XCTAssertFalse(StoryCameraRules.showsMicNote(micDenied: true, mode: .photo, isRecording: false))
        XCTAssertFalse(StoryCameraRules.showsMicNote(micDenied: false, mode: .video, isRecording: true))
    }

    func testCameraWaitsForTransitions() {
        XCTAssertTrue(StoryComposerView.cameraMayOpen(transitioning: false))
        XCTAssertFalse(StoryComposerView.cameraMayOpen(transitioning: true))
    }

    /// 配線: 向きは端末の向きの係(`ComposeCamera` と同じ求め方)・マイクは録画の前・孤児の録画ファイルは消す・固定の待ちを置かない
    func testCameraWiring() throws {
        let camera = try read("Sources/JourneyPhoto/Features/Stories/StoryCameraView.swift")
        XCTAssertFalse(camera.contains("videoOrientation"), "向きを縦に決め打ちしている")
        XCTAssertTrue(camera.contains("ComposeGuide.captureAngle("))
        XCTAssertTrue(camera.contains("videoRotationAngleForHorizonLevelCapture"))
        XCTAssertTrue(camera.contains("await camera.prepareAudio()\n                // 長押しで始めるはずが"),
                      "録画の前にマイクの許可を済ませていない")
        XCTAssertTrue(camera.contains("abandoned = true"), "録画の途中で閉じたファイルが残る")
        let composer = try read("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        XCTAssertFalse(composer.contains("450_000_000"), "カメラを出すのに固定の待ちを置いている")
        XCTAssertTrue(composer.contains("isTransitioning()"))
    }

    /// 場面の係は、冷えた起動(`willConnectTo`)と起動中(`performActionFor`)の両方を受ける
    func testSceneDelegateReceivesBothPaths() throws {
        let scene = try read("Sources/JourneyPhoto/App/StoryShortcutScene.swift")
        XCTAssertTrue(scene.contains("scene(_ scene: UIScene, willConnectTo session: UISceneSession"))
        XCTAssertTrue(scene.contains("connectionOptions.shortcutItem"))
        XCTAssertTrue(scene.contains("windowScene(_ windowScene: UIWindowScene, performActionFor"))
        let delegate = try read("Sources/JourneyPhoto/App/AppDelegate.swift")
        XCTAssertTrue(delegate.contains("configuration.delegateClass = StorySceneDelegate.self"))
    }

    /// 使われなくなった動画用の模型を残さない
    func testNoDeadVideoShims() throws {
        let shim = try read("Shims/UIKit/UIKit.swift")
        for dead in ["videoMaximumDuration", "VideoQuality", "UIImagePickerControllerMediaURL"] {
            XCTAssertFalse(shim.contains(dead), dead)
        }
    }
}
