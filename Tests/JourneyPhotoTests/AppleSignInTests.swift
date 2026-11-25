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
        var forgotProviders = 0
        var fail: Error?
    }

    private func store(_ calls: Calls, latch: SignOutLatch = .forTesting()) -> AuthStore {
        var gateway = AuthStoreGateway(
            isSignedIn: { false }, currentUserId: { "sub-1" }, currentUsername: { "uuid-1" },
            isSessionExpired: { false },
            signOut: { calls.signOut += 1; return .signedOut },
            deleteUser: {},
            latch: latch)
        gateway.forgetProviderSessions = { calls.forgotProviders += 1 }
        gateway.signInWithTicket = { username, answer in
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
            throw APIError.server(status: 401, message: "サインインできませんでした。もう一度お試しください")
        }
        XCTAssertNil(started)
        XCTAssertTrue(calls.signInWith.isEmpty)
        XCTAssertNil(auth.userId)
        XCTAssertNotNil(auth.errorMessage)
    }

    /// 🔴 2つの端末で同時に押した（サーバーの 409）は「途中です」と出し、Cognito に進まない
    func testBusyServerSaysInProgress() async {
        let calls = Calls()
        let auth = store(calls)
        await auth.restore()
        let started = await auth.signInWithApple(credential) { _ in
            throw APIError.server(status: 409, message: "サインイン中です。少し待ってからお試しください")
        }
        XCTAssertNil(started)
        XCTAssertTrue(calls.signInWith.isEmpty)
        XCTAssertEqual(auth.errorMessage, AuthStore.federatedBusy)
    }

    /// 🔴 「サインインの方法」で解除した ID（サーバーの 409・`code` が `*_signin_unlinked`）は、サーバーの文をそのまま出す。
    /// 見分けるのは本文の `code`（文の一部ではない・2026-11-23 確かめ役の見直し）。「途中です」と取り違えない。Cognito に進まない
    func testUnlinkedServerMessageIsShown() async {
        let text = "この Apple ID の連携は解除されています。メールアドレスでログインしてください"
        StubProtocol.respond(path: "/auth/apple", status: 409, body: #"{"error":"\#(text)","code":"apple_signin_unlinked"}"#)
        let calls = Calls()
        let auth = store(calls)
        await auth.restore()
        let service = AppleSignInService(api: api(token: nil))
        let started = await auth.signInWithApple(credential) { try await service.start($0) }
        XCTAssertNil(started)
        XCTAssertTrue(calls.signInWith.isEmpty)
        XCTAssertEqual(auth.errorMessage, text)

        // 同じ 409 でも `code` が「途中」なら「途中です」（文に同じ言葉が入っていても、`code` で決める）
        StubProtocol.reset()
        StubProtocol.respond(path: "/auth/apple", status: 409,
                             body: #"{"error":"連携は解除されています（試験のための紛らわしい文）","code":"apple_signin_busy"}"#)
        _ = await auth.signInWithApple(credential) { try await service.start($0) }
        XCTAssertEqual(auth.errorMessage, AuthStore.federatedBusy)

        // Google も同じ
        StubProtocol.reset()
        let gtext = "この Google アカウントの連携は解除されています。メールアドレスでログインしてください"
        StubProtocol.respond(path: "/auth/google", status: 409, body: #"{"error":"\#(gtext)","code":"google_signin_unlinked"}"#)
        let google = GoogleSignInService(api: api(token: nil))
        let g = await auth.signInWithGoogle(GoogleSignInCredential(idToken: "g", rawNonce: "r", displayName: nil)!) { try await google.start($0) }
        XCTAssertNil(g)
        XCTAssertEqual(auth.errorMessage, gtext)
    }

    /// `code` の見分けそのもの（409 でないもの・知らない `code` は包まない）
    func testUnlinkedWrapsOnlyByCode() async {
        let refusal = APIError.server(status: 409, message: "x")
        XCTAssertEqual(FederatedSignInUnlinked.wrap(refusal, code: "apple_signin_unlinked") as? FederatedSignInUnlinked,
                       FederatedSignInUnlinked(message: "x"))
        XCTAssertNil(FederatedSignInUnlinked.wrap(refusal, code: "apple_signin_busy") as? FederatedSignInUnlinked)
        XCTAssertNil(FederatedSignInUnlinked.wrap(refusal, code: nil) as? FederatedSignInUnlinked)
        XCTAssertNil(FederatedSignInUnlinked.wrap(APIError.server(status: 400, message: "x"), code: "apple_signin_unlinked") as? FederatedSignInUnlinked)
    }

    // MARK: - Google でログイン（札 #715）

    func testGoogleStartSendsIdTokenAndRawNonce() async throws {
        StubProtocol.respond(path: "/auth/google", status: 200,
                             body: #"{"username":"uuid-g","challengeAnswer":"google:109:T","created":false}"#)
        let credential = try XCTUnwrap(GoogleSignInCredential(idToken: "g.id.tok", rawNonce: "raw-g", displayName: " 山田 太郎 "))
        let started = try await GoogleSignInService(api: api(token: nil)).start(credential)
        XCTAssertEqual(started, FederatedSignInStart(username: "uuid-g", challengeAnswer: "google:109:T", created: false))
        XCTAssertEqual(StubProtocol.requests, ["POST /auth/google"])
        XCTAssertNil(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "ログイン前に呼ぶ口")
        let sent = try XCTUnwrap(StubProtocol.lastBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertEqual(sent["idToken"] as? String, "g.id.tok")
        XCTAssertEqual(sent["nonce"] as? String, "raw-g", "サーバーには元の値（Google に渡したのは SHA-256）")
        XCTAssertEqual(sent["displayName"] as? String, "山田 太郎")
    }

    func testGoogleAvailableOnlyWhenServerSaysSo() async {
        StubProtocol.respond(path: "/auth/google/status", status: 200, body: #"{"available":true}"#)
        let yes = await GoogleSignInService(api: api()).isAvailable()
        XCTAssertTrue(yes)
        StubProtocol.reset()
        StubProtocol.respond(path: "/elsewhere", status: 200, body: "{}")
        let missing = await GoogleSignInService(api: api()).isAvailable()
        XCTAssertFalse(missing, "口がまだ無い本番（404）ではボタンを出さない")
    }

    func testGoogleCredentialNeedsTokenAndNonce() async {
        XCTAssertNil(GoogleSignInCredential(idToken: nil, rawNonce: "n", displayName: nil))
        XCTAssertNil(GoogleSignInCredential(idToken: "", rawNonce: "n", displayName: nil))
        XCTAssertNil(GoogleSignInCredential(idToken: "t", rawNonce: nil, displayName: nil))
        XCTAssertNil(GoogleSignInCredential(idToken: "t", rawNonce: "n", displayName: "  ")?.displayName)
    }

    /// Google も同じ券の流れ（答えは券。Cognito の「違います」は Google の文で出す）
    func testGoogleSignsInWithTicket() async {
        let calls = Calls()
        let auth = store(calls)
        await auth.restore()
        let g = GoogleSignInCredential(idToken: "g.id.tok", rawNonce: "raw-g", displayName: nil)!
        let started = await auth.signInWithGoogle(g) { _ in .init(username: "uuid-g", challengeAnswer: "google:109:T", created: true) }
        XCTAssertEqual(started?.created, true)
        XCTAssertEqual(calls.signInWith.map(\.1), ["google:109:T"])

        let calls2 = Calls()
        calls2.fail = AuthError.notAuthorized("", "", AWSCognitoAuthErrorProbe.none)
        let auth2 = store(calls2)
        await auth2.restore()
        _ = await auth2.signInWithGoogle(g) { _ in .init(username: "uuid-g", challengeAnswer: "google:109:T", created: nil) }
        XCTAssertEqual(auth2.errorMessage, AuthStore.googleSignInFailed)
    }

    /// 🔴 ログアウトしたら、Google の部品の中のログインも外す（次の人に前の人の Google アカウントを出さない）
    func testSignOutForgetsGoogleSession() async {
        let calls = Calls()
        let auth = store(calls)
        await auth.restore()
        _ = await auth.signInWithGoogle(GoogleSignInCredential(idToken: "g", rawNonce: "r", displayName: nil)!) { _ in
            .init(username: "uuid-g", challengeAnswer: "google:1:T", created: nil)
        }
        let before = calls.forgotProviders
        await auth.signOut()
        XCTAssertEqual(calls.forgotProviders, before + 1)
    }

    /// URL の型とクライアント ID は同じ値から（逆さのクライアント ID）
    func testGoogleUrlSchemeMatchesClientId() async {
        let id = GoogleSignInConfig.clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        XCTAssertEqual(GoogleSignInConfig.urlScheme, "com.googleusercontent.apps.\(id)")
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

    /// ログインの画面と知らせの文は話し言葉で短く（2026-11-23 owner「結ばれました、は日常会話で使わない」「長すぎる」）。
    /// 「結ぶ」「連携」と中黒を、ログインまわりの `L("…")` の日本語に入れない
    func testSignInWordingIsPlain() async throws {
        let src = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        let dirs = ["Features/Auth", "Core/Auth", "Services"].map { src.appendingPathComponent($0) }
        var bad: [String] = []
        for dir in dirs {
            let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "swift" && (!dir.path.hasSuffix("Services") || $0.lastPathComponent.contains("SignIn")) }
            for file in files {
                let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                for (i, line) in lines.enumerated()
                where line.range(of: #"L\("[^"]*(結ば|結び|結ぶ|結べ|連携|・)"#, options: .regularExpression) != nil {
                    bad.append("\(file.lastPathComponent):\(i + 1)")
                }
            }
        }
        XCTAssertEqual(bad, [], "ログインまわりの文に「結ぶ」「連携」「・」がある")
        // 失敗の文は1文の短い形（前置きの「Apple での」「確かめられませんでした」を入れない）
        for message in [AuthStore.appleSignInFailed, AuthStore.googleSignInFailed, AuthStore.federatedBusy] {
            XCTAssertFalse(message.contains("確かめられません"), message)
            XCTAssertFalse(message.contains("途中です"), message)
        }
    }

    /// 登録とログインを切り替えたら、Apple のボタンを作り直す（札 #730・Mac run 1808 で「Appleで登録」のまま残った）。
    /// `SignInWithAppleButton` は作ったときの字のまま替わらないので、`appleButton` に登録かどうかで変わる `.id` を付ける。
    /// 画面は Linux で描けないので書いてあるもので見る。実際の字は UI テスト `testCapturesSignInLayout` で見る
    func testAppleButtonIsRebuiltWhenSideSwitches() async throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto/Features/Auth/SignInView.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private var appleButton: some View {"), "appleButton が無い")
        let end = try XCTUnwrap(source.range(of: "\n    }\n", range: start.upperBound..<source.endIndex))
        let body = source[start.upperBound..<end.lowerBound]
        XCTAssertTrue(body.contains("SignInWithAppleButton(mode == .signUp ? .signUp : .signIn)"), "Apple のボタンの字が登録とログインで分かれていない")
        XCTAssertTrue(body.contains(".id(mode == .signUp)"), "切り替えで Apple のボタンを作り直していない（字が前の側のまま残る）")
    }
}

/// `AuthError` の中身に入れる何か（種類は `notAuthorized` の枠で決まる）
private enum AWSCognitoAuthErrorProbe: Error { case none }
