import XCTest
@testable import JourneyPhoto
import Amplify
import AWSCognitoAuthPlugin

/// ログアウトの終わらせ方（期限切れの知らせ・ログアウトの結果）。
///
/// Amplify は模型なので、`AuthStore` の Cognito の口（`AuthStoreGateway`）を差し替えて見る。
@MainActor
final class AuthSessionEndTests: XCTestCase {

    /// ログイン中（u1）に見せる口。ログアウトは `gate` で止められる
    private func gateway(signOuts: SignOutCounter, gate: Gate? = nil) -> AuthStoreGateway {
        AuthStoreGateway(
            isSignedIn: { true },
            currentUserId: { "u1" },
            currentUsername: { "name-u1" },
            isSessionExpired: { false },
            signOut: {
                await signOuts.note()
                await gate?.wait()
                return .signedOut
            },
            deleteUser: {},
            latch: .forTesting()
        )
    }

    /// 🔴 **期限切れの知らせが同時に何通来ても、ログアウトは1回。** 1本目がログアウトを
    /// 待っている間（まだ `.signedIn`）に2本目も通り、並んで走っていた
    func testSimultaneousExpiryNoticesSignOutOnce() async {
        let signOuts = SignOutCounter()
        let gate = Gate()
        let auth = AuthStore(gateway: gateway(signOuts: signOuts, gate: gate))
        await auth.restore()
        XCTAssertEqual(auth.userId, "u1", "下ごしらえ: ログイン中になる")

        let first = Task { await auth.expireSession() }
        let second = Task { await auth.expireSession() }
        let third = Task { await auth.expireSession() }
        await gate.untilWaiting(1)
        // 残りの知らせが届くだけの間を置く（直っていなければ、ここで2本目が着く）
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        await gate.open()
        _ = await (first.value, second.value, third.value)

        let count = await signOuts.count
        XCTAssertEqual(count, 1, "期限切れの知らせごとにログアウトが並んで走っている")
        XCTAssertNil(auth.userId)
        XCTAssertNotNil(auth.errorMessage, "期限切れの案内が出ていない")
    }

    /// 走り終えた後なら、次の期限切れ（入り直した後）でまたログアウトできる
    func testExpiryCanRunAgainAfterTheFirstFinished() async {
        let signOuts = SignOutCounter()
        let auth = AuthStore(gateway: gateway(signOuts: signOuts))
        await auth.restore()
        await auth.expireSession()
        await auth.restore()
        XCTAssertEqual(auth.userId, "u1")
        await auth.expireSession()
        let count = await signOuts.count
        XCTAssertEqual(count, 2, "1回目の印が残って、2回目の期限切れでログアウトしない")
    }
}

/// ログアウトの結果を捨てない（`AuthGateway.signOut`・`SignOutLatch`）。
///
/// 🔴 `_ = await Amplify.Auth.signOut()` で結果を捨てていたので、端末の中のログインを
/// 消せなかった回（`.failed`）は画面だけログアウトし、次の起動で黙ってログイン中に戻っていた
@MainActor
final class SignOutResultTests: XCTestCase {

