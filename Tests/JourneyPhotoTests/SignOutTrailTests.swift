import XCTest
@testable import JourneyPhoto
import Amplify
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// ログアウトした時と道の記録（`ExitTrail.keepSignOut`）と、鍵束が開く前の起動（`AuthGateway.configure`）。
/// 札 #617（2026-11-15）「勝手にログアウトされる」
@MainActor
final class SignOutTrailTests: XCTestCase {

    nonisolated(unsafe) private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SignOutTrailTests-\(UUID().uuidString)")!
    }

    /// ログイン中（u1）に見せる口。`signedIn` が false なら Amplify は「ログインしていない」と答える
    private func gateway(signedIn: @escaping @Sendable () async -> Bool = { true },
                         prepare: @escaping @Sendable () async -> Void = {}) -> AuthStoreGateway {
        AuthStoreGateway(
            isSignedIn: signedIn,
            currentUserId: { "u1" },
            currentUsername: { "name-u1" },
            isSessionExpired: { false },
            signOut: { .signedOut },
            deleteUser: {},
            prepare: prepare,
            latch: .forTesting()
        )
    }

    private func store(_ gateway: AuthStoreGateway) -> AuthStore {
        let auth = AuthStore(gateway: gateway)
        auth.trailDefaults = defaults
        return auth
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "待っても変わらなかった", file: file, line: line)
    }

    /// 🔴 **期限切れの知らせが添えた道と細かい種類を、そのまま記録に残す。** 入ってからの日数も出す
    /// （更新トークンの 5 日で切れたのかを見分ける）。知らせの添え物を読まないと、どの道も `expired.token` になる
    func testExpiryNoticeKeepsItsCauseDetailAndAge() async {
        let auth = store(gateway())
        await auth.restore()
        XCTAssertEqual(auth.userId, "u1", "下ごしらえ: ログイン中になる")
        // 入った時刻を 5 日前にする（本物は ID トークンの auth_time）
        ExitTrail.noteSignedIn(authTime: Date().addingTimeInterval(-5 * 86_400), defaults: defaults)

        NotificationCenter.default.post(name: .authSessionExpired, object: nil, userInfo: [
            AuthGateway.sessionExpiredCauseKey: ExitTrail.SignOutCause.expiredRefresh.rawValue,
            AuthGateway.sessionExpiredDetailKey: "GET/user/photos",
        ])
        await waitUntil { auth.userId == nil }

        let lines = ExitTrail.signOutLines(defaults: defaults)
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("cause=expired.refresh"), lines[0])
        XCTAssertTrue(lines[0].contains("age=5.0d"), lines[0])
        XCTAssertTrue(lines[0].contains("detail=GET/user/photos"), lines[0])
        XCTAssertEqual(ExitTrail.signOutCounts(defaults: defaults), ["expired.refresh": 1])
        XCTAssertEqual(ExitTrail.session(defaults: defaults)?.signedIn, false, "ログアウトしたのにログイン中の控えが残っている")
    }

    /// 本人が押したログアウトは `user` で数える（勝手なログアウトと分ける）
    func testUserSignOutIsCountedAsUser() async {
        let auth = store(gateway())
        await auth.restore()
        await auth.startSigningOut(releaseDevice: {})?.value
        XCTAssertEqual(ExitTrail.signOutCounts(defaults: defaults), ["user": 1])
    }

    /// 🔴 **前の起動でログイン中だったのに、起動したら「ログインしていない」**——この回だけ `launch.notSignedIn` に残す。
    /// ふだんの未ログインの起動（控えが無い）は数えない
    func testLaunchThatLostTheSignInIsKeptOnlyAfterASignedInRun() async {
        ExitTrail.noteSignedIn(authTime: nil, defaults: defaults)
        let lost = store(gateway(signedIn: { false }))
        await lost.restore()
        XCTAssertEqual(ExitTrail.signOutCounts(defaults: defaults), ["launch.notSignedIn": 1])

        // 次の起動も未ログイン。もう控えは下りているので数えない
        let again = store(gateway(signedIn: { false }))
        await again.restore()
        XCTAssertEqual(ExitTrail.signOutCounts(defaults: defaults), ["launch.notSignedIn": 1],
                       "ふだんの未ログインの起動まで数えている")
    }

    /// 🔴 **起動の確かめは、鍵束が開くのを待ってから Amplify に聞く**（`AuthStoreGateway.prepare`）。
    /// 待たずに聞くと、鍵を開ける前に起こされた起動では控えを読めず「ログインしていない」になり、
    /// 控えは残っているのにログイン画面が出ていた
    func testRestoreWaitsForTheKeychainBeforeAsking() async {
        let ready = Flag()
        let auth = store(gateway(signedIn: { await ready.value }, prepare: { await ready.set() }))
        await auth.restore()
        XCTAssertEqual(auth.userId, "u1", "鍵束が開くのを待たずに確かめて、ログイン画面に倒している")
    }

    /// 🔴 **鍵束が開いていない起動では Amplify を設定しない。** 開いてから設定し、待った回を1つ数える
    func testConfigureWaitsWhileTheKeychainIsLocked() async throws {
        let wasConfigured = AuthGateway.isConfigured
        let wasWaiting = AuthGateway.waitsForKeychain
        defer {
            AuthGateway.isConfigured = wasConfigured
            AuthGateway.waitsForKeychain = wasWaiting
        }
        AuthGateway.isConfigured = false
        AuthGateway.waitsForKeychain = false

        try AuthGateway.configure(keychainLocked: { true })
        XCTAssertFalse(AuthGateway.isConfigured, "鍵束が開く前に Amplify を設定している（控えを読めず未ログインで始まる）")
        XCTAssertTrue(AuthGateway.waitsForKeychain)

        var answers = [true, true, false]
        var pauses = 0
        var configured = 0
        await AuthGateway.configureWhenKeychainOpens(
            keychainLocked: { answers.removeFirst() },
            pause: { pauses += 1 },
            configure: { configured += 1 })
        XCTAssertEqual(pauses, 2, "開くまで待っていない")
        XCTAssertEqual(configured, 1, "開いたあとに設定していない")
        XCTAssertFalse(AuthGateway.waitsForKeychain)

        // 後に回していない起動では何もしない
        await AuthGateway.configureWhenKeychainOpens(keychainLocked: { true }, pause: { XCTFail("待っている") },
                                                     configure: { configured += 1 })
        XCTAssertEqual(configured, 1)
    }

    /// エラーは**型と種類の名前だけ**にする（Cognito の文は入れない）
    func testErrorKindHasNoMessageText() async {
        struct NotAuthorizedException: Error {}
        let kind = ExitTrail.errorKind(AuthError.sessionExpired("someone@example.com was signed out", "sign in",
                                                                NotAuthorizedException()))
        XCTAssertEqual(kind, "sessionExpired/NotAuthorizedException")
        XCTAssertEqual(ExitTrail.errorKind(AuthError.notAuthorized("x", "y", nil)), "notAuthorized")
    }

    /// 口の形は id を伏せる
    func testPathShapeHidesIds() async {
        XCTAssertEqual(ExitTrail.pathShape("/user/profile"), "/user/profile")
        XCTAssertEqual(ExitTrail.pathShape("/photos/p1/comments"), "/photos/:id/comments")
        XCTAssertEqual(ExitTrail.pathShape("/highlights/3f2a9c1e-aaaa-bbbb-cccc-111122223333/x"), "/highlights/:id/x")
    }

    /// 「意見を送る」に添える文に入り（回数の行が先・新しい順）、送ったら消える。ログイン中かの控えは残す
    func testSignOutLinesAreAttachedAndClearedAfterSending() async {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        ExitTrail.keepSignOut(.expiredToken, detail: "sessionExpired/NotAuthorizedException", defaults: defaults,
                              now: t0, version: "1.1.93 (1)")
        ExitTrail.keepSignOut(.user, defaults: defaults, now: t0.addingTimeInterval(60), version: "1.1.93 (1)")
        ExitTrail.noteSignedIn(authTime: t0, defaults: defaults)
        XCTAssertEqual(ExitTrail.contents(defaults: defaults), .signOut)

        let text = ExitTrail.attachment(defaults: defaults, limit: 400) ?? ""
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, "[ログアウトの回数] expired.token=1 user=1")
        XCTAssertTrue(lines[1].hasPrefix("[ログアウト] 1.1.93 (1) ") && lines[1].contains("cause=user"), lines[1])
        XCTAssertTrue(lines[2].contains("cause=expired.token") && lines[2].contains("detail=sessionExpired/NotAuthorizedException"))

        ExitTrail.clear(defaults: defaults)
        XCTAssertNil(ExitTrail.attachment(defaults: defaults, limit: 400))
        XCTAssertEqual(ExitTrail.session(defaults: defaults)?.signedIn, true)
    }

    /// 行は新しい方から `signOutLinesMax` 行だけ残す（回数は全部数える）
    func testOnlyTheLatestLinesAreKept() async {
        for _ in 0..<(ExitTrail.signOutLinesMax + 2) { ExitTrail.keepSignOut(.expiredToken, defaults: defaults) }
        XCTAssertEqual(ExitTrail.signOutLines(defaults: defaults).count, ExitTrail.signOutLinesMax)
        XCTAssertEqual(ExitTrail.signOutCounts(defaults: defaults)["expired.token"], ExitTrail.signOutLinesMax + 2)
    }

    /// ID トークンの `auth_time` を読む
    func testAuthTimeIsReadFromTheIdToken() async {
        let body = Data(#"{"sub":"u1","auth_time":1800000000}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(IdTokenClaims.authTime(fromJWT: "h.\(body).s"), Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertNil(IdTokenClaims.authTime(fromJWT: FakeJWT.make(sub: "u1", tag: "t")))
    }
}

