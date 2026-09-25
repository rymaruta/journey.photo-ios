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
    /// 順番に返す応答。**使い切ったら最後のものを返し続ける**
    /// （「断られてから引き直す」のような2手の流れを書くのに要る）
    nonisolated(unsafe) private static var queue: [(Int, Data)] = []
    /// 道ごとの応答。**1つの試験で2つの口を叩き分ける**のに要る
    /// （公開プロフィールと公開一覧は別の入れ物から来る）。
    /// 空のときは今までどおり `status`/`body`/`queue` だけで返す
    nonisolated(unsafe) private static var routes: [(path: String, status: Int, body: Data)] = []
    /// 応答に付ける種別（`Content-Type`）。**既定は付けない**——本物の
    /// 応答を写しているのは「キャプティブポータルが 200 で HTML を返す」
    /// 経路だけで、そこを試すときにだけ指定する
    nonisolated(unsafe) private static var contentType: String?

    static func reset() {
        status = 200
        body = Data()
        error = nil
        lastRequest = nil
        lastBody = nil
        requestCount = 0
        queue = []
        routes = []
        contentType = nil
    }

    static func respond(status: Int, body: String, contentType: String? = nil) {
        self.status = status
        self.body = Data(body.utf8)
        self.error = nil
        self.contentType = contentType
        // **順番返しの残りを捨てる。** 残すとこの指定が黙って無視され、
        // 「落ちるはずの経路」を通らないまま緑になる
        self.queue = []
    }

    /// 道（URL のパス）で選んで返す。**当てはまる道が1つも無い要求は
    /// 404 で返す**——「叩かないはずの口」を叩いたら緑にならないように。
    static func respond(path: String, status: Int, body: String) {
        routes.append((path, status, Data(body.utf8)))
    }

    /// 1回目・2回目…と順番に返す。
    static func respondInOrder(_ pairs: [(status: Int, body: String)]) {
        queue = pairs.map { ($0.status, Data($0.body.utf8)) }
        error = nil
    }

    static func fail(with error: Error) {
        self.error = error
        self.queue = []
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
        var status = StubProtocol.status
        var body = StubProtocol.body
        if !StubProtocol.routes.isEmpty {
            let path = request.url?.path ?? ""
            let hit = StubProtocol.routes.first { path.contains($0.path) }
            status = hit?.status ?? 404
            body = hit?.body ?? Data("{\"error\":\"no route\"}".utf8)
        } else if !StubProtocol.queue.isEmpty {
            let next = StubProtocol.queue.count > 1
                ? StubProtocol.queue.removeFirst()
                : StubProtocol.queue[0]
            status = next.0
            body = next.1
        }
        let headers = StubProtocol.contentType.map { ["Content-Type": $0] }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
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

    /// **403 は「期限切れ」ではない（2026-09-21 に改めた）。**
    ///
    /// 以前は 401 とまとめて「ログインし直してください」と出していたが、
    /// 403 は**ログインできているのに権限が無い**状態で、ログインし直しても
    /// 直らない（登録直後に権限を配る処理が落ちたとき）。Web は同じ
    /// 取り違えで、ログイン画面と元の画面を**無限に往復**させていた
    /// （`lib/hooks/useMemberGate.ts` の経緯）。言い分けは
    /// `AuthStatusMessageTests` が見張る。
    func testForbiddenIsNotExpiry() {
        XCTAssertFalse(APIError.server(status: 403, message: "").isAuthExpired)
        XCTAssertTrue(APIError.server(status: 403, message: "").isForbidden)
    }

    /// ほかの失敗は巻き込まない（400 は打ち直せば直る）。
    func testOtherStatusesKeepTheServerMessage() {
        let bad = APIError.server(status: 400, message: "理由を選んでください")
        XCTAssertFalse(bad.isAuthExpired)
        XCTAssertEqual(bad.errorDescription, "理由を選んでください")
    }
}

/// 401 と 403 の言い分け。
///
/// **403 は「ログインし直して」ではない。** ログインできているのに権限が
/// 無い状態で、ログインし直しても直らない（登録直後に権限を配る処理が
/// 落ちたときに起きる）。Web は同じ取り違えで、ログイン画面と元の画面を
/// **無限に往復**させていた（`lib/hooks/useMemberGate.ts` の経緯）。
final class AuthStatusMessageTests: XCTestCase {

    func testExpiredSessionFor401() {
        let error = APIError.server(status: 401, message: "")
        XCTAssertTrue(error.isAuthExpired)
        XCTAssertFalse(error.isForbidden)
        XCTAssertTrue(error.errorDescription?.contains("ログインし直して") == true)
    }

    func testForbiddenIsNotASessionProblem() {
        let error = APIError.server(status: 403, message: "")
        XCTAssertFalse(error.isAuthExpired, "403 で再ログインを促してはいけない")
        XCTAssertTrue(error.isForbidden)
        XCTAssertTrue(error.errorDescription?.contains("権限がありません") == true)
    }
}
