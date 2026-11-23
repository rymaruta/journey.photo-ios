import XCTest
@testable import JourneyPhoto
import Amplify
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 「Apple でサインイン」（札 #601・2026-11-23）。
///
/// - サーバーの口が無い・使えないときはボタンを出さない（今の本番でも壊れない）
/// - Apple には nonce の SHA-256、サーバーには元の値を渡す（2026-11-23 確かめ役の指摘）
/// - サーバーが返した Cognito のユーザー名に、サーバーが出した使い捨ての券を答えてログインする
/// - 退会の Apple の取り消しはサーバーが行う（アプリは取り消しの口を呼ばない）
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
        StubProtocol.respond(path: "/auth/apple", status: 200,
                             body: #"{"username":"uuid-1","challengeAnswer":"apple:001.x:TICKET","created":true}"#)
        let credential = try XCTUnwrap(AppleSignInCredential(identityToken: Data("a.b.c".utf8), rawNonce: "raw-1",
                                                             authorizationCode: Data("code".utf8),
                                                             givenName: "太郎", familyName: "山田"))
        let started = try await AppleSignInService(api: api(token: nil)).start(credential)
        XCTAssertEqual(started, AppleSignInService.Started(username: "uuid-1", challengeAnswer: "apple:001.x:TICKET", created: true))
        XCTAssertEqual(StubProtocol.requests, ["POST /auth/apple"])
        let sent = try XCTUnwrap(StubProtocol.lastBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertEqual(sent["identityToken"] as? String, "a.b.c")
        XCTAssertEqual(sent["nonce"] as? String, "raw-1", "サーバーには元の値")
        XCTAssertEqual(sent["authorizationCode"] as? String, "code")
        XCTAssertEqual(sent["displayName"] as? String, "山田 太郎")
    }

    // MARK: - Apple から来たもの

    func testCredentialNeedsIdentityTokenAndNonce() async {
        XCTAssertNil(AppleSignInCredential(identityToken: nil, rawNonce: "n", authorizationCode: nil, givenName: nil, familyName: nil))
        XCTAssertNil(AppleSignInCredential(identityToken: Data(), rawNonce: "n", authorizationCode: nil, givenName: nil, familyName: nil))
        XCTAssertNil(AppleSignInCredential(identityToken: Data("t".utf8), rawNonce: nil, authorizationCode: nil, givenName: nil, familyName: nil),
                     "nonce の元の値が無いとサーバーで照らせない")
        XCTAssertNil(AppleSignInCredential(identityToken: Data("t".utf8), rawNonce: "", authorizationCode: nil, givenName: nil, familyName: nil))
        let noCode = AppleSignInCredential(identityToken: Data("t".utf8), rawNonce: "n", authorizationCode: Data(), givenName: nil, familyName: nil)
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
        XCTAssertEqual(a.raw.count, 64)
        XCTAssertTrue(a.raw.allSatisfy { $0.isHexDigit })
        XCTAssertNotEqual(a, AppleSignInNonce.make())
    }

    /// 🔴 Apple に渡すのは元の値の SHA-256（16進・小文字）。サーバーの `sha256Hex` と同じ形でないと照らせない
    func testNonceHashedForAppleIsSha256Hex() async {
        XCTAssertEqual(AppleSignInNonce.sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(AppleSignInNonce.sha256Hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        let n = AppleSignInNonce(raw: "raw-nonce-0123456789abcdef")
        // サーバーの試験（photo-gallery `appleSignin.test.ts` の RAW）と同じ値
        XCTAssertEqual(n.hashed, "987470e0df287fdfc6949e7320c3a7d3c45154b33ca5b44eda6b0784faa10014")
        XCTAssertNotEqual(n.hashed, n.raw, "Apple に元の値を渡さない")
        XCTAssertEqual(n.hashed.count, 64)
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
        gateway.signInWithApple = { username, answer in
            if let error = calls.fail { throw error }
            calls.signInWith.append((username, answer))
            return true
        }
        return AuthStore(gateway: gateway)
    }

    private let credential = AppleSignInCredential(identityToken: Data("tok.en.x".utf8), rawNonce: "raw-1", authorizationCode: nil,
                                                   givenName: nil, familyName: nil)!

    func testSignsInWithTheUsernameTheServerChose() async {
        let calls = Calls()
        let auth = store(calls)
        await auth.restore()
        let started = await auth.signInWithApple(credential) { _ in .init(username: "uuid-9", challengeAnswer: "apple:001.x:T1", created: false) }
        XCTAssertEqual(started?.username, "uuid-9")
        XCTAssertEqual(calls.signInWith.map(\.0), ["uuid-9"])
        XCTAssertEqual(calls.signInWith.map(\.1), ["apple:001.x:T1"], "答えはサーバーが出した券（identity token ではない）")
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
        let started = await auth.signInWithApple(credential) { _ in .init(username: "uuid-9", challengeAnswer: "apple:001.x:T1", created: nil) }
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
        let started = await auth.signInWithApple(credential) { _ in .init(username: "uuid-9", challengeAnswer: "apple:001.x:T1", created: nil) }
        XCTAssertNotNil(started)
        XCTAssertGreaterThanOrEqual(calls.signOut, 1)
        XCTAssertFalse(latch.isSet, "入れたら印を外す")
    }

    // MARK: - 退会

    /// 退会はサーバーの退会だけ（Apple の取り消しはサーバーが中で行う）。取り消しの口は呼ばない
    func testDeletionLeavesAppleRevokeToServer() async throws {
        StubProtocol.respond(path: "/user/account", status: 200, body: "{}")
        try await AccountService(api: api()).deleteAccount()
        XCTAssertEqual(StubProtocol.requests, ["DELETE /user/account"])
    }
}

/// `AuthError` の中身に入れる何か（種類は `notAuthorized` の枠で決まる）
private enum AWSCognitoAuthErrorProbe: Error { case none }
