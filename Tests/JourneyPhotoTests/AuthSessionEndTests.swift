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
            signOutNotCleared: { false },
            clearSignOutNotCleared: {}
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
            signOutNotCleared: { false }, clearSignOutNotCleared: {}))
        await auth.restore()
        XCTAssertEqual(auth.userId, "u1")
        await auth.signOut()
        XCTAssertEqual(auth.state, .signedOut)
    }

    /// 🔴 **印があれば、Amplify が「ログイン中」と答えても戻さない。** もう一度消してみる
    func testRestoreDoesNotSignBackInWhileTheLatchIsSet() async {
        let signOuts = SignOutCounter()
        let auth = AuthStore(gateway: AuthStoreGateway(
            isSignedIn: { true }, currentUserId: { "u1" }, currentUsername: { "n" },
            isSessionExpired: { false },
            signOut: { await signOuts.note(); return .notClearedLocally },
            deleteUser: {},
            signOutNotCleared: { true }, clearSignOutNotCleared: {}))
        await auth.restore()
        XCTAssertEqual(auth.state, .signedOut, "ログアウトしたはずの人が、起動し直しただけでログイン中に戻った")
        let count = await signOuts.count
        XCTAssertEqual(count, 1, "起動時にもう一度消してみていない")
    }
}

actor SignOutCounter {
    private(set) var count = 0
    func note() { count += 1 }
}
