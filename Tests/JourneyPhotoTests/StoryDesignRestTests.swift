import XCTest
@testable import JourneyPhoto

/// 設計の案「ストーリーのデザイン 残り」（1.1.83・2026-11-12）の4画面——カメラ・動画を切り取る・曲の流し始め・
/// ハイライトを作る。決まり（画面から出した値）と、画面の配線を確かめる
final class StoryDesignRestTests: XCTestCase {

    private func repo(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: - 01 カメラ

    /// 録画中・数えている間はまわりの印（柱・最近の1枚・前後・写真｜動画）を消す。✕ は録画中だけ消す
    func testCameraChromeHidesWhileRecordingOrCounting() {
        XCTAssertTrue(StoryCameraRules.showsChrome(isRecording: false, counting: false))
        XCTAssertFalse(StoryCameraRules.showsChrome(isRecording: true, counting: false))
        XCTAssertFalse(StoryCameraRules.showsChrome(isRecording: false, counting: true))
        XCTAssertTrue(StoryCameraRules.showsClose(isRecording: false))
        XCTAssertFalse(StoryCameraRules.showsClose(isRecording: true))
        // 倍率の丸: 数えている間は消し、録画中は残す。段が1つなら出さない
        XCTAssertTrue(StoryCameraRules.showsZoom(presetCount: 3, counting: false))
        XCTAssertFalse(StoryCameraRules.showsZoom(presetCount: 3, counting: true))
        XCTAssertFalse(StoryCameraRules.showsZoom(presetCount: 1, counting: false))
        XCTAssertEqual(StoryCameraRules.preparingOpacity, 0.4)
    }

    /// 数えている間の案内・撮れなかった知らせ・録画の上限の札
    func testCameraNotes() {
        XCTAssertEqual(StoryCameraRules.countdownNote(seconds: 3, action: .takePhoto), "3秒後に撮ります")
        XCTAssertEqual(StoryCameraRules.countdownNote(seconds: 10, action: .startRecording), "10秒後に録画を始めます")
        XCTAssertEqual(StoryCameraRules.countdownCancelHint, "押すと取り消し")
        XCTAssertEqual(StoryCameraRules.failureNote, "撮れませんでした。もう一度押してください")
        XCTAssertEqual(StoryCameraRules.failureNoteSeconds, 3)
        XCTAssertEqual(StoryCameraRules.limitLabel, "/ 1:00")
    }

    /// 最近の1枚は写真の許可がすでにあるときだけ（許可を求めない）。写真から選ぶのは、1枚もなければ格子へ戻るだけ
    func testRecentThumbnailNeverAsksForPermission() throws {
        XCTAssertTrue(StoryCameraRules.showsRecentThumbnail(.authorized))
        XCTAssertTrue(StoryCameraRules.showsRecentThumbnail(.limited))
        XCTAssertFalse(StoryCameraRules.showsRecentThumbnail(.notDetermined))
        XCTAssertFalse(StoryCameraRules.showsRecentThumbnail(.denied))
        XCTAssertFalse(StoryCameraRules.showsRecentThumbnail(.restricted))
        XCTAssertFalse(StoryCameraRules.opensLibraryAfterCamera(shotCount: 0))
        XCTAssertTrue(StoryCameraRules.opensLibraryAfterCamera(shotCount: 2))
        let camera = try repo("Sources/JourneyPhoto/Features/Stories/StoryCameraView.swift")
        XCTAssertFalse(camera.contains("requestAuthorization"), "カメラの画面で写真の許可を求めている")
        XCTAssertTrue(camera.contains("PHPhotoLibrary.authorizationStatus(for: .readWrite)"))
    }

    /// 画面の配線: ガラスの柱・左下の写真から選ぶ・撮れなかった知らせ・準備中に部品を沈める・許可の無い画面
    func testCameraLayoutWiring() throws {
        let camera = try repo("Sources/JourneyPhoto/Features/Stories/StoryCameraView.swift")
        XCTAssertTrue(camera.contains(".jpGlass(in: RoundedRectangle(cornerRadius: WebTheme.minTapTarget / 2))"),
                      "フラッシュとタイマーがガラスの柱にまとまっていない")
        XCTAssertTrue(camera.contains("private var shutterRow: some View"))
        XCTAssertTrue(camera.contains("recentButton"))
        XCTAssertTrue(camera.contains(".accessibilityIdentifier(\"story.camera.library\")"))
        XCTAssertTrue(camera.contains(".onChange(of: failTick) { _, _ in showFailure() }"), "撮れなかったのに目に見える知らせが無い")
        XCTAssertTrue(camera.contains("controls(ready: false)"), "準備中に部品を先に置いていない")
        XCTAssertTrue(camera.contains(".opacity(ready ? 1 : StoryCameraRules.preparingOpacity)"))
        // 細い線の印（作る画面の線の太さ）。以前の semibold を残さない
        XCTAssertTrue(camera.contains("private static let iconFont: Font = .body.weight(.regular)"))
        // 許可の無い画面: 空の状態の型・「写真から選ぶ」を置く・言うだけで押せない文を残さない
        XCTAssertTrue(camera.contains("EmptyState(title: title, message: detail,"))
        XCTAssertTrue(camera.contains("story.camera.noticeLibrary"))
        XCTAssertFalse(camera.contains("ここで撮れます。写真アプリから選ぶこともできます"), "選ぶボタンが無いのに選べると書いている")
        // 「写真｜動画」はシャッターの下・選んでいるほうは白 94% に墨
        XCTAssertTrue(camera.contains(".background(on ? WebTheme.accentBackground : Color.clear, in: Capsule())"))
        // 録画中の札は「0:07 / 1:00」
        XCTAssertTrue(camera.contains("Text(StoryCameraRules.limitLabel)"))
        // 作る画面は、閉じたあとに写真選びへ
        let composer = try repo("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(composer.contains("onPickFromLibrary: { libraryAfterCamera = true }"))
        XCTAssertTrue(composer.contains("StoryCameraRules.opensLibraryAfterCamera(shotCount: shots.count)"))
    }

    // MARK: - 02 動画を切り取る

    /// 範囲ごと動かす: 長さは変えず、頭と終わりで止まる
    func testTrimShiftKeepsLength() {
        var trim = StoryVideoTrim(total: 144, start: 12, end: 72)
        trim.shift(toStart: 30)
        XCTAssertEqual(trim.start, 30)
        XCTAssertEqual(trim.end, 90)
        trim.shift(toStart: 200)
        XCTAssertEqual(trim.start, 84)
        XCTAssertEqual(trim.end, 144)
        trim.shift(toStart: -5)
        XCTAssertEqual(trim.start, 0)
        XCTAssertEqual(trim.end, 60)
        XCTAssertTrue(trim.atLimit)
        XCTAssertFalse(StoryVideoTrim(total: 30).atLimit)
    }

    /// 長さの下の注記: 60 秒を超える動画だけ「60秒まで」。範囲の札・吹き出しの時刻
    func testTrimLabels() {
        let long = StoryVideoTrim(total: 144, start: 12, end: 72)
        XCTAssertEqual(long.totalNote, "全体 2:24")
        XCTAssertEqual(long.limitNote, "60秒まで")
        XCTAssertNil(StoryVideoTrim(total: 45).limitNote)
        XCTAssertEqual(long.rangeLabel, "0:12–1:12")
        XCTAssertEqual(StoryVideoTrim(total: 45).totalNote, "全体 0:45")
        XCTAssertEqual(StoryVideoTrim(total: 60).totalNote, "全体 1:00")
        XCTAssertEqual(StoryVideoTrim.preciseLabel(12.4), "0:12.4")
        XCTAssertEqual(StoryVideoTrim.preciseLabel(72.05), "1:12.0")
        XCTAssertEqual(StoryVideoTrim.preciseLabel(5), "0:05.0")
        XCTAssertEqual(StoryVideoTrim.preciseLabel(-1), "0:00.0")
        XCTAssertEqual(StoryVideoTrim.preciseLabel(.nan), "0:00.0")
        XCTAssertEqual(StoryVideoTrimSheet.positionLabel(index: 0, count: 2), "1 / 2")
        XCTAssertNil(StoryVideoTrimSheet.positionLabel(index: 0, count: 1))
        XCTAssertNil(StoryVideoTrimSheet.positionLabel(index: 3, count: 2))
    }

    /// 開けない: 長さが読めない・帯を取り終えて1コマも取れない。取り終えるまでは決めない
    func testTrimCannotOpen() {
        XCTAssertTrue(StoryVideoTrim.cannotOpen(total: 0, framesRead: 0, framesAsked: 0, stripLoaded: false))
        XCTAssertTrue(StoryVideoTrim.cannotOpen(total: .nan, framesRead: 3, framesAsked: 10, stripLoaded: true))
        XCTAssertFalse(StoryVideoTrim.cannotOpen(total: 30, framesRead: 0, framesAsked: 0, stripLoaded: false))
        XCTAssertFalse(StoryVideoTrim.cannotOpen(total: 30, framesRead: 0, framesAsked: 10, stripLoaded: false))
        XCTAssertTrue(StoryVideoTrim.cannotOpen(total: 30, framesRead: 0, framesAsked: 10, stripLoaded: true))
        XCTAssertFalse(StoryVideoTrim.cannotOpen(total: 30, framesRead: 1, framesAsked: 10, stripLoaded: true))
        // 帯を取らない環境（Linux の模型）は 0 コマを頼んで 0 コマ——開けないとは言わない
        XCTAssertFalse(StoryVideoTrim.cannotOpen(total: 30, framesRead: 0, framesAsked: 0, stripLoaded: true))
    }

    /// 骨組みの光は -1〜1 を 1.6 秒で一回り
    func testTrimShimmerPhase() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertEqual(StoryVideoTrim.shimmerPhase(at: base), -1, accuracy: 0.0001)
        XCTAssertEqual(StoryVideoTrim.shimmerPhase(at: base.addingTimeInterval(0.8)), 0, accuracy: 0.0001)
        let late = StoryVideoTrim.shimmerPhase(at: base.addingTimeInterval(1.5))
        XCTAssertGreaterThan(late, 0.8)
        XCTAssertLessThan(late, 1)
    }

    /// 画面の配線: 動画は上の面いっぱい・長さは白・長い説明を出さない・開けない状態・骨組み
    func testTrimLayoutWiring() throws {
        let view = try repo("Sources/JourneyPhoto/Features/Stories/StoryVideoTrimView.swift")
        XCTAssertTrue(view.contains("UnevenRoundedRectangle(bottomLeadingRadius: JPRadius.xl, bottomTrailingRadius: JPRadius.xl)"))
        XCTAssertTrue(view.contains(".toolbar(.hidden, for: .navigationBar)"))
        XCTAssertFalse(view.contains(".foregroundStyle(WebTheme.accent)"), "長さの数を真鍮にしている（数は合図ではない）")
        XCTAssertTrue(view.contains("Text(trim.totalNote)"))
        XCTAssertFalse(view.contains("両端のつまみで範囲を選びます"), "長い説明の文が残っている")
        XCTAssertTrue(view.contains("EmptyState(title: L(\"この動画を開けません\""))
        XCTAssertTrue(view.contains("RetryButton { reload() }"))
        XCTAssertTrue(view.contains("StoryTrimShimmer(animated: !reduceMotion)"), "動きを減らす設定でも光を流している")
        XCTAssertTrue(view.contains(".gesture(rangeDrag(barWidth: barWidth))"))
        XCTAssertTrue(view.contains(".frame(minHeight: Self.chipHeight)"))
        XCTAssertEqual(StoryVideoTrimSheet.chipHeight, 32)
    }

    // MARK: - 03 曲の流し始め

    /// 帯の棒: 1 秒に 2 本・5 秒ごと > 毎秒 > 半秒（音の形に見せかけない等間隔の拍）
    func testSongStripBars() {
        XCTAssertEqual(SongStartStrip.barCount, 60)
        XCTAssertEqual(SongStartStrip.barHeight(0), SongStartStrip.tallBar)
        XCTAssertEqual(SongStartStrip.barHeight(1), SongStartStrip.halfBar)
        XCTAssertEqual(SongStartStrip.barHeight(2), SongStartStrip.secondBar)
        XCTAssertEqual(SongStartStrip.barHeight(10), SongStartStrip.tallBar)
        XCTAssertEqual(SongStartStrip.barTime(25), 12.5)
    }

    /// 棒の塗り: 枠の外は灰・枠の中は鳴った所まで白
    func testSongStripTones() {
        XCTAssertEqual(SongStartStrip.tone(index: 22, start: 12, window: 5, played: 0), .outside)
        XCTAssertEqual(SongStartStrip.tone(index: 24, start: 12, window: 5, played: 0), .played)
        XCTAssertEqual(SongStartStrip.tone(index: 26, start: 12, window: 5, played: 0), .upcoming)
        XCTAssertEqual(SongStartStrip.tone(index: 26, start: 12, window: 5, played: 1.2), .played)
        XCTAssertEqual(SongStartStrip.tone(index: 34, start: 12, window: 5, played: 0), .outside)
    }

    /// 枠の位置と掴み方・流し始めの丸め（表示秒数が試聴に収まる所まで）
    func testSongStripWindowAndDrag() {
        let frame = SongStartStrip.windowFraction(start: 12, window: 5)
        XCTAssertEqual(frame.left, 0.4, accuracy: 0.0001)
        XCTAssertEqual(frame.width, 5.0 / 30.0, accuracy: 0.0001)
        // 枠の中を押したらその位置のまま、外を押したら真ん中を指の下へ
        XCTAssertEqual(SongStartStrip.grabOffset(touchSeconds: 14, start: 12, window: 5), 2)
        XCTAssertEqual(SongStartStrip.grabOffset(touchSeconds: 3, start: 12, window: 5), 2.5)
        XCTAssertEqual(SongStartStrip.start(touchSeconds: 20, grab: 2, window: 5), 18)
        XCTAssertEqual(SongStartStrip.start(touchSeconds: 29.9, grab: 0, window: 5), 25, "表示秒数が試聴の外へはみ出す")
        XCTAssertEqual(SongStartStrip.start(touchSeconds: 1, grab: 2.5, window: 5), 0)
        XCTAssertEqual(SongStartStrip.seconds(atX: 150, width: 300), 15)
        XCTAssertEqual(SongStartStrip.clock(12), "0:12")
        XCTAssertEqual(SongStartStrip.lengthNote(window: 5), "から 5秒")
    }

    /// 試聴の状態: 自分で止めていないのに鳴っていなければ「流せない」
    func testSongPlaybackStates() {
        XCTAssertEqual(SongStartStrip.playback(mine: false, playing: false, stoppedByMe: false, itemFailed: false, waiting: false), .idle)
        XCTAssertEqual(SongStartStrip.playback(mine: true, playing: true, stoppedByMe: false, itemFailed: false, waiting: true), .loading)
        XCTAssertEqual(SongStartStrip.playback(mine: true, playing: true, stoppedByMe: false, itemFailed: false, waiting: false), .playing)
        XCTAssertEqual(SongStartStrip.playback(mine: true, playing: false, stoppedByMe: false, itemFailed: false, waiting: false), .failed)
        XCTAssertEqual(SongStartStrip.playback(mine: true, playing: false, stoppedByMe: true, itemFailed: false, waiting: false), .idle)
        XCTAssertEqual(SongStartStrip.playback(mine: true, playing: true, stoppedByMe: false, itemFailed: true, waiting: false), .failed)
    }

    /// 画面の配線: 決めるのは下の主ボタン（写真の無い画面なので真鍮）・上の「決める」をやめた・画面いっぱいで出す
    func testSongStartWiring() throws {
        let view = try repo("Sources/JourneyPhoto/Features/Stories/SongStartSheet.swift")
        XCTAssertTrue(view.contains("Text(L(\"この位置にする\", \"Use this point\")).jpPillButton(.main(onPhoto: false))"))
        XCTAssertFalse(view.contains("L(\"決める\""), "上の「決める」が残っている")
        XCTAssertFalse(view.contains("Slider("), "細い横棒のまま")
        XCTAssertTrue(view.contains("length: Double(window)"), "枠の秒数ぶんを繰り返していない")
        XCTAssertTrue(view.contains(".onAppear { if playedSession == nil { playFromStart() } }"))
        XCTAssertTrue(view.contains(".accessibilityAdjustableAction"))
        let composer = try repo("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        let song = try XCTUnwrap(composer.components(separatedBy: "SongStartSheet(song: song").dropFirst().first)
        XCTAssertTrue(String(song.prefix(500)).contains(".presentationDetents([.large])"))
    }

    // MARK: - 04 ハイライト

    func testHighlightLabels() {
        XCTAssertEqual(HighlightService.titleCount(""), "0/30")
        XCTAssertEqual(HighlightService.titleCount("金沢"), "2/30")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(HighlightService.dayLabel("2026-09-12T10:00:00.000Z", calendar: utc), "9/12")
        XCTAssertEqual(HighlightService.dayLabel("2026-10-03T23:59:59Z", calendar: utc), "10/3")
        XCTAssertNil(HighlightService.dayLabel(nil))
        XCTAssertNil(HighlightService.dayLabel("きのう"))
        XCTAssertEqual(HighlightService.cellLabel(day: "9/12", order: 2, isCover: true), "9/12、2件目、表紙")
        XCTAssertEqual(HighlightService.cellLabel(day: "9/12", order: nil, isCover: false), "9/12")
    }

    /// 画面の配線: 表の形をやめて輪・名前・3 列の格子。表紙を選べる・空から作りに行ける・保存中は回る印
    func testHighlightEditorWiring() throws {
        let view = try repo("Sources/JourneyPhoto/Features/Profile/HighlightEditorView.swift")
        XCTAssertFalse(view.contains("Form {"), "設定の表の形のまま")
        XCTAssertTrue(view.contains("LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2)"))
        XCTAssertTrue(view.contains(".sheet(isPresented: $showCoverPicker) { coverPicker }"), "表紙を選べない")
        XCTAssertTrue(view.contains("coverId = id"))
        XCTAssertTrue(view.contains("actionIdentifier: \"highlightEditor.makeStory\") { showComposer = true }"),
                      "空から作りに行く口が無い")
        XCTAssertTrue(view.contains(".fullScreenCover(isPresented: $showComposer"))
        XCTAssertTrue(view.contains("if saving {"))
        // 名前の欄は 44pt の行のどこを押しても入れる（欄そのものは字の高さ・Mac run 1093）
        XCTAssertTrue(view.contains(".onTapGesture { nameFocused = true }"))
        XCTAssertTrue(view.contains(".focused($nameFocused)"))
        // 空と失敗を分ける（今の決まりのまま）・読み込み中は格子の骨組み
        XCTAssertTrue(view.contains("ErrorBanner(title: L(\"ストーリーを読み込めませんでした\""))
        XCTAssertTrue(view.contains("JPLoadingState(kind: .grid)"))
        // 危険の色はテーマの赤（系統の赤を行に出さない）
        XCTAssertTrue(view.contains(".foregroundStyle(WebTheme.danger)"))
        XCTAssertFalse(view.contains("role: .destructive) {\n            showDeleteConfirm"))
    }

    // MARK: - 区切りの中黒（2026-11-12 owner）

    /// この章で足した画面の文に「・」「·」の区切りを使わない（字の太さ・色と余白か改行、文の中は「、」で分ける）
    func testNoMiddleDotSeparatorsInAddedText() throws {
        let built = [
            StoryCameraRules.countdownNote(seconds: 3, action: .takePhoto),
            StoryCameraRules.countdownNote(seconds: 10, action: .startRecording),
            StoryCameraRules.countdownCancelHint,
            StoryCameraRules.failureNote,
            StoryCameraRules.limitLabel,
            StoryVideoTrim(total: 144).totalNote,
            StoryVideoTrim(total: 144).limitNote ?? "",
            StoryVideoTrim(total: 144).rangeLabel,
            StoryVideoTrim.cannotOpenMessage,
            SongStartStrip.lengthNote(window: 5),
            HighlightService.cellLabel(day: "9/12", order: 2, isCover: true),
            HighlightService.titleCount("金沢"),
        ]
        for text in built {
            XCTAssertFalse(text.contains("·") || text.contains("・"), text)
        }
        // この章で書き起こした画面（全部この章の文）は、表の言葉（`L(` の行）に中黒を置かない
        for path in ["Sources/JourneyPhoto/Features/Stories/SongStartSheet.swift",
                     "Sources/JourneyPhoto/Features/Profile/HighlightEditorView.swift",
                     "Sources/JourneyPhoto/Core/Text/SongStartStrip.swift"] {
            let source = try repo(path)
            for line in source.split(separator: "\n") where line.contains("L(\"") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                XCTAssertFalse(line.contains("·") || line.contains("・"), "\(path): \(line)")
            }
        }
        // 数えている案内・全体の注記は、字の大きさ・色と余白で分けている
        let camera = try repo("Sources/JourneyPhoto/Features/Stories/StoryCameraView.swift")
        XCTAssertTrue(camera.contains("Text(StoryCameraRules.countdownCancelHint)"))
        let trim = try repo("Sources/JourneyPhoto/Features/Stories/StoryVideoTrimView.swift")
        XCTAssertTrue(trim.contains("if let limit = trim.limitNote { Text(limit) }"))
    }
}
