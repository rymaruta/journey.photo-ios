import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// ストーリーの動画（札 #500・owner 2026-11-08）。上限は Web と同じ 60 秒・50MB、許可は mp4 / webm / mov。
/// AVFoundation に触る書き出しの本物は Mac の CI と実機で確かめる。ここは決まりと、送る形と、圏外の預かり。
final class StoryVideoTests: XCTestCase {

    // MARK: - 上限

    func testLimitsMatchTheWebAndTheServer() {
        XCTAssertEqual(StoryVideoRules.maxSeconds, 60)
        XCTAssertEqual(StoryVideoRules.maxBytes, 50 * 1024 * 1024, "サーバーの MAX_UPLOAD_BYTES")
        XCTAssertLessThan(StoryVideoRules.targetBytes, StoryVideoRules.maxBytes, "上限ちょうどに寄せている")
        XCTAssertEqual(Set(StoryVideoRules.allowedFileTypes), ["video/mp4", "video/quicktime", "video/webm"])
        XCTAssertTrue(StoryVideoRules.allowedFileTypes.contains(StoryVideoRules.exportFileType), "書き出す形が許可に無い")
    }

    func testDurationCheck() {
        XCTAssertNil(StoryVideoRules.problem(durationSec: 12))
        XCTAssertNil(StoryVideoRules.problem(durationSec: 60), "ちょうど60秒を断っている")
        XCTAssertNil(StoryVideoRules.problem(durationSec: 60.3), "撮影が60秒で止まった動画（少し超える）を断っている")
        XCTAssertEqual(StoryVideoRules.problem(durationSec: 61), .tooLong)
        XCTAssertEqual(StoryVideoRules.problem(durationSec: 0), .unreadable)
        XCTAssertEqual(StoryVideoRules.problem(durationSec: nil), .unreadable)
        XCTAssertEqual(StoryVideoRules.problem(durationSec: .nan), .unreadable)
    }

    func testExportedSizeCheck() {
        XCTAssertNil(StoryVideoRules.problem(exportedBytes: StoryVideoRules.maxBytes))
        XCTAssertEqual(StoryVideoRules.problem(exportedBytes: StoryVideoRules.maxBytes + 1), .tooLarge)
        XCTAssertEqual(StoryVideoRules.problem(exportedBytes: 0), .exportFailed)
    }

    func testEveryProblemHasAMessage() {
        let all: [StoryVideoRules.Problem] = [.tooLong, .unreadable, .tooLarge, .locationRemains, .exportFailed, .importFailed, .importTimedOut]
        for problem in all {
            XCTAssertFalse(problem.message.isEmpty)
            XCTAssertEqual(problem.errorDescription, problem.message, "送れなかった知らせに出る言葉が違う")
        }
    }

    // MARK: - 種類

    func testFileTypes() {
        XCTAssertEqual(StoryVideoRules.fileType(forExtension: "MP4"), "video/mp4")
        XCTAssertEqual(StoryVideoRules.fileType(forExtension: "mov"), "video/quicktime")
        XCTAssertEqual(StoryVideoRules.fileType(forExtension: "webm"), "video/webm")
        XCTAssertNil(StoryVideoRules.fileType(forExtension: "avi"))
        XCTAssertEqual(StoryVideoRules.fileExtension(forFileType: "video/quicktime"), "mov")
        XCTAssertEqual(StoryVideoRules.fileExtension(forFileType: "video/mp4; codecs=avc1"), "mp4")
        XCTAssertNil(StoryVideoRules.fileExtension(forFileType: "image/jpeg"))
    }

    // MARK: - 書き出しの段

