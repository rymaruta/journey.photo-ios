import XCTest
@testable import JourneyPhoto
import Amplify
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 「Apple でサインイン」（札 #601・2026-11-23）。
///
/// - サーバーの口が無い・使えないときはボタンを出さない（今の本番でも壊れない）
/// - サーバーが返した Cognito のユーザー名に、Apple の identity token を答えてログインする
/// - 退会の前に Apple の取り消しを呼ぶ。失敗しても退会は止めない
@MainActor
final class AppleSignInTests: XCTestCase {

    private func api(token: String? = "t") -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return APIClient(baseURL: URL(string: "https://api.example.test")!,
                         tokenProvider: StubTokenProvider(token: token),
                         session: URLSession(configuration: config))
    }

    override func setUp() async throws {
        try await super.setUp()
        StubProtocol.reset()
    }

    override func tearDown() async throws {
        StubProtocol.reset()
        try await super.tearDown()
    }

    // MARK: - 使えるか

    func testAvailableOnlyWhenServerSaysSo() async {
        StubProtocol.respond(path: "/auth/apple/status", status: 200, body: #"{"available":true}"#)
        let yes = await AppleSignInService(api: api()).isAvailable()
        XCTAssertTrue(yes)
        XCTAssertEqual(StubProtocol.requests, ["GET /auth/apple/status"])
        XCTAssertNil(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "ログイン前に呼ぶ口（鍵を付けない）")

        StubProtocol.reset()
        StubProtocol.respond(path: "/auth/apple/status", status: 200, body: #"{"available":false}"#)
        let no = await AppleSignInService(api: api()).isAvailable()
        XCTAssertFalse(no, "鍵の入っていない環境")
    }

    /// 口がまだ無い本番（404）・壊れた答えでは出さない
    func testUnavailableWhenRouteMissingOrBroken() async {
        StubProtocol.respond(path: "/elsewhere", status: 200, body: "{}")   // 当てはまる道が無い＝404
        let missing = await AppleSignInService(api: api()).isAvailable()
        XCTAssertFalse(missing)
        StubProtocol.reset()
        StubProtocol.respond(path: "/auth/apple/status", status: 200, body: "<html>")
        let broken = await AppleSignInService(api: api()).isAvailable()
        XCTAssertFalse(broken)
    }

    func testStartSendsCredentialAndReadsUsername() async throws {
        StubProtocol.respond(path: "/auth/apple", status: 200, body: #"{"username":"uuid-1","created":true}"#)
        let credential = try XCTUnwrap(AppleSignInCredential(identityToken: Data("a.b.c".utf8), authorizationCode: Data("code".utf8),
                                                             givenName: "太郎", familyName: "山田"))
        let started = try await AppleSignInService(api: api(token: nil)).start(credential)
        XCTAssertEqual(started, AppleSignInService.Started(username: "uuid-1", created: true))
        XCTAssertEqual(StubProtocol.requests, ["POST /auth/apple"])
        let sent = try XCTUnwrap(StubProtocol.lastBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertEqual(sent["identityToken"] as? String, "a.b.c")
        XCTAssertEqual(sent["authorizationCode"] as? String, "code")
        XCTAssertEqual(sent["displayName"] as? String, "山田 太郎")
    }

    // MARK: - Apple から来たもの

    func testCredentialNeedsIdentityToken() async {
        XCTAssertNil(AppleSignInCredential(identityToken: nil, authorizationCode: nil, givenName: nil, familyName: nil))
        XCTAssertNil(AppleSignInCredential(identityToken: Data(), authorizationCode: nil, givenName: nil, familyName: nil))
        let noCode = AppleSignInCredential(identityToken: Data("t".utf8), authorizationCode: Data(), givenName: nil, familyName: nil)
        XCTAssertNil(noCode?.authorizationCode, "空の認可コードは送らない")
        XCTAssertNil(noCode?.displayName, "2回目から Apple は名前を渡さない")
    }

    func testDisplayNameOrder() async {
        XCTAssertEqual(AppleSignInName.displayName(given: "太郎", family: "山田"), "山田 太郎")
        XCTAssertEqual(AppleSignInName.displayName(given: "たろう", family: "やまだ"), "やまだ たろう")
        XCTAssertEqual(AppleSignInName.displayName(given: "Taro", family: "Yamada"), "Taro Yamada")
        XCTAssertEqual(AppleSignInName.displayName(given: " Taro ", family: nil), "Taro")
        XCTAssertEqual(AppleSignInName.displayName(given: nil, family: "山田"), "山田")
        XCTAssertNil(AppleSignInName.displayName(given: " ", family: ""))
    }

    func testNonceIsFreshEachTime() async {
        let a = AppleSignInNonce.make()
        XCTAssertEqual(a.count, 64)
        XCTAssertTrue(a.allSatisfy { $0.isHexDigit })
        XCTAssertNotEqual(a, AppleSignInNonce.make())
    }

    // MARK: - ログイン

    func testAnswersOnlyTheCustomChallenge() async {
        XCTAssertTrue(AuthGateway.needsCustomAnswer(.confirmSignInWithCustomChallenge(nil)))
        XCTAssertFalse(AuthGateway.needsCustomAnswer(.done))
        XCTAssertFalse(AuthGateway.needsCustomAnswer(.confirmSignUp(nil)))
    }

    private final class Calls: @unchecked Sendable {
        var signInWith: [(String, String)] = []
        var signOut = 0
        var fail: Error?
    }

    private func store(_ calls: Calls, latch: SignOutLatch = .forTesting()) -> AuthStore {
        var gateway = AuthStoreGateway(
            isSignedIn: { false }, currentUserId: { "sub-1" }, currentUsername: { "uuid-1" },
            isSessionExpired: { false },
            signOut: { calls.signOut += 1; return .signedOut },
            deleteUser: {},
            latch: latch)
        gateway.signInWithApple = { username, token in
            if let error = calls.fail { throw error }
            calls.signInWith.append((username, token))
            return true
        }
        return AuthStore(gateway: gateway)
    }

    private let credential = AppleSignInCredential(identityToken: Data("tok.en.x".utf8), authorizationCode: nil,
                                                   givenName: nil, familyName: nil)!

    func testSignsInWithTheUsernameTheServerChose() async {
        let calls = Calls()
        let auth = store(calls)
        await auth.restore()
        let started = await auth.signInWithApple(credential) { _ in .init(username: "uuid-9", created: false) }
        XCTAssertEqual(started?.username, "uuid-9")
        XCTAssertEqual(calls.signInWith.map(\.0), ["uuid-9"])
        XCTAssertEqual(calls.signInWith.map(\.1), ["tok.en.x"], "答えは Apple の identity token")
        XCTAssertEqual(auth.userId, "sub-1")
        XCTAssertNil(auth.errorMessage)
    }

    /// サーバーが断ったら Cognito に進まない
    func testServerRefusalStopsBeforeCognito() async {
        let calls = Calls()
        let auth = store(calls)
        await auth.restore()
        let started = await auth.signInWithApple(credential) { _ in
            throw APIError.server(status: 401, message: "Apple でのサインインを確かめられませんでした。もう一度お試しください")
        }
        XCTAssertNil(started)
        XCTAssertTrue(calls.signInWith.isEmpty)
        XCTAssertNil(auth.userId)
        XCTAssertNotNil(auth.errorMessage)
    }

    /// Cognito の「違います」を、メールとパスワードの文で出さない
    func testCognitoRefusalSaysAppleNotPassword() async {
        let calls = Calls()
        calls.fail = AuthError.notAuthorized("", "", AWSCognitoAuthErrorProbe.none)
        let auth = store(calls)
        await auth.restore()
        let started = await auth.signInWithApple(credential) { _ in .init(username: "uuid-9", created: nil) }
        XCTAssertNil(started)
        XCTAssertEqual(auth.errorMessage, AuthStore.appleSignInFailed)
        XCTAssertNil(auth.userId)
    }

    /// 前のログアウトで端末の中のログインを消せなかった回は、先に消してから入る（メールのログインと同じ）
    func testClearsLeftoverSessionFirst() async {
        let calls = Calls()
        let latch = SignOutLatch.forTesting()
        latch.set()
        let auth = store(calls, latch: latch)
        let started = await auth.signInWithApple(credential) { _ in .init(username: "uuid-9", created: nil) }
        XCTAssertNotNil(started)
        XCTAssertGreaterThanOrEqual(calls.signOut, 1)
        XCTAssertFalse(latch.isSet, "入れたら印を外す")
    }

    // MARK: - 退会

    /// 退会の前に Apple の取り消しを呼び、そのあとサーバーの退会
    func testDeletionRevokesAppleFirst() async throws {
        StubProtocol.respond(path: "/auth/apple/revoke", status: 200, body: #"{"revoked":true}"#)
        StubProtocol.respond(path: "/user/account", status: 200, body: "{}")
        try await AccountService(api: api()).deleteAccount()
        XCTAssertEqual(StubProtocol.requests, ["POST /auth/apple/revoke", "DELETE /user/account"])
    }

    /// 取り消しが落ちても（口がまだ無い本番の 404・Apple の失敗の 502）退会は進む
    func testDeletionContinuesWhenRevokeFails() async throws {
        StubProtocol.respond(path: "/user/account", status: 200, body: "{}")   // 取り消しの口は無い＝404
        try await AccountService(api: api()).deleteAccount()
        XCTAssertEqual(StubProtocol.requests, ["POST /auth/apple/revoke", "DELETE /user/account"])

        StubProtocol.reset()
        StubProtocol.respond(path: "/auth/apple/revoke", status: 502, body: #"{"error":"x","code":"apple_revoke_failed"}"#)
        StubProtocol.respond(path: "/user/account", status: 200, body: "{}")
        try await AccountService(api: api()).deleteAccount()
        XCTAssertEqual(StubProtocol.requests.last, "DELETE /user/account")
    }
}

/// `AuthError` の中身に入れる何か（種類は `notAuthorized` の枠で決まる）
private enum AWSCognitoAuthErrorProbe: Error { case none }
