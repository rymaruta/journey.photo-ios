import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 自動の結びの表（`/app/data/spot-photo-links.json`）と、投稿の候補の索引（`/app/data/spot-match.json`）の
/// 読み方（2026-10-31・journey.photo-ios#425）。**撮影スポットの索引と同じ仕組み**（控え → 条件付きの通信 →
/// 圏外・5xx・HTML・壊れた中身は前回の控え → 404 は控えも消して空）
final class SpotPhotoLinksServiceTests: XCTestCase {

    private var session: URLSession!
    private let url = URL(string: "https://site.example.test/app/data/spots.json")!
    private var prefixes: [String] = []

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset()
    }

    override func tearDown() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        for prefix in prefixes {
            for name in ["spot-photo-links.json", "spot-match.json"] {
                let file = caches.appendingPathComponent("\(prefix)-\(name)")
                try? FileManager.default.removeItem(at: file)
                try? FileManager.default.removeItem(at: file.appendingPathExtension("validator"))
            }
        }
        prefixes = []
        StubProtocol.reset()
        super.tearDown()
    }

    /// 同じ `prefix` なら同じ端末の控えを読む（開き直したアプリ）
    private func service(prefix: String) -> OfficialSpotService {
        if !prefixes.contains(prefix) { prefixes.append(prefix) }
        return OfficialSpotService(url: url, session: session, snapshot: SpotSnapshotStore(fileName: "\(prefix)-legacy"),
                                   feedSnapshotPrefix: prefix)
    }

    private let table = #"{"v":1,"links":{"p1":"sp_a","p2":"sp_b"}}"#

    func testReadsTableNextToTheSpotIndex() async {
        StubProtocol.respond(path: "/app/data/spot-photo-links.json", status: 200, body: table)
        let links = await service(prefix: UUID().uuidString).fetchPhotoLinks()
        XCTAssertEqual(links.links, ["p1": "sp_a", "p2": "sp_b"])
        XCTAssertEqual(StubProtocol.requests, ["GET /app/data/spot-photo-links.json"])
    }

    /// 60秒は控えを使い回す（写真を開くたびに叩かない）
    func testSecondReadUsesMemory() async {
        StubProtocol.respond(path: "/app/data/spot-photo-links.json", status: 200, body: table)
        let s = service(prefix: UUID().uuidString)
        _ = await s.fetchPhotoLinks()
        _ = await s.fetchPhotoLinks()
        XCTAssertEqual(StubProtocol.requestCount, 1)
    }

    /// 5xx・HTML（キャプティブポータル）・壊れた中身・圏外は、前回の良い控え
    func testFailuresFallBackToThePreviousSnapshot() async {
        let prefix = UUID().uuidString
        StubProtocol.respond(path: "/app/data/spot-photo-links.json", status: 200, body: table)
        _ = await service(prefix: prefix).fetchPhotoLinks()

        StubProtocol.reset()
        StubProtocol.respond(path: "/app/data/spot-photo-links.json", status: 500, body: "oops")
        let after500 = await service(prefix: prefix).fetchPhotoLinks()
        XCTAssertEqual(after500.links["p1"], "sp_a", "5xx で表を捨てた")

        StubProtocol.reset()
        StubProtocol.respond(status: 200, body: "<html>login</html>", contentType: "text/html")
        let afterHTML = await service(prefix: prefix).fetchPhotoLinks()
        XCTAssertEqual(afterHTML.links["p1"], "sp_a", "ログイン画面を表として読んだ")

        StubProtocol.reset()
        StubProtocol.respond(path: "/app/data/spot-photo-links.json", status: 200, body: #"{"v":9}"#)
        let afterBroken = await service(prefix: prefix).fetchPhotoLinks()
        XCTAssertEqual(afterBroken.links["p1"], "sp_a", "読めない中身で前の控えを上書きした")

        StubProtocol.reset()
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        let offline = await service(prefix: prefix).fetchPhotoLinks()
        XCTAssertEqual(offline.links["p1"], "sp_a", "圏外で表が消えた")
    }

    /// 404 は「下げた」。控えも消して空（`spotId` だけで引く）
    func testNotFoundClearsTheSnapshot() async {
        let prefix = UUID().uuidString
        StubProtocol.respond(path: "/app/data/spot-photo-links.json", status: 200, body: table)
        _ = await service(prefix: prefix).fetchPhotoLinks()
        StubProtocol.reset()
        StubProtocol.respond(path: "/app/data/spot-photo-links.json", status: 404, body: "")
        let gone = await service(prefix: prefix).fetchPhotoLinks()
        XCTAssertEqual(gone, .empty)
        StubProtocol.reset()
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        let offline = await service(prefix: prefix).fetchPhotoLinks()
        XCTAssertEqual(offline, .empty, "下げた表を圏外で出し続けた")
    }

    /// 本人が外した・戻した分は、サイトの作り直しを待たずに表へ重ねる
    func testNotedOverridesAreLayeredOnTheTable() async throws {
        StubProtocol.respond(path: "/app/data/spot-photo-links.json", status: 200, body: table)
        let s = service(prefix: UUID().uuidString)
        await s.noteSpotAuto(photoId: "p1", .off(spotId: "sp_a"))
        let links = await s.fetchPhotoLinks()
        XCTAssertNil(links.spotId(for: try SpotAutoLinkTests.photo(["id": "p1"])))
        XCTAssertEqual(links.spotId(for: try SpotAutoLinkTests.photo(["id": "p2"])), "sp_b")
    }

    /// 写真の詳細で外したら、開いたままの地図の数も読み直してそろう（`SpotLinkRevision`）。
    /// 同じ回の値では読み直さない（出直すたびに走る `.task` で無駄に読まない）
    @MainActor
    func testMapRefreshesLinksAfterARevision() async throws {
        StubProtocol.respond(path: "/app/data/spot-photo-links.json", status: 200, body: table)
        let s = service(prefix: UUID().uuidString)
        let model = PhotoMapViewModel()
        await model.refreshPhotoLinks(revision: 0, spots: s)
        XCTAssertEqual(model.photoLinks, .empty, "知らせの無い回に読み直した")
        await s.noteSpotAuto(photoId: "p1", .off(spotId: "sp_a"))
        await model.refreshPhotoLinks(revision: 1, spots: s)
        XCTAssertNil(model.photoLinks.spotId(for: try SpotAutoLinkTests.photo(["id": "p1"])), "外した写真を数えたまま")
        XCTAssertEqual(model.photoLinks.spotId(for: try SpotAutoLinkTests.photo(["id": "p2"])), "sp_b")
    }

    /// 読んでいる途中で取り消された回は「反映済み」にしない（次に出直したとき、同じ回の値で読み直す）
    @MainActor
    func testCancelledRefreshIsNotRecorded() async throws {
        StubProtocol.respond(path: "/app/data/spot-photo-links.json", status: 200, body: table)
        let s = service(prefix: UUID().uuidString)
        let model = PhotoMapViewModel()
        await s.noteSpotAuto(photoId: "p1", .off(spotId: "sp_a"))
        let cancelled = Task { @MainActor in await model.refreshPhotoLinks(revision: 1, spots: s) }
        cancelled.cancel()
        await cancelled.value
        XCTAssertEqual(model.photoLinks, .empty, "前提: 取り消された回は表を入れない")
        // 同じ回の値でもう一度（画面に出直した）。記録していなければ読み直して入る
        await model.refreshPhotoLinks(revision: 1, spots: s)
        XCTAssertEqual(model.photoLinks.spotId(for: try SpotAutoLinkTests.photo(["id": "p2"])), "sp_b",
                       "取り消された回を反映済みにして、読み直さなかった")
        XCTAssertNil(model.photoLinks.spotId(for: try SpotAutoLinkTests.photo(["id": "p1"])))
    }

    func testMatchIndexIsReadOnceAndBrokenIsNil() async {
        StubProtocol.respond(path: "/app/data/spot-match.json", status: 200,
                             body: #"{"v":1,"spots":[{"i":"sp_a","d":"蔵王キツネ村","n":"蔵王キツネ村"}]}"#)
        let s = service(prefix: UUID().uuidString)
        let index = await s.fetchMatchIndex()
        XCTAssertEqual(index?.rows.map(\.id), ["sp_a"])
        _ = await s.fetchMatchIndex()
        XCTAssertEqual(StubProtocol.requestCount, 1)

        StubProtocol.reset()
        StubProtocol.respond(path: "/app/data/spot-match.json", status: 200, body: "<html>")
        let broken = await service(prefix: UUID().uuidString).fetchMatchIndex()
        XCTAssertNil(broken, "読めない索引で候補を選んだ")
    }

    /// 外す・戻すの本文（`PUT /photos/{id}`）。外すは `"off"`、戻すは null
    func testPatchEncodesSpotAuto() throws {
        var off = PhotoPatch()
        off.spotAuto = .off
        XCTAssertFalse(off.isEmpty)
        let offJSON = try XCTUnwrap(String(data: try JSONEncoder().encode(off), encoding: .utf8))
        XCTAssertEqual(offJSON, #"{"spotAuto":"off"}"#)
        var back = PhotoPatch()
        back.spotAuto = .auto
        XCTAssertEqual(String(data: try JSONEncoder().encode(back), encoding: .utf8), #"{"spotAuto":null}"#)
        XCTAssertEqual(String(data: try JSONEncoder().encode(PhotoPatch()), encoding: .utf8), "{}", "触らないときは送らない")
    }
}