    /// 長さに対して45MBに収まりそうな段から始める。60秒は1080pが収まらない、10秒は全部収まる
    func testLadderStartsAtWhatFits() {
        XCTAssertEqual(StoryVideoRules.ladder(durationSec: 10).first?.preset, "AVAssetExportPreset1920x1080")
        XCTAssertEqual(StoryVideoRules.ladder(durationSec: 60).first?.preset, "AVAssetExportPreset1280x720",
                       "60秒を1080pから試している（50MBに収まらず無駄に書き出す）")
        for seconds in [1.0, 15, 30, 45, 60] {
            let ladder = StoryVideoRules.ladder(durationSec: seconds)
            XCTAssertFalse(ladder.isEmpty)
            // 下へ行くほど小さい
            XCTAssertEqual(ladder.map(\.estimatedBitsPerSecond), ladder.map(\.estimatedBitsPerSecond).sorted(by: >))
        }
        // どれも収まりそうにない長さでも最後の段だけは試す（空にしない）
        XCTAssertEqual(StoryVideoRules.ladder(durationSec: 100_000).count, 1)
    }

    // MARK: - 位置情報

    func testLocationIdentifiers() {
        XCTAssertTrue(StoryVideoRules.isLocationIdentifier("mdta/com.apple.quicktime.location.ISO6709"))
        XCTAssertTrue(StoryVideoRules.isLocationIdentifier("udta/©xyz"))
        XCTAssertTrue(StoryVideoRules.isLocationIdentifier("common/location"))
        XCTAssertFalse(StoryVideoRules.isLocationIdentifier("mdta/com.apple.quicktime.make"))
        XCTAssertFalse(StoryVideoRules.isLocationIdentifier(""))
    }

    func testDurationLabel() {
        XCTAssertEqual(StoryVideoClip.label(0), "0:00")
        XCTAssertEqual(StoryVideoClip.label(12.4), "0:12")
        XCTAssertEqual(StoryVideoClip.label(60), "1:00")
    }

