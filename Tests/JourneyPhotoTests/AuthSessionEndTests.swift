import XCTest
@testable import JourneyPhoto

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
            },
            deleteUser: {}
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

actor SignOutCounter {
    private(set) var count = 0
    func note() { count += 1 }
}
