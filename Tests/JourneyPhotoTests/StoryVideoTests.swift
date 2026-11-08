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
        let all: [StoryVideoRules.Problem] = [.tooLong, .unreadable, .tooLarge, .locationRemains, .exportFailed, .importFailed]
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
}
