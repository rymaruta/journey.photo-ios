import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 退会済み（410）は、どの口でも「退会の途中」に回す（`APIClient.attempt`・2026-10-21）。
///
/// 🔴 サーバーは 10/18 から退会した人の書く口を 410 で塞ぐ（`liveCaller.ts`）。アプリが 410 を
/// 「退会の途中」として受けるのは自分のプロフィールの読み込みだけで、投稿・コメント・いいねでは
/// 日本語の断り文が出るだけだった。
@MainActor
final class AccountGoneTests: XCTestCase {

    /// ほかの試験の `AuthStore`（"u1" でログイン中）に知らせが届いても効かない人
    private let me = "gone-me"
    private let goneBody = #"{"error":"このアカウントは削除されています"}"#

    override func setUp() {
        super.setUp()
        StubProtocol.reset()
    }

    override func tearDown() {
        StubProtocol.reset()
        super.tearDown()
    }

    /// 本番と同じ知らせ方（`CognitoTokenProvider.accountGone`）に回す提供者。鍵は `sub` 入り
    private struct Provider: TokenProviding {
        let sub: String
        func idToken() async throws -> String? { FakeJWT.make(sub: sub, tag: "t") }
        func accountGone(idToken: String) async { await CognitoTokenProvider().accountGone(idToken: idToken) }
    }

    private func api(sub: String) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return APIClient(baseURL: URL(string: "https://api.example.test")!,
                         tokenProvider: Provider(sub: sub), session: URLSession(configuration: config))
    }

    private func signedIn(as id: String) async -> AuthStore {
        let auth = AuthStore(gateway: AuthStoreGateway(
            isSignedIn: { true }, currentUserId: { id }, currentUsername: { "uuid-\(id)" },
            isSessionExpired: { false }, signOut: { .signedOut }, deleteUser: {},
            latch: .forTesting()))
        await auth.restore()
        XCTAssertEqual(auth.userId, id, "下ごしらえ: ログイン中になる")
        return auth
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition(), "待っても立たなかった", file: file, line: line)
    }

    /// 知らせが届くはずの時間だけ待つ（「立たない」を見る試験用）
    private func settle() async {
        for _ in 0..<20 { await Task.yield(); try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    // MARK: - どの口でも

    func testLikeGoneRaisesPendingDeletion() async {
        let auth = await signedIn(as: me)
        StubProtocol.respond(status: 410, body: goneBody)
        _ = try? await SocialService(api: api(sub: me)).like(photoId: "p1")
        await waitUntil { auth.deletionPending }
    }

    func testCommentGoneRaisesPendingDeletion() async {
        let auth = await signedIn(as: me)
        StubProtocol.respond(status: 410, body: goneBody)
        do {
            _ = try await SocialService(api: api(sub: me)).postComment(photoId: "p1", text: "きれい")
            XCTFail("投げるはず")
        } catch {
            XCTAssertEqual((error as? APIError)?.isAccountGone, true)
        }
        await waitUntil { auth.deletionPending }
    }

    func testPhotoSaveGoneRaisesPendingDeletion() async throws {
        let auth = await signedIn(as: me)
        let presigned = try JSONDecoder().decode(UploadService.PresignResponse.self, from: Data(#"""
        {"presignedUrl":"https://s3.example.test/put","key":"uploads/x.jpg",
         "publicUrl":"https://cdn.example.test/x.jpg","photoId":"p1","contentType":"image/jpeg"}
        """#.utf8))
        StubProtocol.respond(status: 410, body: goneBody)
        _ = try? await UploadService(api: api(sub: me)).save(PhotoDraft(), presigned: presigned)
        await waitUntil { auth.deletionPending }
    }

    /// 自分のプロフィールの 410 も同じ入口から1回だけ（`ProfileService` は自分で知らせない）
    func testProfileGoneIsAnnouncedOnce() async {
        let auth = await signedIn(as: me)
        let counter = NoticeCounter()
        let token = NotificationCenter.default.addObserver(forName: .accountDeletionPending, object: nil, queue: nil) { _ in
            counter.add()
        }
        defer { NotificationCenter.default.removeObserver(token) }
        StubProtocol.respond(status: 410, body: goneBody)
        _ = try? await ProfileService(api: api(sub: me)).myProfile()
        await waitUntil { auth.deletionPending }
        await settle()
        XCTAssertEqual(counter.count, 1, "410 の知らせが二重に出た")
    }

    // MARK: - 別の人に効かない

    /// 人が替わったあとに届いた前の人の 410 で、いまの人を退会の扱いにしない
    func testOldGoneOfAnotherPersonDoesNotAffectCurrentUser() async {
        let auth = await signedIn(as: me)
        StubProtocol.respond(status: 410, body: goneBody)
        _ = try? await SocialService(api: api(sub: "previous-person")).like(photoId: "p1")
        await settle()
        XCTAssertFalse(auth.deletionPending, "前の人の 410 で、いまの人に「退会の途中」が出た")
        // 同じ人の 410 なら立つ（知らせが届く時間は足りている）
        _ = try? await SocialService(api: api(sub: me)).like(photoId: "p1")
        await waitUntil { auth.deletionPending }
    }

    /// 人の添えられていない知らせ・違う人の知らせは受けない
    func testStoreChecksTheGonePerson() async {
        let auth = await signedIn(as: me)
        NotificationCenter.default.post(name: .accountDeletionPending, object: nil)
        auth.noteDeletionPending(userId: "someone-else")
        await settle()
        XCTAssertFalse(auth.deletionPending)
        auth.noteDeletionPending(userId: me)
        XCTAssertTrue(auth.deletionPending)
    }

    /// 招待リンクの期限切れも 410（`invite.ts`）。**退会の扱いにしない**——「完了する」で
    /// 生きている人のアカウントを消すことになる
    func testInviteGoneDoesNotRaisePendingDeletion() async {
        let auth = await signedIn(as: me)
        StubProtocol.respond(status: 410, body: #"{"error":"この招待リンクは期限が切れています。送った人にもう一度もらってください"}"#)
        do {
            _ = try await AlbumService(api: api(sub: me)).join(token: "abcDEF123")
            XCTFail("投げるはず")
        } catch {
            XCTAssertEqual((error as? APIError)?.isGone, true)
            XCTAssertEqual((error as? APIError)?.isAccountGone, false)
        }
        await settle()
        XCTAssertFalse(auth.deletionPending)
    }

    func testGoneFlags() async {
        XCTAssertTrue(APIError.server(status: 410, message: "").isGone)
        XCTAssertFalse(APIError.server(status: 410, message: "").isAccountGone)
        XCTAssertTrue(APIError.server(status: 410, message: APIError.accountGoneMessage).isAccountGone)
        XCTAssertFalse(APIError.server(status: 404, message: APIError.accountGoneMessage).isGone)
        XCTAssertFalse(APIError.unreachable.isGone)
    }
}

private final class NoticeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func add() { lock.lock(); value += 1; lock.unlock() }
}
