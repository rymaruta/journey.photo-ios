import XCTest
@testable import JourneyPhoto
import Amplify
import AWSCognitoAuthPlugin
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// サーバーとの約束・通信の失敗の言い分け（バグ探し 2026-09-27 #2・#21・#22・#25）。
final class ServerContractTests: XCTestCase {

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

    /// 🔴 #2 **本文つきの 403 は本文を出す**（上限・返信不可など）。
    /// 「権限がありません…お問い合わせください」にすり替えない
    func testForbiddenWithServerMessageShowsTheMessage() {
        let limit = APIError.server(status: 403, message: "アルバムは50個までです。使わないものを消してください")
        XCTAssertEqual(limit.errorDescription, "アルバムは50個までです。使わないものを消してください")
        XCTAssertTrue(limit.isForbidden, "403 であることは変わらない")
        // 本文の無い 403（API Gateway の門前払い）は今まで通り
        XCTAssertTrue(APIError.server(status: 403, message: "").errorDescription?.contains("お問い合わせ") == true)
    }

    /// 本文は API の応答から拾われる（`{ error }`）
    func testForbiddenBodyReachesTheScreen() async {
        StubProtocol.respond(status: 403, body: #"{"error":"アップロード上限（1000枚）に達しています"}"#)
        do {
            try await api().authorizedVoid(.post, "/user/upload")
            XCTFail("投げるはず")
        } catch {
            XCTAssertEqual((error as? APIError)?.errorDescription, "アップロード上限（1000枚）に達しています")
        }
    }

    /// 🔴 #21 **取り消しを「通信できません」にしない。** 画面が見分けられるよう
    /// `CancellationError` で返す
    func testCancelledRequestIsCancellationNotUnreachable() async {
        StubProtocol.fail(with: URLError(.cancelled))
        do {
            _ = try await api().authorized(.get, "/user/albums", as: EmptyResponse.self)
            XCTFail("投げるはず")
        } catch {
            XCTAssertTrue(error is CancellationError, "取り消しが \(error) になっている")
        }
    }

    /// 🔴 #22 **トークンを取れなかった通信の失敗は `APIError.unreachable`**
    func testTokenNetworkFailureIsUnreachable() {
        let offline = AuthError.service("", "", AWSCognitoAuthError.network)
        XCTAssertEqual(AuthGateway.tokenFailure(offline) as? APIError, .unreachable)
        let wrapped = AuthError.service("", "", URLError(.notConnectedToInternet))
        XCTAssertEqual(AuthGateway.tokenFailure(wrapped) as? APIError, .unreachable)
        XCTAssertEqual(AuthGateway.tokenFailure(URLError(.timedOut)) as? APIError, .unreachable)
    }

    /// 通信以外は包まない（期限切れ・その他を「通信できません」と言わない）
    func testTokenOtherFailureIsNotCalledUnreachable() {
        let other = AuthError.service("", "", AWSCognitoAuthError.userNotFound)
        XCTAssertNil(AuthGateway.tokenFailure(other) as? APIError)
    }

    /// 🔴 #25 **1行壊れても、自分の写真・限定写真の一覧ごと落とさない**
    func testOneBrokenRowDoesNotDropTheWholeList() async throws {
        StubProtocol.respond(status: 200, body: """
        [{"id":"a","src":"https://x/a.jpg"},{"id":42,"src":7},{"id":"draft","src":"https://x/d.jpg","published":false}]
        """)
        let photos = PhotoService(api: api())
        let mine = try await photos.myPhotos()
        XCTAssertEqual(mine.map(\.id), ["a", "draft"], "下書きを落としている／1行で全部落ちている")
        let restricted = try await photos.restrictedFeed()
        XCTAssertEqual(restricted.map(\.id), ["a", "draft"])
    }
}
