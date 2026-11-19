import XCTest
@testable import JourneyPhoto

/// ストーリーの「＋」は**写真と動画の一覧**を先に開く（札 #627・2026-11-15 判断）。
/// owner「ストーリーを追加押すとカメラ起動しちゃう！」。今のインスタと同じ形: 一覧の最初のマスがカメラ、
/// マスを押せばそのまま作る段へ（「＋ → 選ぶ」の2回）。許可の無い人には前の写真選びと、許可を増やす1行
final class StoryLibraryFirstTests: XCTestCase {

    private static var repo: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: Self.repo.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: - 許可の段

    /// すべて・一部の許可は一覧。まだ聞いていない・許可していない人は前の写真選び（許可が要らない）と1行
    func testContentFollowsLibraryAccess() {
        XCTAssertEqual(StoryLibraryRules.content(for: .authorized), .grid(limited: false))
        XCTAssertEqual(StoryLibraryRules.content(for: .limited), .grid(limited: true),
                       "一部だけ許可した人に「写真を増やす」の1行が出ない")
        XCTAssertEqual(StoryLibraryRules.content(for: .notDetermined), .systemPicker(offer: .ask),
                       "まだ聞いていない人に、開いたとたん許可のダイアログを出さない（前の写真選びを出す）")
        XCTAssertEqual(StoryLibraryRules.content(for: .denied), .systemPicker(offer: .openSettings))
        XCTAssertEqual(StoryLibraryRules.content(for: .restricted), .systemPicker(offer: nil),
                       "本人が変えられない「制限」に、押しても何も変わらない1行を出している")
    }

    /// 1行の言葉は短く、押す前に何が起きるか分かる。中黒で区切らない・「捨てる」を使わない
    func testOfferWordingIsShortAndPlain() {
        let words = [StoryLibraryRules.offerTitle(.ask), StoryLibraryRules.offerTitle(.openSettings),
                     StoryLibraryRules.limitedNote, StoryLibraryRules.limitedAction, StoryLibraryRules.emptyTitle]
        for word in words {
            XCTAssertLessThanOrEqual(word.count, 20, "1行に収まらない: \(word)")
            XCTAssertFalse(word.contains("・") || word.contains("·"), "中黒で区切っている: \(word)")
            XCTAssertFalse(word.contains("捨て"), word)
        }
        XCTAssertTrue(StoryLibraryRules.offerTitle(.openSettings).contains("設定"), "設定へ飛ぶことが言葉から分からない")
    }

    // MARK: - 並べ方

    /// 2026-11-18（案 B1・owner 採用）: 投稿とストーリーで同じ一覧。模型どおり4列・正方形のマス
    /// （アクセシビリティの大きさでは3列）。前は板の3列と作る画面の枠に近い縦長（2:3）
    func testGridFollowsTheMockup() {
        XCTAssertEqual(StoryLibraryRules.columns(accessibilitySize: false), 4)
        XCTAssertEqual(StoryLibraryRules.columns(accessibilitySize: true), 3)
        XCTAssertEqual(StoryLibraryRules.cellAspect, 1.0, "マスが正方形でない（模型の 95×95）")
        XCTAssertEqual(StoryLibraryRules.cameraIconSize, 30)
        XCTAssertEqual(StoryLibraryRules.markedOpacity, 0.75)
        XCTAssertGreaterThanOrEqual(StoryLibraryRules.maxItems, 1000)
    }

    /// 写真と動画の両方を新しい順に取る（種類を絞らない口・並べ替えは作った日の新しい順）
    func testFeedFetchesPhotosAndVideosNewestFirst() throws {
        let source = try read("Sources/JourneyPhoto/Features/Common/LibraryGrid.swift")
        XCTAssertTrue(source.contains("PHAsset.fetchAssets(with: options)"), "種類を絞る口だと写真か動画の片方しか並ばない")
        XCTAssertTrue(source.contains("\"mediaType == %d || mediaType == %d\""))
        XCTAssertTrue(source.contains("PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue"))
        XCTAssertTrue(source.contains("NSSortDescriptor(key: \"creationDate\", ascending: false)"), "新しい順でない")
    }

    // MARK: - 動画の長さの印

    func testDurationLabel() {
        XCTAssertEqual(StoryLibraryRules.durationLabel(15), "0:15")
        XCTAssertEqual(StoryLibraryRules.durationLabel(65), "1:05")
        XCTAssertEqual(StoryLibraryRules.durationLabel(3723), "1:02:03")
        XCTAssertEqual(StoryLibraryRules.durationLabel(0.4), "0:01", "短い動画が「0:00」に見える")
        XCTAssertEqual(StoryLibraryRules.durationLabel(14.2), "0:15")
        XCTAssertEqual(StoryLibraryRules.durationLabel(-3), "0:00")
    }

