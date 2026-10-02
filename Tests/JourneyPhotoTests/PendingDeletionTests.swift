import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 退会の途中で止まったアカウント（自分のプロフィールが 410）。
///
/// 🔴 退会の画面で Cognito の削除だけが落ちたまま閉じると、覚えていたのは画面の `@State`
/// だけだった。その人はログインできるのに、サーバーは墓石を置いていて 410 を返す
/// （`userProfile.ts` の `getMyProfile`）——iOS は 410 を扱っておらず、何も使えないまま残った。
@MainActor
final class PendingDeletionTests: XCTestCase {

    private func profiles() -> ProfileService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        StubProtocol.reset()
        return ProfileService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                             tokenProvider: StubTokenProvider(token: "t"),
                                             session: URLSession(configuration: config)))
    }

    private final class Calls: @unchecked Sendable {
        var deleteUser = 0
        var signOut = 0
        var deleteFails = false
    }

    private func signedIn(_ calls: Calls) async -> AuthStore {
        let auth = AuthStore(gateway: AuthStoreGateway(
            isSignedIn: { true }, currentUserId: { "u1" }, currentUsername: { "uuid-u1" },
            isSessionExpired: { false },
            signOut: { calls.signOut += 1; return .signedOut },
            deleteUser: {
                calls.deleteUser += 1
                if calls.deleteFails { throw APIError.unreachable }
            },
            latch: .forTesting()))
        await auth.restore()
        XCTAssertEqual(auth.userId, "u1", "下ごしらえ: ログイン中になる")
        return auth
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition(), "待っても立たなかった", file: file, line: line)
    }

    /// 自分のプロフィールが 410 なら、ログイン中の `AuthStore` に「退会の途中」が立つ
    func testGoneProfileRaisesPendingDeletion() async {
        let auth = await signedIn(Calls())
        let profiles = profiles()
        StubProtocol.respond(status: 410, body: #"{"error":"このアカウントは削除されています"}"#)
        defer { StubProtocol.reset() }
        do {
            _ = try await profiles.myProfile()
            XCTFail("投げるはず")
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 410, message: "このアカウントは削除されています"))
        }
        await waitUntil { auth.deletionPending }
    }

    /// 410 以外（通信できない・404・500）では立てない
    func testOtherFailuresDoNotRaisePendingDeletion() async {
        XCTAssertTrue(ProfileService.meansAccountDeleted(APIError.server(status: 410, message: "")))
        XCTAssertFalse(ProfileService.meansAccountDeleted(APIError.server(status: 404, message: "")))
        XCTAssertFalse(ProfileService.meansAccountDeleted(APIError.server(status: 500, message: "")))
        XCTAssertFalse(ProfileService.meansAccountDeleted(APIError.unreachable))
    }

    /// 未ログインでは立てない（前の人の 410 が遅れて届いた回）
    func testSignedOutStoreIgnoresTheNotice() async {
        let auth = AuthStore(gateway: AuthStoreGateway(
            isSignedIn: { false }, currentUserId: { "" }, currentUsername: { "" },
            isSessionExpired: { false }, signOut: { .signedOut }, deleteUser: {},
            latch: .forTesting()))
        auth.noteDeletionPending()
        XCTAssertFalse(auth.deletionPending)
    }

    /// 「完了する」で退会の後半を済ませる: 通知の宛先の後片付け → Cognito の削除 → 端末の控えの削除
    func testFinishingDeletesCognitoUserAndLocalData() async {
        let calls = Calls()
        let auth = await signedIn(calls)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let likes = FavoritesStore(defaults: defaults); likes.use(userId: "u1"); likes.set("p", favorite: true)

        auth.noteDeletionPending()
        var released = 0
        var order: [String] = []
        await auth.finishPendingDeletion(deleteServerData: { order.append("server") },
                                         releaseDevice: { released += 1; order.append("device") },
                                         localDefaults: defaults)
        XCTAssertEqual(order, ["server", "device"],
                       "サーバーの退会をやり直していない（墓石の後の掃除が孤立する）")

        XCTAssertEqual(calls.deleteUser, 1, "Cognito の利用者を消していない")
        XCTAssertEqual(released, 1, "通知の宛先を片づけていない")
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertFalse(auth.deletionPending)
        let after = FavoritesStore(defaults: defaults); after.use(userId: "u1")
        XCTAssertTrue(after.ids.isEmpty, "退会したのに端末の控えが残っている")
    }

    /// Cognito の削除が落ちたら、ログイン中のまま「途中」を残して理由を出す（控えは消さない）
    func testFailureKeepsThePendingStateAndLocalData() async {
        let calls = Calls()
        calls.deleteFails = true
        let auth = await signedIn(calls)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let likes = FavoritesStore(defaults: defaults); likes.use(userId: "u1"); likes.set("p", favorite: true)

        auth.noteDeletionPending()
        await auth.finishPendingDeletion(deleteServerData: {}, releaseDevice: {}, localDefaults: defaults)

        XCTAssertTrue(auth.deletionPending, "消せなかったのに「途中」を下ろした（もう一度押せない）")
        XCTAssertNotNil(auth.deletionFailure)
        XCTAssertFalse(auth.isFinishingDeletion)
        XCTAssertEqual(auth.userId, "u1")
        let after = FavoritesStore(defaults: defaults); after.use(userId: "u1")
        XCTAssertFalse(after.ids.isEmpty, "アカウントが残っているのに控えを消した")
    }

    /// 🔴 **サーバーの退会のやり直しが落ちたら、Cognito に進まない。** 先に Cognito を消すと、
    /// 墓石の後の掃除（フォロー・お知らせ・いいね）を消せる人がいなくなる
    func testServerFailureStopsBeforeCognito() async {
        let calls = Calls()
        let auth = await signedIn(calls)
        auth.noteDeletionPending()
        var released = 0
        await auth.finishPendingDeletion(deleteServerData: { throw APIError.unreachable },
                                         releaseDevice: { released += 1 })
        XCTAssertEqual(calls.deleteUser, 0, "サーバーの掃除が残ったまま Cognito を消した")
        XCTAssertEqual(released, 0)
        XCTAssertTrue(auth.deletionPending)
        XCTAssertNotNil(auth.deletionFailure)
        XCTAssertEqual(auth.userId, "u1")
    }

    /// 「完了する」の二度押しで2本走らせない（門は押したその場で閉じる）
    func testDoubleTapStartsOnlyOnce() async {
        let calls = Calls()
        let auth = await signedIn(calls)
        auth.noteDeletionPending()
        auth.startFinishingDeletion(deleteServerData: {}, releaseDevice: {})
        auth.startFinishingDeletion(deleteServerData: {}, releaseDevice: {})
        await waitUntil { !auth.isFinishingDeletion }
        XCTAssertEqual(calls.deleteUser, 1)
    }
}
