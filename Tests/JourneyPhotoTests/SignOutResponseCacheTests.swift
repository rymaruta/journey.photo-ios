import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// サインアウト・退会で**通信の控え（URLCache）を空にする**（2026-10-03 の品質点検）。
///
/// `/user/profile`・`/user/photos`（下書きと限定写真の署名つき URL）・`/user/notifications` は
/// Cache-Control を付けずに返り、限定写真の画像も `AsyncImage` を通して同じ控えに入る。
/// 消していたのは設定画面の「キャッシュを消す」だけで、前の人の応答が端末に残っていた。
@MainActor
final class SignOutResponseCacheTests: XCTestCase {

    private func gateway() -> AuthStoreGateway {
        AuthStoreGateway(
            isSignedIn: { true },
            currentUserId: { "u1" },
            currentUsername: { "name-u1" },
            isSessionExpired: { false },
            signOut: { .signedOut },
            deleteUser: {},
            latch: .forTesting()
        )
    }

    /// 試験ごとの控え（Linux の corelibs は置き場の指定が要る）
    private func cacheWithOneResponse() throws -> (URLCache, URLRequest) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("signout-cache-\(UUID().uuidString)")
        let cache = URLCache(memoryCapacity: 1 << 20, diskCapacity: 1 << 20, diskPath: directory.path)
        let request = URLRequest(url: URL(string: "https://api.example.test/user/photos")!)
        let response = try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: 200,
                                                     httpVersion: "HTTP/1.1", headerFields: nil))
        cache.storeCachedResponse(CachedURLResponse(response: response, data: Data(#"{"items":[]}"#.utf8)),
                                  for: request)
        XCTAssertNotNil(cache.cachedResponse(for: request), "下ごしらえ: 控えに入っている")
        return (cache, request)
    }

    func testSignOutEmptiesTheResponseCache() async throws {
        let (cache, request) = try cacheWithOneResponse()
        let auth = AuthStore(gateway: gateway())
        auth.responseCache = cache
        await auth.restore()
        XCTAssertEqual(auth.userId, "u1")

        await auth.signOut()

        XCTAssertNil(cache.cachedResponse(for: request), "前の人の応答が控えに残っている")
    }

    /// 期限切れのログアウトも同じ道（`expireSession` → `signOut`）
    func testExpiredSessionEmptiesTheResponseCache() async throws {
        let (cache, request) = try cacheWithOneResponse()
        let auth = AuthStore(gateway: gateway())
        auth.responseCache = cache
        await auth.restore()

        await auth.expireSession()

        XCTAssertNil(auth.userId)
        XCTAssertNil(cache.cachedResponse(for: request), "期限切れのログアウトで控えが残っている")
    }

    /// 退会（Cognito の利用者を消す）でも空にする
    func testAccountDeletionEmptiesTheResponseCache() async throws {
        let (cache, request) = try cacheWithOneResponse()
        let auth = AuthStore(gateway: gateway())
        auth.responseCache = cache
        await auth.restore()

        try await auth.deleteCognitoUser()

        XCTAssertNil(cache.cachedResponse(for: request), "退会しても前の人の応答が控えに残っている")
    }

    /// ログインし直す（起動時の復元）だけでは消さない——画像の控えを毎回捨てると遅くなる
    func testRestoreKeepsTheResponseCache() async throws {
        let (cache, request) = try cacheWithOneResponse()
        let auth = AuthStore(gateway: gateway())
        auth.responseCache = cache

        await auth.restore()

        XCTAssertNotNil(cache.cachedResponse(for: request), "起動のたびに控えを捨てている")
    }
}