    /// 読み上げは「動画、15秒、11月14日」。区切りは「、」
    func testAccessibilityLabel() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 9)))
        let video = StoryLibraryRules.Item(id: "v", isVideo: true, duration: 15, date: date)
        let photo = StoryLibraryRules.Item(id: "p", isVideo: false, duration: 0, date: nil)
        let videoLabel = StoryLibraryRules.accessibilityLabel(video, calendar: calendar)
        XCTAssertTrue(videoLabel == "動画、15秒、11月14日" || videoLabel == "Video, 15 seconds, 11/14", videoLabel)
        let photoLabel = StoryLibraryRules.accessibilityLabel(photo, calendar: calendar)
        XCTAssertTrue(photoLabel == "写真" || photoLabel == "Photo", photoLabel)
        XCTAssertFalse(videoLabel.contains("・"))
        XCTAssertEqual(StoryLibraryRules.spokenDuration(65), L("1分5秒", "1 min 5 sec"))
        XCTAssertEqual(StoryLibraryRules.spokenDuration(120), L("2分", "2 minutes"))
    }

    // MARK: - 押したとき

    /// ふだんはマスを押せばそのまま作る段へ（「＋ → 選ぶ」の2回）。読み込み中は何もしない
    func testTapOpensDirectly() {
        XCTAssertEqual(StoryLibraryRules.tapAction(selecting: false, isMarked: false, markedCount: 0, loading: false), .open,
                       "マスを押しても作る段へ進まない（押す回数が2回にならない）")
        XCTAssertEqual(StoryLibraryRules.tapAction(selecting: false, isMarked: false, markedCount: 0, loading: true), .ignore,
                       "読み込み中に別のマスを押すと、2本の読み込みが混ざって並ぶ")
        XCTAssertEqual(StoryLibraryRules.tapAction(selecting: true, isMarked: false, markedCount: 0, loading: false), .toggle)
        XCTAssertEqual(StoryLibraryRules.tapAction(selecting: true, isMarked: true, markedCount: StoryQueue.maxShots,
                                                   loading: false), .toggle, "上限まで印が付くと外せない")
        XCTAssertEqual(StoryLibraryRules.tapAction(selecting: true, isMarked: false, markedCount: StoryQueue.maxShots,
                                                   loading: false), .ignore)
    }

    /// 印は選んだ順。外したら詰める。上限を超えて付けない
    func testMarksKeepTheOrder() {
        var marked: [String] = []
        marked = StoryLibraryRules.toggled(marked, id: "a")
        marked = StoryLibraryRules.toggled(marked, id: "b")
        marked = StoryLibraryRules.toggled(marked, id: "c")
        XCTAssertEqual(marked, ["a", "b", "c"])
        marked = StoryLibraryRules.toggled(marked, id: "b")
        XCTAssertEqual(marked, ["a", "c"])
        XCTAssertEqual(StoryLibraryRules.markNumber(marked, id: "c"), 2)
        XCTAssertNil(StoryLibraryRules.markNumber(marked, id: "b"))
        let full = (0..<StoryQueue.maxShots).map { "\($0)" }
        XCTAssertEqual(StoryLibraryRules.toggled(full, id: "x"), full)
    }

    /// カメラのマスは「選択」の間・読み込み中は押せない（印の写真と撮った1枚の順が分からなくなる）
    func testCameraCellEnabled() {
        XCTAssertTrue(StoryLibraryRules.cameraEnabled(selecting: false, loading: false))
        XCTAssertFalse(StoryLibraryRules.cameraEnabled(selecting: true, loading: false))
        XCTAssertFalse(StoryLibraryRules.cameraEnabled(selecting: false, loading: true))
    }

    // MARK: - 画面のつなぎ

    /// 一覧の最初のマスがカメラで、押すと今のカメラ（`showCamera`）。マスを押すと一覧の読み込みへ
    func testComposerWiresTheGrid() throws {
        let grid = try read("Sources/JourneyPhoto/Features/Common/LibraryGrid.swift")
        let body = try XCTUnwrap(grid.range(of: "LazyVGrid(columns: columns"))
        let after = String(grid[body.lowerBound...].prefix(200))
        XCTAssertLessThan(try XCTUnwrap(after.range(of: "cameraCell")).lowerBound,
                          try XCTUnwrap(after.range(of: "ForEach(items)")).lowerBound, "カメラが最初のマスでない")
        let composer = try read("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(composer.contains("onCamera: { showCamera = true }"), "カメラのマスが今のカメラを開かない")
        XCTAssertTrue(composer.contains("Task { await loadLibraryItems([item]) }"), "マスを押しても読み込まない")
        // 許可の無い人には前の埋め込みの写真選び（壊さない）
        let picker = try XCTUnwrap(composer.range(of: "case .systemPicker(let offer):"))
        XCTAssertTrue(String(composer[picker.lowerBound...].prefix(600)).contains("(selection: $librarySelection,"), "許可の無い人に前の写真選びが出ない")
        // 写真選び（PHPicker）と一覧は同じ読み込みの道（写しを作らない）
        XCTAssertEqual(composer.components(separatedBy: "AsyncTimeout.firstWithin(").count, 2,
                       "動画の読み込みの上限時間を2か所に書いている")
        XCTAssertTrue(composer.contains("importVideo: { try await StoryVideoPipeline.importAsset(id: $0.id) }"))
        XCTAssertTrue(composer.contains("readPhoto: { await PhotoLibrary.imageData(for: $0.id) }"))
    }

    /// ライブラリの動画は、写す前に長さを確かめ、編集後のものを使い、iCloud からも落とす
    func testLibraryVideoImport() throws {
        let source = try read("Sources/JourneyPhoto/Services/StoryVideoPipeline.swift")
        let start = try XCTUnwrap(source.range(of: "fileprivate static func importAssetDarwin(id: String)"))
        let body = String(source[start.lowerBound...].prefix(1800))
        let check = try XCTUnwrap(body.range(of: "StoryVideoRules.importProblem(durationSec: asset.duration)"))
        let write = try XCTUnwrap(body.range(of: "writeData(for: resource"))
        XCTAssertLessThan(check.lowerBound, write.lowerBound, "長すぎる動画を写してから断っている")
        XCTAssertTrue(body.contains("$0.type == .fullSizeVideo"), "写真アプリで切った動画が元の長さで入る")
        XCTAssertTrue(body.contains("options.isNetworkAccessAllowed = true"), "iCloud にしか無い動画が読めない")
        XCTAssertTrue(body.contains("return try await prepare(fileAt: copy)"), "写真選びの動画と同じ確かめを通していない")
    }
}
