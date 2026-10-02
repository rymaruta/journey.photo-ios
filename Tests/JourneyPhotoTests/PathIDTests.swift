import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// パスに入れる ID・トークン（`PathID`）。
///
/// 🔴 `.urlPathAllowed` は `/` と `.` を通すので、`../user/account` のような値で
/// 写真の削除が `DELETE /user/account`（退会）に化けうる。親しい友達の口は符号化すらなかった。
final class PathIDTests: XCTestCase {

    /// サーバーが実際に配る形（pg-dev の api-user で確かめた）は全部通す
    func testAcceptsTheShapesTheServerHandsOut() throws {
        let valid = [
            "a129394d-f386-4795-9623-2d6e915d20c7",          // 写真（uuidv4）・アルバム・ハイライト・旅行プラン
            "67d49a68-80f1-7083-b0e0-c767886ef868",          // Cognito の sub
            "story-1b4e28ba-2fa1-11d2-883f-0016d3cca427",    // ストーリー
            "sp_92dc681b0f47",                               // スポット
            "Zm9vYmFyLWJhel9xdXgtMTIzNDU2Nzg5MGFi",          // 招待（24 バイトの base64url = 32 文字）
            "-_aZ09",                                         // base64url は - と _ を含む
        ]
        for id in valid {
            XCTAssertTrue(PathID.isSafe(id), "正しい ID を弾いている: \(id)")
            XCTAssertEqual(try PathID.segment(id), id, "通す値を書き換えている（符号化は要らない）")
        }
        // 本物の招待トークンの作り方（24 バイト → base64url）で作った値も通る
        for _ in 0..<50 {
            let bytes = (0..<24).map { _ in UInt8.random(in: 0...255) }
            let token = Data(bytes).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            XCTAssertTrue(PathID.isSafe(token), "招待トークンを弾いている: \(token)")
        }
    }

    func testRejectsAnythingThatCouldChangeThePath() {
        let invalid = [
            "", "../user/account", "..", ".", "a/b", "a.b", "a b", "a?b=1", "a#b", "a%2Fb",
            "パリ", "a\u{0}b", "a\nb", String(repeating: "a", count: PathID.maxLength + 1),
        ]
        for id in invalid {
            XCTAssertFalse(PathID.isSafe(id), "パスを変えうる値を通している: \(id.debugDescription)")
            XCTAssertThrowsError(try PathID.segment(id)) {
                XCTAssertEqual($0 as? APIError, .invalidIdentifier)
            }
        }
    }
}

/// 形の違う ID では**要求を出さない**（各サービスが `PathID` を通している）
final class PathIDServiceTests: XCTestCase {

    private var api: APIClient!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        StubProtocol.reset()
        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
        api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                        tokenProvider: StubTokenProvider(token: "t"),
                        session: URLSession(configuration: config))
    }

    override func tearDown() {
        StubProtocol.reset()
        super.tearDown()
    }

    private func assertNoRequest(_ label: String, _ work: () async throws -> Void,
                                 file: StaticString = #filePath, line: UInt = #line) async {
        StubProtocol.reset()
        do {
            try await work()
            XCTFail("\(label): 投げるはず", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? APIError, .invalidIdentifier, "\(label): \(error)", file: file, line: line)
        }
        XCTAssertEqual(StubProtocol.requestCount, 0, "\(label): 形の違う ID で要求を出している", file: file, line: line)
    }

    func testServicesRefuseBadIdsBeforeSending() async {
        let photos = PhotoService(api: api)
        let albums = AlbumService(api: api)
        let social = SocialService(api: api)
        let profiles = ProfileService(api: api)
        await assertNoRequest("写真の削除") { try await photos.delete(photoId: "../user/account") }
        await assertNoRequest("写真の更新") { try await photos.update(photoId: "a/b", patch: PhotoPatch()) }
        await assertNoRequest("アルバムの削除") { try await albums.delete(id: "../x") }
        await assertNoRequest("招待") { _ = try await albums.join(token: "a.b") }
        await assertNoRequest("親しい友達") { _ = try await social.setCloseFriend(userId: "../account", wanted: true) }
        await assertNoRequest("コメントの削除") { try await social.deleteComment(photoId: "p1", commentId: "a/b") }
        await assertNoRequest("公開プロフィール") { _ = try await profiles.publicProfile(userId: "a/../b") }
    }

    /// 壊れた `%` の道は落とさずに失敗にする（`percentEncodedPath` は壊れた `%` で落ちる）
    func testBrokenPercentInPathFailsWithoutCrashing() async {
        StubProtocol.reset()
        do {
            try await api.authorizedVoid(.get, "/user/spots/a%zz")
            XCTFail("投げるはず")
        } catch {
            guard case .decoding = error as? APIError else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(StubProtocol.requestCount, 0)
    }

    /// 正しい ID はそのままパスに載る
    func testGoodIdsAreSentAsIs() async throws {
        let id = "story-1b4e28ba-2fa1-11d2-883f-0016d3cca427"
        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
        try await StoryService(api: api).delete(id: id)
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/stories/\(id)")

        StubProtocol.respond(status: 200, body: #"{"userId":"x","closeFriend":true}"#)
        _ = try await SocialService(api: api).setCloseFriend(userId: "67d49a68-80f1-7083-b0e0-c767886ef868", wanted: true)
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/user/close-friends/67d49a68-80f1-7083-b0e0-c767886ef868")
    }
}
