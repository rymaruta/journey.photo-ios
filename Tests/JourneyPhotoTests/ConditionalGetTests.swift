import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 静的 JSON（`photos.json`・`spots.json`）の**条件付きの取得**（2026-10-02）。
///
/// 前回の `ETag` を `If-None-Match` で送り、304 なら端末の控えの中身を使う。
/// 304 なのに控えが無い・壊れているときは、条件なしで取り直す。
/// 60秒の控えの判断は手前のままなので、ここでは `force: true` で通信まで行かせる。
final class ConditionalGetTests: XCTestCase {

    private var session: URLSession!
    private let photosURL = URL(string: "https://site.example.test/app/data/photos.json")!
    private let spotsURL = URL(string: "https://site.example.test/app/data/spots.json")!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset()
        AppConfig.testOverrides = [
            "JPEnvironmentName": "staging",
            "JPSiteBaseURL": "https://site.example.test",
            "JPUserApiBaseURL": "https://api.example.test",
            "JPCognitoUserPoolId": "pool",
            "JPCognitoClientId": "client",
            "JPCognitoRegion": "ap-northeast-1",
        ]
    }

    override func tearDown() {
        StubProtocol.reset()
        AppConfig.testOverrides = nil
        super.tearDown()
    }

    private let feed = """
    [{"id":"a","src":"https://x/a.jpg","category":"風景"},
     {"id":"b","src":"https://x/b.jpg","category":"食"},
     {"id":"c","src":"https://x/c.jpg","category":"風景"}]
    """
    private let newer = #"[{"id":"z","src":"https://x/z.jpg"}]"#

    private func gallery(_ name: String) -> PublicGalleryService {
        PublicGalleryService(url: photosURL, session: session, snapshot: PhotoSnapshotStore(fileName: name))
    }

    private func respond(_ status: Int, _ body: String, etag: String? = nil, lastModified: String? = nil) {
        StubProtocol.respond(status: status, body: body)
        var headers: [String: String] = [:]
        if let etag { headers["ETag"] = etag }
        if let lastModified { headers["Last-Modified"] = lastModified }
        StubProtocol.responseHeaders = headers
    }

    private func header(_ name: String, ofRequest index: Int) -> String? {
        StubProtocol.allRequests[index].value(forHTTPHeaderField: name)
    }

    /// 控えのファイル（`PhotoSnapshotStore` と同じ場所）
    private func snapshotFile(_ name: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
    }

    // MARK: - 写真の一覧

    /// 1回目は条件なし。**2回目に前回の印（`If-None-Match`・`If-Modified-Since`）が付く**
    func testSecondFetchSendsTheValidator() async throws {
        let name = UUID().uuidString
        respond(200, feed, etag: #"W/"v1""#, lastModified: "Fri, 02 Oct 2026 12:33:29 GMT")
        let service = gallery(name)
        _ = try await service.fetchPhotos()
        respond(304, "")
        _ = try await service.fetchPhotos(force: true)

        XCTAssertEqual(StubProtocol.allRequests.count, 2)
        XCTAssertNil(header("If-None-Match", ofRequest: 0), "1回目に条件を付けている")
        XCTAssertEqual(header("If-None-Match", ofRequest: 1), #"W/"v1""#, "2回目に前回の ETag が付いていない")
        XCTAssertEqual(header("If-Modified-Since", ofRequest: 1), "Fri, 02 Oct 2026 12:33:29 GMT")
    }

    /// 🔴 **304 なら控えの中身を返す**（本文は空）。アプリを開き直した後（別の入れ物）でも同じ
    func testNotModifiedReturnsTheSnapshot() async throws {
        let name = UUID().uuidString
        respond(200, feed, etag: #""v1""#)
        _ = try await gallery(name).fetchPhotos()

        respond(304, "")
        let same = try await gallery(name).fetchPhotos()
        XCTAssertEqual(same.map(\.id), ["a", "b", "c"], "304 で控えの中身を返していない")
        XCTAssertEqual(StubProtocol.allRequests.count, 2, "304 の後に取り直している")
        XCTAssertEqual(header("If-None-Match", ofRequest: 1), #""v1""#)
    }

    /// **200 なら新しい中身にし、印も新しい回のものに替える**
    func testOkReplacesTheContentAndTheValidator() async throws {
        let name = UUID().uuidString
        respond(200, feed, etag: #""v1""#)
        let service = gallery(name)
        _ = try await service.fetchPhotos()

        respond(200, newer, etag: #""v2""#)
        let updated = try await service.fetchPhotos(force: true)
        XCTAssertEqual(updated.map(\.id), ["z"])

        respond(304, "")
        let again = try await service.fetchPhotos(force: true)
        XCTAssertEqual(again.map(\.id), ["z"], "304 で古い回の中身を出している")
        XCTAssertEqual(header("If-None-Match", ofRequest: 2), #""v2""#, "印が新しい回のものになっていない")
    }

    /// 🔴 **304 なのに控えが壊れている → 印を捨てて、条件なしで取り直す**
    func testNotModifiedWithoutUsableSnapshotRefetchesUnconditionally() async throws {
        let name = UUID().uuidString
        respond(200, feed, etag: #""v1""#)
        _ = try await gallery(name).fetchPhotos()
        // 印は残ったまま、中身だけ壊れた
        try Data("<html>broken</html>".utf8).write(to: snapshotFile(name))

        StubProtocol.respondInOrder([(304, ""), (200, feed)])
        StubProtocol.responseHeaders = [:]
        let photos = try await gallery(name).fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(StubProtocol.allRequests.count, 3, "条件なしで取り直していない")
        XCTAssertEqual(header("If-None-Match", ofRequest: 1), #""v1""#)
        XCTAssertNil(header("If-None-Match", ofRequest: 2), "取り直しにも条件を付けている")
    }

    /// 304 なのに控えのファイルが消えている（OS が Caches を掃除した）ときも、条件なしで取り直す
    func testNotModifiedWithMissingSnapshotRefetches() async throws {
        let name = UUID().uuidString
        respond(200, feed, etag: #""v1""#)
        _ = try await gallery(name).fetchPhotos()
        try FileManager.default.removeItem(at: snapshotFile(name))

        StubProtocol.respondInOrder([(304, ""), (200, newer)])
        StubProtocol.responseHeaders = [:]
        let photos = try await gallery(name).fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["z"])
        XCTAssertNil(header("If-None-Match", ofRequest: 2))
    }

    /// 印の無い応答の後は条件を付けない（**前の回の印を残さない**）
    func testNoValidatorMeansNoCondition() async throws {
        let name = UUID().uuidString
        respond(200, feed, etag: #""v1""#)
        let service = gallery(name)
        _ = try await service.fetchPhotos()
        respond(200, newer)
        _ = try await service.fetchPhotos(force: true)
        respond(200, newer)
        _ = try await service.fetchPhotos(force: true)
        XCTAssertNil(header("If-None-Match", ofRequest: 2), "印の無い回の後に、前の回の印を送っている")
    }

    /// 控えなかった回（1件も読めなかった）の後も、前の回の印を送らない
    func testUnsavedResponseDropsTheValidator() async throws {
        let name = UUID().uuidString
        respond(200, feed, etag: #""v1""#)
        let service = gallery(name)
        _ = try await service.fetchPhotos()
        respond(200, #"[{"id":123}]"#, etag: #""v2""#)
        _ = try await service.fetchPhotos(force: true)
        respond(200, feed)
        _ = try await service.fetchPhotos(force: true)
        XCTAssertNil(header("If-None-Match", ofRequest: 2))
    }

    // MARK: - スポットの索引（同じ部品）

    func testSpotIndexUsesTheSnapshotOnNotModified() async throws {
        let name = UUID().uuidString
        StubProtocol.respond(status: 200, body: OfficialSpotServiceTests.threeSpots)
        StubProtocol.responseHeaders = ["ETag": #"W/"s1""#]
        _ = try await OfficialSpotService(url: spotsURL, session: session,
                                          snapshot: SpotSnapshotStore(fileName: name)).fetchIndex()

        respond(304, "")
        let spots = try await OfficialSpotService(url: spotsURL, session: session,
                                                  snapshot: SpotSnapshotStore(fileName: name)).fetchIndex()
        XCTAssertEqual(spots.count, 3, "304 で控えの索引を返していない")
        XCTAssertEqual(header("If-None-Match", ofRequest: 1), #"W/"s1""#)
        XCTAssertEqual(StubProtocol.allRequests.count, 2)
    }

    /// 404（索引を下げた）で控えを消したら、印も消える（次は条件なし）
    func testSpotIndexNotFoundForgetsTheValidator() async throws {
        let name = UUID().uuidString
        StubProtocol.respond(status: 200, body: OfficialSpotServiceTests.threeSpots)
        StubProtocol.responseHeaders = ["ETag": #""s1""#]
        let spots = OfficialSpotService(url: spotsURL, session: session, snapshot: SpotSnapshotStore(fileName: name))
        _ = try await spots.fetchIndex()
        respond(404, "not found")
        _ = try await spots.fetchIndex(force: true)
        respond(200, OfficialSpotServiceTests.threeSpots)
        _ = try await spots.fetchIndex(force: true)
        XCTAssertNil(header("If-None-Match", ofRequest: 2))
    }

    // MARK: - 部品

    func testValidatorReadsHeadersCaseInsensitively() {
        let response = HTTPURLResponse(url: photosURL, statusCode: 200, httpVersion: "HTTP/2",
                                       headerFields: ["etag": #"W/"x""#, "last-modified": "Wed, 30 Sep 2026 09:25:59 GMT"])!
        XCTAssertEqual(HTTPValidator(response: response),
                       HTTPValidator(etag: #"W/"x""#, lastModified: "Wed, 30 Sep 2026 09:25:59 GMT"))
        let bare = HTTPURLResponse(url: photosURL, statusCode: 200, httpVersion: "HTTP/2", headerFields: [:])!
        XCTAssertNil(HTTPValidator(response: bare))
    }
}