    private func latch() -> SignOutLatch {
        SignOutLatch(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    /// 1回目で消せなければ、もう一度だけ試す（消せたら印は残さない）
    func testRetriesOnceWhenTheFirstSignOutFails() async {
        var answers = [false, true]
        var attempts = 0
        let latch = latch()
        latch.set()  // 前の起動の印が残っていた
        let outcome = await AuthGateway.signOut(attempt: {
            attempts += 1
            return answers.removeFirst()
        }, latch: latch)
        XCTAssertEqual(outcome, .signedOut)
        XCTAssertEqual(attempts, 2, "消せなかったのにもう一度試していない")
        XCTAssertFalse(latch.isSet, "消せたのに印が残っている（次の起動でログインできない）")
    }

    /// 2回とも消せなければ、印を残して「消せなかった」を返す。**3回目は試さない**
    func testLeavesTheLatchWhenBothAttemptsFail() async {
        var attempts = 0
        let latch = latch()
        let outcome = await AuthGateway.signOut(attempt: {
            attempts += 1
            return false
        }, latch: latch)
        XCTAssertEqual(outcome, .notClearedLocally)
        XCTAssertEqual(attempts, 2)
        XCTAssertTrue(latch.isSet, "消せなかったのに印を残していない（次の起動でログイン中に戻る）")
    }

    /// 1回で消せたら1回だけ
    func testSucceedsOnTheFirstTry() async {
        var attempts = 0
        let outcome = await AuthGateway.signOut(attempt: { attempts += 1; return true }, latch: latch())
        XCTAssertEqual(outcome, .signedOut)
        XCTAssertEqual(attempts, 1)
    }

    /// Amplify の答えの読み方: `.failed` だけが「端末から消せていない」
    func testReadsAmplifySignOutResults() async {
        XCTAssertFalse(AuthGateway.signedOutLocally(
            AWSCognitoSignOutResult.failed(.unknown("Keychain", nil))))
        XCTAssertTrue(AuthGateway.signedOutLocally(AWSCognitoSignOutResult.complete))
        XCTAssertTrue(AuthGateway.signedOutLocally(AWSCognitoSignOutResult.partial(
            revokeTokenError: nil, globalSignOutError: nil, hostedUIError: nil)),
            "サーバー側の取り消しだけが落ちた回を「消せていない」と読んでいる")
    }

    /// 端末から消せなくても、**画面はログアウトの扱い**にする
    func testScreenSignsOutEvenWhenTheDeviceCouldNotBeCleared() async {
        let auth = AuthStore(gateway: AuthStoreGateway(
            isSignedIn: { true }, currentUserId: { "u1" }, currentUsername: { "n" },
            isSessionExpired: { false }, signOut: { .notClearedLocally }, deleteUser: {},
            latch: .forTesting()))
        await auth.restore()
        XCTAssertEqual(auth.userId, "u1")
        await auth.signOut()
        XCTAssertEqual(auth.state, .signedOut)
    }

    /// 消せない端末の口: ログアウトは毎回落ち、本番と同じく印を1つ進める
    private func stuckGateway(_ latch: SignOutLatch, signOuts: SignOutCounter, log: SignInLog,
                              signIn: @escaping @Sendable () async throws -> Bool = { true }) -> AuthStoreGateway {
        AuthStoreGateway(
            isSignedIn: { true }, currentUserId: { "u1" }, currentUsername: { "n" },
            isSessionExpired: { false },
            signOut: {
                await signOuts.note()
                await log.note("signOut")
                latch.set()
                return .notClearedLocally
            },
            deleteUser: {},
            latch: latch,
            signIn: { _, _ in
                await log.note("signIn")
                return try await signIn()
            })
    }

    /// 🔴 **印があれば、Amplify が「ログイン中」と答えても戻さない。** もう一度消してみる。
    /// **消せない回が上限に達したら諦めて、印の無かった頃と同じくログイン中に戻す**
    /// ——印を持ち続けると、ログインも断られ（invalidState）抜け道が無くなる
    func testRestoreHonoursTheLatchUntilTheLimitThenGivesUp() async {
        let latch = SignOutLatch.forTesting()
        latch.set()  // 本人のログアウトが2回とも落ちた
        let signOuts = SignOutCounter()
        let gateway = stuckGateway(latch, signOuts: signOuts, log: SignInLog())

        for round in 1..<SignOutLatch.limit {
            let auth = AuthStore(gateway: gateway)
            await auth.restore()
            XCTAssertEqual(auth.state, .signedOut, "\(round) 回目の起動で、ログアウトしたはずの人がログイン中に戻った")
        }
        let tries = await signOuts.count
        XCTAssertEqual(tries, SignOutLatch.limit - 1, "起動時にもう一度消してみていない")
        XCTAssertEqual(latch.count, SignOutLatch.limit)

        let auth = AuthStore(gateway: gateway)
        await auth.restore()
        XCTAssertEqual(auth.userId, "u1", "上限に達しても印に従い続けている（誰もログインできない）")
        XCTAssertFalse(latch.isSet, "諦めたのに印が残っている")
    }

    /// 印があるときは、ログインの前に前のログインを消してみる。ログインできたら印を外す
    func testSignInClearsTheOldSessionFirstAndDropsTheLatch() async {
        let latch = SignOutLatch.forTesting()
        latch.set()
        let log = SignInLog()
        let auth = AuthStore(gateway: AuthStoreGateway(
            isSignedIn: { false }, currentUserId: { "u2" }, currentUsername: { "n" },
            isSessionExpired: { false },
            // 消し直しは落ちたが、Cognito のログインは通った（印を外すのはログインの方）
            signOut: { await log.note("signOut"); return .notClearedLocally },
            deleteUser: {}, latch: latch,
            signIn: { _, _ in await log.note("signIn"); return true }))
        // （起動時の消し直しは通さない——ログイン画面から入る順だけを見る）
        await auth.signIn(email: "b@example.test", password: "pw")
        let steps = await log.steps
        XCTAssertEqual(steps, ["signOut", "signIn"], "印があるのにログインの前に消していない")
        XCTAssertEqual(auth.userId, "u2")
        XCTAssertFalse(latch.isSet, "ログインし直せたのに印が残っている（次の起動でログアウトさせる）")
    }

    /// 🔴 **前のログインを消せないまま断られたら（invalidState）、通さない。** 打たれたメールと
    /// パスワードは Cognito で確かめられていないので、前の人のログインを渡さない。
    /// 開き直しを案内する
    func testSignInRefusedByALeftoverSessionIsNotLetThrough() async {
        let latch = SignOutLatch.forTesting()
        latch.set()
        let log = SignInLog()
        let auth = AuthStore(gateway: stuckGateway(latch, signOuts: SignOutCounter(), log: log, signIn: {
            throw AuthError.invalidState("There is already a user in signedIn state", "", nil)
        }))
        await auth.restore()
        await auth.signIn(email: "a@example.test", password: "pw")
        XCTAssertNil(auth.userId, "確かめていない人に前のログインを渡した")
        XCTAssertEqual(auth.lastFailure, .alreadySignedIn)
        XCTAssertEqual(auth.errorMessage, AuthMessage.text(for: .alreadySignedIn))
        XCTAssertTrue(latch.isSet)
    }
}

actor SignInLog {
    private(set) var steps: [String] = []
    func note(_ step: String) { steps.append(step) }
}

extension SignOutLatch {
    /// 試験ごとに別の入れ物（本物の `UserDefaults.standard` に触らない）
    static func forTesting() -> SignOutLatch {
        SignOutLatch(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }
}

actor SignOutCounter {
    private(set) var count = 0
    func note() { count += 1 }
}
