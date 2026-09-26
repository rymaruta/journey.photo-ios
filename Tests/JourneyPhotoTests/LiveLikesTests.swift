import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// いいねの数が、詳細画面（いまの数）と一覧（サイトを建てた時点の数）で
/// 食い違っていた件。**一覧の数をいまの数に差し替える**ところを見る。
final class LiveLikesTests: XCTestCase {

    // MARK: - 応答の読み方

    func testReadsCountsAndTreatsMissingLikesAsZero() {
        let data = Data("""
        [{"id":"a","likes":3},{"id":"b"},{"id":"c","likes":0}]
        """.utf8)
        XCTAssertEqual(LiveLikes.counts(from: data), ["a": 3, "b": 0, "c": 0])
    }

    /// 1行が壊れているだけで全部を捨てない
    func testSkipsBrokenRows() {
        let data = Data("""
        [null, {"likes":5}, {"id":"","likes":1}, {"id":"a","likes":2}]
        """.utf8)
        XCTAssertEqual(LiveLikes.counts(from: data), ["a": 2])
    }

    /// 配列でない（キャプティブポータルの HTML・エラーの JSON）なら使わない
    func testRejectsNonArray() {
        XCTAssertNil(LiveLikes.counts(from: Data("<html></html>".utf8)))
        XCTAssertNil(LiveLikes.counts(from: Data(#"{"error":"x"}"#.utf8)))
    }

    // MARK: - 写し方

    private func photo(_ id: String, likes: Int?) throws -> Photo {
        let likesJSON = likes.map { ",\"likes\":\($0)" } ?? ""
        return try JSONDecoder.api.decode(Photo.self,
            from: Data("{\"id\":\"\(id)\",\"src\":\"https://x/\(id).jpg\"\(likesJSON)}".utf8))
    }

    func testOverwritesStaleCountsAndLeavesUnknownPhotos() throws {
        let photos = [try photo("a", likes: 5), try photo("b", likes: nil), try photo("restricted", likes: 7)]
        let out = LiveLikes.apply(["a": 2, "b": 4], to: photos)
        XCTAssertEqual(out.map(\.likes), [2, 4, 7])
    }

    /// 取り消されて 0 になった写真は、古い数を残さず 0 にする
    func testDropsToZero() throws {
        let out = LiveLikes.apply(["a": 0], to: [try photo("a", likes: 3)])
        XCTAssertEqual(out.first?.likes, 0)
    }

    // MARK: - カードに出す数

    /// 🔴 以前は「いいね済みなら一覧の数に +1」で、**一覧の数に自分のぶんが
    /// 既に入っている**写真は1つ多く出ていた。待っていない間は一覧の数そのまま
    func testDoesNotAddOwnLikeTwice() {
        XCTAssertEqual(LiveLikes.displayCount(base: 3, pendingDelta: 0), 3)
    }

    func testPendingDelta() {
        XCTAssertEqual(LiveLikes.displayCount(base: 3, pendingDelta: 1), 4)
        XCTAssertEqual(LiveLikes.displayCount(base: nil, pendingDelta: 1), 1)
        XCTAssertEqual(LiveLikes.displayCount(base: 0, pendingDelta: -1), 0)
    }
}

/// 公開一覧が、いいねの数だけいまの数に差し替わるか（本物の読み込みを通す）。
final class PublicGalleryLiveLikesTests: XCTestCase {

    private var session: URLSession!
    private let staticURL = URL(string: "https://site.example.test/app/data/photos.json")!
    private let liveURL = URL(string: "https://admin.example.test/photos")!

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

    private func service(live: URL?) -> PublicGalleryService {
        PublicGalleryService(url: staticURL, liveURL: live, session: session,
                             snapshot: PhotoSnapshotStore(fileName: UUID().uuidString))
    }

    private let staticBody = """
    [{"id":"a","src":"https://x/a.jpg","likes":5},{"id":"b","src":"https://x/b.jpg"}]
    """

    func testUsesLiveCounts() async throws {
        // 道の照合は「含む」なので、静的 JSON の道を先に置く
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        StubProtocol.respond(path: "/photos", status: 200, body: #"[{"id":"a","likes":2},{"id":"b","likes":1}]"#)
        let photos = try await service(live: liveURL).fetchPhotos()
        XCTAssertEqual(photos.map(\.likes), [2, 1])
    }

    /// いまの数が取れなくても一覧は出る（数は静的 JSON のまま）
    func testFallsBackWhenLiveFails() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        StubProtocol.respond(path: "/photos", status: 500, body: "{}")
        let gallery = service(live: liveURL)
        let photos = try await gallery.fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["a", "b"])
        XCTAssertEqual(photos.map(\.likes), [5, nil])
        // 取りに行ったうえで諦めている（一度も叩かない実装を通さない）
        XCTAssertEqual(StubProtocol.requestCount, 2)

        // 🔴 失敗した後も、控えがある間は**叩き直さない**。
        // 取れた時刻で見ていた版は、呼ぶたびに管理 API を待ってから一覧を返した
        _ = try await gallery.fetchPhotos()
        XCTAssertEqual(StubProtocol.requestCount, 2)
    }

    /// 口が設定されていなければ叩かない（既存の試験・未設定の環境）
    func testSkipsWhenNotConfigured() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        let photos = try await service(live: nil).fetchPhotos()
        XCTAssertEqual(photos.map(\.likes), [5, nil])
        XCTAssertEqual(StubProtocol.requestCount, 1)
    }
}

/// 詳細で押した数を、ホームと検索に渡す入れ物
@MainActor
final class LikeCountStoreTests: XCTestCase {

    func testKeepsServerAnswers() async {
        let store = LikeCountStore()
        XCTAssertNil(store.count(for: "a"))
        store.set("a", count: 5)
        XCTAssertEqual(store.count(for: "a"), 5)
        store.set("a", count: 4)
        XCTAssertEqual(store.count(for: "a"), 4)
        store.set("b", count: -1)
        XCTAssertEqual(store.count(for: "b"), 0)
    }
}
