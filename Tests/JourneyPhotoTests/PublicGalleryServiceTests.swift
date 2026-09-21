import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 公開一覧の読み込み。**壊れ方が画面に出る場所**なので、実際に走らせて見る。
final class PublicGalleryServiceTests: XCTestCase {

    private var session: URLSession!
    private let url = URL(string: "https://site.example.test/app/data/photos.json")!

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

    private func service(snapshot: String = UUID().uuidString) -> PublicGalleryService {
        PublicGalleryService(url: url, session: session, snapshot: PhotoSnapshotStore(fileName: snapshot))
    }

    private let twoPhotos = """
    [{"id":"a","src":"https://x/a.jpg","userId":"u1"},
     {"id":"b","src":"https://x/b.jpg","userId":"u2"}]
    """

    func testReadsPublishedPhotos() async throws {
        StubProtocol.respond(status: 200, body: twoPhotos)
        let photos = try await service().fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["a", "b"])
    }

    /// `published: false` が混ざっても出さない（二重の守り）。
    func testHidesUnpublishedRows() async throws {
        StubProtocol.respond(status: 200, body: """
        [{"id":"a","src":"https://x/a.jpg"},{"id":"draft","src":"https://x/d.jpg","published":false}]
        """)
        let photos = try await service().fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["a"])
    }

    /// **ブロックした相手と、通報した写真を落とす。**
    /// 公開一覧は静的な JSON なので、サーバー側では絞れない。
    func testHidesBlockedUsersAndReportedPhotos() async throws {
        StubProtocol.respond(status: 200, body: twoPhotos)
        let gallery = service()
        await gallery.setHidden(userIds: ["u2"], photoIds: [])
        var photos = try await gallery.fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["a"], "ブロックした相手の写真が出ている")

        await gallery.setHidden(userIds: [], photoIds: ["a"])
        photos = try await gallery.fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["b"], "通報した写真が出ている")
    }

    /// **圏外なら前回のぶんを出す。**
    func testFallsBackToSnapshotWhenOffline() async throws {
        let name = UUID().uuidString
        let gallery = service(snapshot: name)
        StubProtocol.respond(status: 200, body: twoPhotos)
        _ = try await gallery.fetchPhotos()

        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        let offline = try await service(snapshot: name).fetchPhotos()
        XCTAssertEqual(offline.map(\.id), ["a", "b"])
    }

    /// **壊れた応答を控えない。** キャプティブポータル（ホテルの Wi-Fi）は
    /// 200 でログイン HTML を返す。控えると、次から圏外でそれが出る。
    func testDoesNotCacheGarbageResponse() async throws {
        let name = UUID().uuidString
        StubProtocol.respond(status: 200, body: twoPhotos)
        _ = try await service(snapshot: name).fetchPhotos()

        StubProtocol.respond(status: 200, body: "<html>Wi-Fi にログインしてください</html>")
        // HTML は配列として読めないので、控えに落ちる
        let afterGarbage = try await service(snapshot: name).fetchPhotos()
        XCTAssertEqual(afterGarbage.map(\.id), ["a", "b"], "壊れた応答で控えが潰れた")
    }

    /// **1件も読めなかった回も控えを上書きしない。**
    func testDoesNotOverwriteSnapshotWhenEverythingIsUnreadable() async throws {
        let name = UUID().uuidString
        StubProtocol.respond(status: 200, body: twoPhotos)
        _ = try await service(snapshot: name).fetchPhotos()

        StubProtocol.respond(status: 200, body: #"[{"id":"x","src":123}]"#)
        _ = try await service(snapshot: name).fetchPhotos()

        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        let offline = try await service(snapshot: name).fetchPhotos()
        XCTAssertEqual(offline.map(\.id), ["a", "b"], "読めない応答で控えが潰れた")
    }
}
