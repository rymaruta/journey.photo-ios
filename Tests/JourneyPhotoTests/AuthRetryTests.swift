import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 401 を受けたら、取り直して1回だけやり直す（`APIClient.send`）。
///
/// 🔴 以前は 401 をそのまま投げていたので、ID トークンが切れた瞬間に開いた画面は
/// 「ログインの有効期限が切れました」を出したまま、ログイン中の見た目で何もできなかった。
final class AuthRetryTests: XCTestCase {

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

    private struct Payload: Decodable, Equatable { let ok: Bool }

    private func client(_ provider: TokenProviding) -> APIClient {
        APIClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: provider, session: session)
    }

    /// 1回目の 401 で取り直し、新しい鍵で1回だけ送り直す
    func testUnauthorizedRefreshesOnceAndRetriesWithTheNewToken() async throws {
        StubProtocol.respondInOrder([(401, #"{"error":"Unauthorized"}"#), (200, #"{"ok":true}"#)])
        let log = RefreshLog()
        let provider = RefreshingTokenProvider(token: "OLD", refreshed: .token("NEW"), log: log)
        let payload = try await client(provider).authorized(.get, "/user/profile", as: Payload.self)
        XCTAssertEqual(payload, Payload(ok: true))
        XCTAssertEqual(StubProtocol.requestCount, 2, "401 のあと送り直していない")
        XCTAssertEqual(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer NEW",
                       "送り直しに古い鍵を使っている")
        let refreshes = await log.refreshes
        let expiries = await log.expiries
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(expiries, 0, "取り直して通ったのにログアウトさせている")
    }

    /// 取り直しても 401 なら、**それ以上やり直さず**ログアウトに倒す
    func testSecondUnauthorizedExpiresTheSessionWithoutAThirdTry() async {
        StubProtocol.respond(status: 401, body: #"{"error":"Unauthorized"}"#)
        let log = RefreshLog()
        let provider = RefreshingTokenProvider(token: "OLD", refreshed: .token("NEW"), log: log)
        do {
            _ = try await client(provider).authorized(.get, "/user/profile", as: Payload.self)
            XCTFail("投げるはず")
        } catch {
            XCTAssertEqual((error as? APIError)?.isAuthExpired, true)
        }
        XCTAssertEqual(StubProtocol.requestCount, 2, "やり直しは1回だけ（送り直した要求をさらにやり直している）")
        let refreshes = await log.refreshes
        let expiries = await log.expiries
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(expiries, 1, "取り直しても 401 なのにログアウトに倒していない")
    }

    /// 取り直せない（更新トークンも切れた）なら送り直さず、ログアウトに倒す
    func testUnrefreshableSessionExpiresWithoutResending() async {
        StubProtocol.respond(status: 401, body: "")
        let log = RefreshLog()
        let provider = RefreshingTokenProvider(token: "OLD", refreshed: .none, log: log)
        do {
            _ = try await client(provider).authorizedVoid(.delete, "/photos/p1")
            XCTFail("投げるはず")
        } catch {
            XCTAssertEqual((error as? APIError)?.isAuthExpired, true)
        }
        XCTAssertEqual(StubProtocol.requestCount, 1)
        let expiries = await log.expiries
        XCTAssertEqual(expiries, 1)
    }

    /// **圏外で取り直せない回はログアウトさせない**（通信できない、を返す）
    func testRefreshThatCannotReachCognitoDoesNotSignOut() async {
        StubProtocol.respond(status: 401, body: "")
        let log = RefreshLog()
        let provider = RefreshingTokenProvider(token: "OLD", refreshed: .unreachable, log: log)
        do {
            _ = try await client(provider).authorizedVoid(.get, "/user/profile")
            XCTFail("投げるはず")
        } catch {
            XCTAssertEqual(error as? APIError, .unreachable)
        }
        let expiries = await log.expiries
        XCTAssertEqual(expiries, 0, "圏外なだけの人をログアウトさせている")
    }

    /// 認証の要らない口・401 以外（403 は権限の話）はやり直さない
    func testAnonymousCallsAndForbiddenAreNotRetried() async {
        let log = RefreshLog()
        let api = client(RefreshingTokenProvider(token: "OLD", refreshed: .token("NEW"), log: log))

        StubProtocol.respond(status: 401, body: "")
        _ = try? await api.anonymous(.get, "/profile/u1", as: Payload.self)
        XCTAssertEqual(StubProtocol.requestCount, 1, "認証の要らない口をやり直している")

        StubProtocol.reset()
        StubProtocol.respond(status: 403, body: "")
        _ = try? await api.authorized(.get, "/user/profile", as: Payload.self)
        XCTAssertEqual(StubProtocol.requestCount, 1, "403 をやり直している（ログインし直しても直らない）")

        let refreshes = await log.refreshes
        XCTAssertEqual(refreshes, 0)
    }

    /// 🔴 **同時に何本 401 になっても、取り直しは1本。** 画面は口を一斉に叩くので、
    /// 1本ずつ取り直すと同じ更新トークンで何本も Cognito に頼むことになる。
    /// `APIClient` は画面ごとに別の実体があるので、2つの実体から叩く
    func testConcurrentUnauthorizedCallsShareOneRefresh() async throws {
        // 1本目・2本目の 401、送り直しはどちらも 200
        StubProtocol.respondInOrder([(401, ""), (401, ""), (200, #"{"ok":true}"#)])
        let fetches = RefreshLog()
        let gate = Gate()
        let refresher = TokenRefresher {
            await fetches.noteRefresh()
            await gate.wait()
            return "NEW"
        }
        let provider = SharedRefresherTokenProvider(refresher: refresher)
        let a = client(provider)
        let b = client(provider)

        async let first = a.authorized(.get, "/user/profile", as: Payload.self)
        async let second = b.authorized(.get, "/albums", as: Payload.self)

        // 2本とも取り直しを待っているところまで進めてから、取り直しを終わらせる
        let deadline = Date().addingTimeInterval(2)
        while await refresher.waiting < 2, Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        let waiting = await refresher.waiting
        XCTAssertEqual(waiting, 2, "下ごしらえ: 2本とも取り直しを待っていない")
        await gate.open()

        let results = try await [first, second]
        XCTAssertEqual(results, [Payload(ok: true), Payload(ok: true)])
        let count = await fetches.refreshes
        XCTAssertEqual(count, 1, "同時の 401 で Cognito に何本も取り直しを頼んでいる")
        XCTAssertEqual(StubProtocol.requestCount, 4)
    }

    /// 終わった後に来た 401 は、新しく取り直す（前の答えを使い回さない）
    func testRefreshAfterTheFirstFinishedStartsAgain() async throws {
        let log = RefreshLog()
        let refresher = TokenRefresher {
            await log.noteRefresh()
            return "NEW"
        }
        _ = try await refresher.refresh()
        _ = try await refresher.refresh()
        let count = await log.refreshes
        XCTAssertEqual(count, 2)
    }
}

// MARK: - 差し替え用

actor RefreshLog {
    private(set) var refreshes = 0
    private(set) var expiries = 0
    func noteRefresh() { refreshes += 1 }
    func noteExpiry() { expiries += 1 }
}

/// 取り直しの答えを決め打ちにした提供者
struct RefreshingTokenProvider: TokenProviding {
    enum Refreshed: Sendable { case token(String), none, unreachable }
    let token: String
    let refreshed: Refreshed
    let log: RefreshLog

    func idToken() async throws -> String? { token }

    func refreshedIdToken() async throws -> String? {
        await log.noteRefresh()
        switch refreshed {
        case .token(let value): return value
        case .none: return nil
        case .unreachable: throw APIError.unreachable
        }
    }

    func sessionExpired() async { await log.noteExpiry() }
}

/// 本番と同じく、1つの `TokenRefresher` を通して取り直す提供者
private struct SharedRefresherTokenProvider: TokenProviding {
    let refresher: TokenRefresher
    func idToken() async throws -> String? { "OLD" }
    func refreshedIdToken() async throws -> String? { try await refresher.refresh() }
}