/// 401 から先のログアウトの道を、`APIClient` が分けて知らせる（取り直せなかった・取り直しても 401）
final class SessionExpiredCauseTests: XCTestCase {

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

    private func client(_ provider: TokenProviding) -> APIClient {
        APIClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: provider, session: session)
    }

    func testUnrefreshableAndRetried401AreToldApart() async {
        let log = CauseLog()
        StubProtocol.respond(status: 401, body: "")
        _ = try? await client(CauseProvider(refreshed: nil, log: log)).authorizedVoid(.delete, "/photos/p1")
        StubProtocol.reset()
        StubProtocol.respond(status: 401, body: "")
        _ = try? await client(CauseProvider(refreshed: FakeJWT.make(sub: "u1", tag: "new"), log: log))
            .authorizedVoid(.get, "/user/profile")
        let causes = await log.causes
        XCTAssertEqual(causes, ["expired.refresh DELETE/photos/:id", "expired.retry401 GET/user/profile"])
    }
}

private actor CauseLog {
    private(set) var causes: [String] = []
    func note(_ value: String) { causes.append(value) }
}

private struct CauseProvider: TokenProviding {
    let refreshed: String?
    let log: CauseLog
    func idToken() async throws -> String? { FakeJWT.make(sub: "u1", tag: "old") }
    func refreshedIdToken() async throws -> String? { refreshed }
    func sessionExpired(because cause: ExitTrail.SignOutCause, detail: String?) async {
        await log.note("\(cause.rawValue) \(detail ?? "-")")
    }
}

private actor Flag {
    private(set) var value = false
    func set() { value = true }
}