    // MARK: - 投稿の本文

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset()
    }

    override func tearDown() {
        StubProtocol.reset()
        super.tearDown()
    }

    private func service() -> StoryService {
        StoryService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                    tokenProvider: StubTokenProvider(token: "t"), session: session))
    }

    private let media = StoryService.UploadedMedia(
        key: "uploads/me/abc.mp4", publicUrl: "https://bucket.example/uploads/me/abc.mp4", uploadedAt: Date())

    private func sentBody() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(StubProtocol.lastBody)) as? [String: Any])
    }

    /// 動画は mediaType=video で送り、位置・座標・表示秒数・撮影地の札の印は付けない（サーバーも捨てる）
    func testVideoBodyCarriesNoLocationCoordsOrDuration() async throws {
        StubProtocol.respond(status: 201, body: #"{"success":true}"#)
        _ = try await service().createRecord(media, caption: "ひとこと", location: "高屋神社",
                                             coords: Photo.Coords(lat: 34.1, lng: 133.6), durationSec: 10,
                                             locationOnPhoto: true, mediaType: "video")
        let body = try sentBody()
        XCTAssertEqual(body["mediaType"] as? String, "video")
        XCTAssertEqual(body["caption"] as? String, "ひとこと", "動画のひとことまで消している")
        XCTAssertNil(body["location"], "動画に位置を付けている")
        XCTAssertNil(body["coords"], "動画に座標を付けている")
        XCTAssertNil(body["durationSec"], "動画に表示秒数を付けている")
        XCTAssertNil(body["locationOnPhoto"], "動画に撮影地の札の印を付けている")
    }

    /// 写真は今までどおり（回帰）
    func testImageBodyStillCarriesLocationAndDuration() async throws {
        StubProtocol.respond(status: 201, body: #"{"success":true}"#)
        _ = try await service().createRecord(media, caption: nil, location: "高屋神社",
                                             coords: Photo.Coords(lat: 34.1, lng: 133.6), durationSec: 10)
        let body = try sentBody()
        XCTAssertEqual(body["mediaType"] as? String, "image")
        XCTAssertEqual(body["location"] as? String, "高屋神社")
        XCTAssertNotNil(body["coords"])
        XCTAssertEqual(body["durationSec"] as? Int, 10)
    }

    // MARK: - 圏外の預かり

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("storyvideo-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private struct Boom: LocalizedError { var errorDescription: String? { "通信できませんでした" } }

    @MainActor
    private func settle(_ center: StoryUploadCenter) async {
        for _ in 0..<400 {
            if case .sending = center.phase { await Task.yield() } else { return }
        }
    }

    /// 動画の1本は、本体ごと預かる（強制終了のあとで戻しても動画のまま送れる）
    @MainActor
    func testVideoJobSurvivesARelaunch() async throws {
        let dir = tempDir()
        let source = tempDir().appendingPathComponent("out.mp4")
        try Data([1, 2, 3, 4]).write(to: source)
        let center = StoryUploadCenter(directory: dir)
        var release = false
        center.start([StoryUploadCenter.Job(imageData: Data([9]), caption: "", location: "", coords: nil,
                                            song: nil, durationSec: 5, archive: false,
                                            video: StoryUploadCenter.Video(fileURL: source, fileType: "video/mp4"))],
                     ownerId: "me", currentUserId: { "me" },
                     send: { _, _ in
            while !release { await Task.yield() }
            throw Boom()
        })
        for _ in 0..<200 { await Task.yield() }

        let relaunched = StoryUploadCenter(directory: dir)
        var seen: [(String?, Data?)] = []
        relaunched.configure(currentUserId: { "me" }, send: { job, _ in
            seen.append((job.video?.fileType, job.video.flatMap { try? Data(contentsOf: $0.fileURL) }))
        }, discardUpload: { _ in })
        relaunched.retry()
        await settle(relaunched)
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.0, "video/mp4", "戻したら動画でなくなった")
        XCTAssertEqual(seen.first?.1, Data([1, 2, 3, 4]), "動画の本体を預かっていない")
        release = true
        center.userChanged(to: nil)
    }

    // MARK: - 札 #500 の直し(書き出しの大きさ・確かめ・閉じる確認)

    /// 重ねを焼くときは段の大きさまで縮める(4K を 1080p の段で 4K のまま書き出して 50MB を超えない)
    func testRenderSizeShrinksToTheStep() {
        let p1080 = StoryVideoRules.allSteps[0], p720 = StoryVideoRules.allSteps[1]
        let uhd = CGSize(width: 2160, height: 3840) // 縦の 4K
        let fitted = StoryVideoRules.renderSize(for: uhd, step: p1080)
        XCTAssertEqual(fitted.height, 1920)
        XCTAssertEqual(fitted.width, 1080)
        XCTAssertEqual(StoryVideoRules.renderSize(for: uhd, step: p720).height, 1280)
        // 小さい動画は拡大しない
        XCTAssertEqual(StoryVideoRules.renderSize(for: CGSize(width: 540, height: 960), step: p1080),
                       CGSize(width: 540, height: 960))
        // 画素は偶数
        let odd = StoryVideoRules.renderSize(for: CGSize(width: 1001, height: 1779), step: p1080)
        XCTAssertEqual(Int(odd.width) % 2, 0)
        XCTAssertEqual(Int(odd.height) % 2, 0)
    }

    func testOverlayFrameRateCapsAt30() {
        XCTAssertEqual(StoryVideoRules.overlayFrameRate(source: 60), 30)
        XCTAssertEqual(StoryVideoRules.overlayFrameRate(source: 24), 24)
        XCTAssertEqual(StoryVideoRules.overlayFrameRate(source: 0), 30)
        XCTAssertEqual(StoryVideoRules.overlayFrameRate(source: .nan), 30)
    }

    /// 送る直前の確かめ: 書き出し済みでない・重ねが変わったときは出さずに書き出し直す
    func testExportCheck() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(StoryVideoRules.exportCheck(videoShots: [a, b], exported: [a, b], overlaysMatch: true), .ok)
        XCTAssertEqual(StoryVideoRules.exportCheck(videoShots: [a, b], exported: [a], overlaysMatch: true), .reexport,
                       "書き出していない動画を静止画で出している")
        XCTAssertEqual(StoryVideoRules.exportCheck(videoShots: [a], exported: [a, b], overlaysMatch: true), .reexport,
                       "外した動画の書き出しが残っている")
        XCTAssertEqual(StoryVideoRules.exportCheck(videoShots: [a], exported: [a], overlaysMatch: false), .reexport,
                       "書き出したあとに変えた重ねが載っていない")
        XCTAssertEqual(StoryVideoRules.exportCheck(videoShots: [], exported: [], overlaysMatch: true), .ok)
    }

    /// 動画が入っていて下書きに残せないときの閉じる確認(「前の下書きはそのまま残ります」を言わない)
    func testLeaveDialogForVideo() {
        let dialog = StoryComposerView.leaveDialog(canSaveDraft: false, loading: false, restored: false, hasVideo: true)
        XCTAssertFalse(dialog.canSave)
        XCTAssertTrue(dialog.message.contains("動画が入っていると下書きに残せません"))
        XCTAssertFalse(dialog.message.contains("前の下書きはそのまま残ります"))
        let plain = StoryComposerView.leaveDialog(canSaveDraft: false, loading: false, restored: false)
        XCTAssertTrue(plain.message.contains("前の下書きはそのまま残ります"), "写真だけの回の言い分を変えている")
    }

    private func repo(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 画面の配線: 書き出し中は編集を止める・取り消せる・動画では効かない操作を出さない・一時ファイルの持ち主
    func testComposerWiring() throws {
        let composer = try repo("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(composer.contains(".overlay { if isExportingVideo { exportOverlay } }"), "書き出し中に編集を止めていない")
        XCTAssertTrue(composer.contains("guard !uploads.isBusy else"), "ほかのストーリーを送っている間も書き出している")
        XCTAssertTrue(composer.contains("StoryVideoRules.exportCheck("), "送る直前に動画の書き出しを確かめていない")
        XCTAssertTrue(composer.contains("if currentClip == nil {\n                Menu {\n                    durationOptions"), "動画に表示秒数を出している")
        XCTAssertTrue(composer.contains("if currentClip == nil, !framing.wrappedValue.isIdentity"), "動画に合わせ方を出している")
        XCTAssertTrue(composer.contains("AsyncTimeout.firstWithin(\n                        seconds: StorySimpleRules.pickLoadTimeout"), "動画の読み込みに時間切れが無い")
        XCTAssertTrue(composer.contains("hasVideo: hasVideoShot"))
        // 閉じる・外す・投稿のどの経路でも消す
        XCTAssertTrue(composer.contains("discardAllVideos()"))
        XCTAssertFalse(composer.contains("StoryVideoPipeline.discard(shots[index].video)"), "外すが持ち主の控えを更新しない")
    }

    func testPipelineExportIsCancellableAndStripsMetadata() throws {
        let pipeline = try repo("Sources/JourneyPhoto/Services/StoryVideoPipeline.swift")
        XCTAssertTrue(pipeline.contains("withTaskCancellationHandler"))
        XCTAssertTrue(pipeline.contains("cancelExport()"), "取り消しが書き出しを止めない")
        XCTAssertTrue(pipeline.contains("AVMutableComposition()"), "重ねなしの書き出しが元の付帯情報を持ち込む")
        XCTAssertTrue(pipeline.contains("CMMetadataFormatDescriptionGetIdentifiers"), "時刻つきの付帯情報を見ていない")
        XCTAssertTrue(pipeline.contains("track.load(.metadata)"), "トラックごとの付帯情報を見ていない")
        XCTAssertTrue(pipeline.contains("for _ in 0..<2"), "位置情報が残ったとき自動でやり直さない")
        XCTAssertTrue(pipeline.contains("StoryVideoRules.renderSize(for: oriented, step: step)"))
    }
}
