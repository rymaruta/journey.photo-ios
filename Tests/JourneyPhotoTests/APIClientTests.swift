import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `APIClient` の振る舞いを**実際に走らせて**確かめる。
///
/// 通信は `URLProtocol` で差し替える。ここで見たいのは HTTP の組み立てと
/// エラーの振り分けで、ネットワークそのものではない。
final class APIClientTests: XCTestCase {

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

    private func client(token: String?) -> APIClient {
        APIClient(
            baseURL: URL(string: "https://api.example.test")!,
            tokenProvider: StubTokenProvider(token: token),
            session: session
        )
    }

    private struct Payload: Decodable, Equatable { let ok: Bool }

    /// **送るのは ID トークン。** `Bearer` を付けて `Authorization` に載せる。
    func testSendsBearerIdToken() async throws {
        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
        _ = try await client(token: "ID-TOKEN").authorized(.get, "/user/profile", as: Payload.self)
        XCTAssertEqual(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer ID-TOKEN")
    }

    /// 認証が要る呼び出しで、トークンが無ければ**通信しない**。
    func testDoesNotCallServerWhenSignedOut() async {
        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
        do {
            _ = try await client(token: nil).authorized(.get, "/user/profile", as: Payload.self)
            XCTFail("投げるはず")
        } catch {
            XCTAssertEqual(error as? APIError, .notAuthenticated)
        }
        XCTAssertNil(StubProtocol.lastRequest, "未ログインなのに要求を投げている")
    }

    /// 認証不要の呼び出しには `Authorization` を付けない。
    func testAnonymousRequestHasNoAuthorization() async throws {
        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
        _ = try await client(token: "ID-TOKEN").anonymous(.get, "/users/search", as: Payload.self)
        XCTAssertNil(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    /// **エラー本文の日本語をそのまま画面に出せること。**
    /// api-user の `jsonError` は `{ "error": "..." }` を返す。
    func testServerErrorCarriesJapaneseMessage() async {
        StubProtocol.respond(status: 400, body: #"{"error":"理由を選んでください"}"#)
        do {
            _ = try await client(token: "t").authorized(.post, "/photos/1/report", as: Payload.self)
            XCTFail("投げるはず")
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 400, message: "理由を選んでください"))
            XCTAssertEqual((error as? APIError)?.errorDescription, "理由を選んでください")
        }
    }

    /// **「通信できなかった」と「ログインしていない」を混ぜない。**
    func testNetworkFailureIsUnreachableNotAuthError() async {
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        do {
            _ = try await client(token: "t").authorized(.get, "/user/profile", as: Payload.self)
            XCTFail("投げるはず")
        } catch {
            XCTAssertEqual(error as? APIError, .unreachable)
        }
    }

    /// クエリは並べ替えて付ける（同じ要求が毎回同じ URL になる）。
    func testQueryIsAppended() async throws {
        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
        _ = try await client(token: nil).anonymous(
            .get, "/users/search", query: ["q": "パリ"], as: Payload.self
        )
        let url = try XCTUnwrap(StubProtocol.lastRequest?.url)
        XCTAssertEqual(url.path, "/users/search")
        XCTAssertTrue(url.query?.contains("q=") == true, "クエリが付いていない: \(url)")
    }

    /// 本文のある呼び出しは JSON で送る。**nil の項目は載せない**
    /// （api-user は「未指定＝触らない」と読む）。
    func testEncodesBodyAndOmitsNil() async throws {
        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
        var patch = ProfilePatch()
        patch.displayName = "たろう"
        _ = try await client(token: "t").authorizedVoid(.put, "/user/profile", body: patch)

        let body = try XCTUnwrap(StubProtocol.lastBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["displayName"] as? String, "たろう")
        XCTAssertNil(json["bio"], "未指定の項目を送っている（サーバーが上書きしてしまう）")
        XCTAssertEqual(
            StubProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
    }
}

// MARK: - 差し替え用

struct StubTokenProvider: TokenProviding {
    let token: String?
    func idToken() async throws -> String? { token }
}

/// 応答を決め打ちで返す `URLProtocol`。
final class StubProtocol: URLProtocol {

    nonisolated(unsafe) private static var status = 200
    nonisolated(unsafe) private static var body = Data()
    nonisolated(unsafe) private static var error: Error?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    /// `URLProtocol` は `httpBody` を落とすことがあるので、
    /// `httpBodyStream` から読み直して覚えておく
    nonisolated(unsafe) static var lastBody: Data?
    /// 何回叩かれたか。**二度押しを止められているか**を見るのに使う
    nonisolated(unsafe) static var requestCount = 0

    static func reset() {
        status = 200
        body = Data()
        error = nil
        lastRequest = nil
        lastBody = nil
        requestCount = 0
    }

    static func respond(status: Int, body: String) {
        self.status = status
        self.body = Data(body.utf8)
        self.error = nil
    }

    static func fail(with error: Error) {
        self.error = error
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubProtocol.requestCount += 1
        StubProtocol.lastRequest = request
        StubProtocol.lastBody = request.httpBody ?? StubProtocol.readStream(request.httpBodyStream)

        if let error = StubProtocol.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: StubProtocol.status, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: StubProtocol.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }
}

/// 認証切れの扱い。**「サーバーエラー」と混ぜない**——直し方が違う。
final class AuthExpiryTests: XCTestCase {

    func testExpiredSessionHasItsOwnMessage() {
        let expired = APIError.server(status: 401, message: "Unauthorized")
        XCTAssertTrue(expired.isAuthExpired)
        XCTAssertNotEqual(expired.errorDescription, "Unauthorized",
                          "サーバーの英文をそのまま出している")
    }

    func testForbiddenIsAlsoTreatedAsExpired() {
        XCTAssertTrue(APIError.server(status: 403, message: "").isAuthExpired)
    }

    /// ほかの失敗は巻き込まない（400 は打ち直せば直る）。
    func testOtherStatusesKeepTheServerMessage() {
        let bad = APIError.server(status: 400, message: "理由を選んでください")
        XCTAssertFalse(bad.isAuthExpired)
        XCTAssertEqual(bad.errorDescription, "理由を選んでください")
    }
}
