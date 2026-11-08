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

    /// 長押しで始めた録画は指を離すと止まる。タップで始めた録画（動画モード）は離しても止まらない
    func testReleaseStopsOnlyHoldRecordings() {
        XCTAssertTrue(StoryCameraRules.releaseStopsRecording(startedByHold: true))
        XCTAssertFalse(StoryCameraRules.releaseStopsRecording(startedByHold: false))
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
        center.request()
        XCTAssertTrue(center.pending)
        XCTAssertEqual(center.requests, 2)
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
            .contains("StoryComposerView(startsWithCamera: composerStartsWithCamera)"))
        XCTAssertTrue(try read("Sources/JourneyPhoto/App/RootView.swift")
            .contains("StoryComposerView(openDraft: openStoryDraftId, startsWithCamera: storyStartsWithCamera)"))
    }
}
