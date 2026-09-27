import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 404 の読み方（バグ探し 2026-09-27 #12・#13）。
///
/// サーバーの 404 は「失敗」とは限らない:
/// - いいねの解除（DELETE）の 404 は、印を消したあとに「数を出せない」と言っているだけ（`likes.ts`）
/// - いいね・保存（POST）の 404 は、見えなくなった写真に**前から付いている**回がある
///   （本文の `liked: true` / `saved: true`。`APIError` は本文を持ち歩かないので印を聞き直す）
/// - 写真・コメントの削除の 404 は「もう無い」＝消せたのと同じ
final class NotFoundContractTests: XCTestCase {

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

    private func api() -> APIClient {
        APIClient(baseURL: URL(string: "https://api.example.test")!,
                  tokenProvider: StubTokenProvider(token: "t"),
                  session: session)
    }

    private let gone = #"{"error":"写真が見つかりません"}"#

    // MARK: - いいね

    /// 解除の 404 は「外れた」。失敗と読むと、画面は付いたままで永久に外せない
    func testUnlikeNotFoundMeansUnliked() async throws {
        StubProtocol.respond(status: 404, body: gone)
        let result = try await SocialService(api: api()).unlike(photoId: "p1")
        XCTAssertFalse(result.liked)
        XCTAssertNil(result.likes, "見えない写真の数を作っている")
    }

    /// 付ける側の 404 で、印が残っていれば「付いている」
    func testLikeNotFoundWithMarkerMeansLiked() async throws {
        StubProtocol.respond(path: "/photos/p1/like", status: 404, body: #"{"error":"写真が見つかりません","liked":true}"#)
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":true}"#)
        let result = try await SocialService(api: api()).like(photoId: "p1")
        XCTAssertTrue(result.liked, "付いているのに付かなかったと読んでいる")
        XCTAssertNil(result.likes)
    }

    /// 印が無ければ本当に付かなかった（404 のまま投げる）
    func testLikeNotFoundWithoutMarkerStillFails() async {
        StubProtocol.respond(path: "/photos/p1/like", status: 404, body: gone)
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":false}"#)
        do {
            _ = try await SocialService(api: api()).like(photoId: "p1")
            XCTFail("付かなかったのに成功にしている")
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 404, message: "写真が見つかりません"))
        }
    }

    /// 404 以外の失敗は聞き直さない（1回で投げる）
    func testLikeOtherFailuresAreNotRetried() async {
        StubProtocol.respond(status: 500, body: #"{"error":"いいねに失敗しました"}"#)
        do {
            _ = try await SocialService(api: api()).like(photoId: "p1")
            XCTFail("投げるはず")
        } catch {
            XCTAssertEqual(StubProtocol.requestCount, 1, "404 でないのに印を聞き直している")
        }
    }

    // MARK: - 保存

    func testSaveNotFoundWhileSavedSucceeds() async throws {
        StubProtocol.respond(path: "/photos/p1/save", status: 404, body: #"{"error":"写真が見つかりません","saved":true}"#)
        StubProtocol.respond(path: "/user/saves/p1", status: 200, body: #"{"saved":true}"#)
        try await SaveService(api: api()).save(photoId: "p1")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/user/saves/p1")
    }

    func testSaveNotFoundWhileNotSavedFails() async {
        StubProtocol.respond(path: "/photos/p1/save", status: 404, body: gone)
        StubProtocol.respond(path: "/user/saves/p1", status: 200, body: #"{"saved":false}"#)
        do {
            try await SaveService(api: api()).save(photoId: "p1")
            XCTFail("保存できていないのに成功にしている")
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 404, message: "写真が見つかりません"))
        }
    }

    // MARK: - 削除

    /// もう無い写真を消すのは、消せたのと同じ
    func testDeletingAPhotoThatIsAlreadyGoneSucceeds() async throws {
        StubProtocol.respond(status: 404, body: gone)
        try await PhotoService(api: api()).delete(photoId: "p1")
    }

    /// 印の聞き直しそのものが失敗したら、元の 404 を投げる（付いたとは言わない）
    func testLikeNotFoundWithFailedRecheckStillFails() async {
        StubProtocol.respond(path: "/photos/p1/like", status: 404, body: gone)
        StubProtocol.respond(path: "/user/likes/p1", status: 500, body: #"{"error":"取得に失敗しました"}"#)
        do {
            _ = try await SocialService(api: api()).like(photoId: "p1")
            XCTFail("聞き直せなかったのに成功にしている")
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 404, message: "写真が見つかりません"))
            XCTAssertEqual(StubProtocol.requestCount, 2, "印を聞き直していない")
        }
    }

    /// 404 以外の失敗は失敗のまま（権限が無い・サーバーの失敗）
    func testDeleteOtherFailuresStillThrow() async {
        StubProtocol.respond(status: 403, body: #"{"error":"権限がありません"}"#)
        do {
            try await PhotoService(api: api()).delete(photoId: "p1")
            XCTFail("403 を成功にしている")
        } catch {
            XCTAssertEqual((error as? APIError)?.isForbidden, true)
        }
    }
}
