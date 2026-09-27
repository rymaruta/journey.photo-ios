import XCTest
@testable import JourneyPhoto
import Amplify
import AWSCognitoAuthPlugin
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `import Amplify` にも `APIError` があるので、ここではアプリの方を指す
/// （無いと Xcode で「曖昧」になり試験のビルドが落ちる・TestFlight run 160）。
private typealias APIError = JourneyPhoto.APIError

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

/// 039c643 のレビュー: 緩く読んだ結果が「全部読めない」ときと、トークン取得の取り消し
final class ServerContractReviewTests: XCTestCase {

    override func tearDown() {
        StubProtocol.reset()
        super.tearDown()
    }

    private func photos() -> PhotoService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        StubProtocol.reset()
        return PhotoService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                           tokenProvider: StubTokenProvider(token: "t"),
                                           session: URLSession(configuration: config)))
    }

    /// 🔴 **1行も読めなければ失敗**（空の一覧で成功にしない——マイページが
    /// 「まだ写真がありません」になり、限定写真の控えを空で上書きする）
    func testEveryRowBrokenIsAFailureNotAnEmptyList() async {
        let service = photos()
        StubProtocol.respond(status: 200, body: #"[{"id":1},{"id":2}]"#)
        do {
            _ = try await service.myPhotos()
            XCTFail("全部読めないのに成功している")
        } catch {
            guard case .decoding = error as? APIError else { return XCTFail("\(error)") }
        }
    }

    /// 本当に0枚（`[]`）は成功のまま
    func testEmptyListIsStillEmpty() async throws {
        let service = photos()
        StubProtocol.respond(status: 200, body: "[]")
        let mine = try await service.myPhotos()
        XCTAssertTrue(mine.isEmpty)
    }

    /// 呼んだ側が取り消されたときのトークン取得の取り消しは「通信できません」にしない
    func testTokenCancellationIsCancellation() async {
        let task = Task { () -> [Bool] in
            withUnsafeCurrentTask { $0?.cancel() }
            return [AuthGateway.tokenFailure(URLError(.cancelled)) is CancellationError,
                    AuthGateway.tokenFailure(AuthError.service("", "", URLError(.cancelled))) is CancellationError]
        }
        let results = await task.value
        XCTAssertEqual(results, [true, true])
    }

    /// 呼び手が生きているのに Amplify の中で取り消された回は、失敗として出す
    /// （黙ると空の画面になる）
    func testTokenCancellationWithoutCallerCancelIsUnreachable() {
        XCTAssertEqual(AuthGateway.tokenFailure(URLError(.cancelled)) as? APIError, .unreachable)
    }

    /// 限定写真も、1行も読めなければ失敗（前回の控えを空で上書きしない）
    func testRestrictedFeedEveryRowBrokenIsAFailure() async {
        let service = photos()
        StubProtocol.respond(status: 200, body: #"[{"id":1}]"#)
        do {
            _ = try await service.restrictedFeed()
            XCTFail("全部読めないのに成功している")
        } catch {
            guard case .decoding = error as? APIError else { return XCTFail("\(error)") }
        }
    }

    /// 下書き（`published: false`）だけの一覧は成功（落とさない）
    func testDraftsOnlyIsSuccess() async throws {
        let service = photos()
        StubProtocol.respond(status: 200, body: #"[{"id":"d","src":"https://x/d.jpg","published":false}]"#)
        let mine = try await service.myPhotos()
        XCTAssertEqual(mine.map(\.id), ["d"])
    }

    /// 期限切れの種類は包まない（呼び出し元の判定を変えない）
    func testSessionExpiredIsNotWrapped() {
        let expired = AuthError.sessionExpired("", "", nil)
        XCTAssertNil(AuthGateway.tokenFailure(expired) as? APIError)
    }
}
