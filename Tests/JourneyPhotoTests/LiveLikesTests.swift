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
        let asOf = Date(timeIntervalSince1970: 100)
        let out = LiveLikes.apply(["a": 2, "b": 4], asOf: asOf, to: photos)
        XCTAssertEqual(out.map(\.likes), [2, 4, 7])
        XCTAssertEqual(out.map(\.likesAsOf), [asOf, asOf, nil])
    }

    /// 取り消されて 0 になった写真は、古い数を残さず 0 にする
    func testDropsToZero() throws {
        let out = LiveLikes.apply(["a": 0], asOf: Date(), to: [try photo("a", likes: 3)])
        XCTAssertEqual(out.first?.likes, 0)
    }

    // MARK: - 押した答えと一覧の、新しい方

    private func entry(_ count: Int, at seconds: TimeInterval) -> LikeCountStore.Entry {
        LikeCountStore.Entry(count: count, at: Date(timeIntervalSince1970: seconds))
    }

    /// 詳細で押して戻った（答えの方が新しい）→ 答え
    func testAnswerNewerThanListWins() throws {
        var p = try photo("a", likes: 4)
        p.likesAsOf = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(LiveLikes.base(for: p, stored: entry(5, at: 200)), 5)
    }

    /// 🔴 そのあと引き下げ更新でいまの数が取れた（一覧の方が新しい）→ 一覧。
    /// 答えを無条件に優先していた版は、ここで古い答えに止まっていた
    func testListNewerThanAnswerWins() throws {
        var p = try photo("a", likes: 7)
        p.likesAsOf = Date(timeIntervalSince1970: 300)
        XCTAssertEqual(LiveLikes.base(for: p, stored: entry(5, at: 200)), 7)
    }

    /// 🔴 押して数秒で引き下げ更新した回。要求は答えより新しいが、サーバーの
    /// 控え（Lambda の10秒）で中身は押す前の数でありうる → 答えを出す
    func testListWithinServerStalenessLosesToAnswer() throws {
        var p = try photo("a", likes: 4)
        p.likesAsOf = Date(timeIntervalSince1970: 205)
        XCTAssertEqual(LiveLikes.base(for: p, stored: entry(5, at: 200)), 5)
        p.likesAsOf = Date(timeIntervalSince1970: 200 + LiveLikes.serverStaleness)
        XCTAssertEqual(LiveLikes.base(for: p, stored: entry(5, at: 200)), 4)
    }

    /// 静的 JSON のまま（いまの数が取れていない）はどの答えより古い
    func testStaticListLosesToAnswer() throws {
        XCTAssertEqual(LiveLikes.base(for: try photo("a", likes: 9), stored: entry(5, at: 0)), 5)
        XCTAssertEqual(LiveLikes.base(for: try photo("a", likes: 9), stored: nil), 9)
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

    /// 公開範囲を絞った写真にも、いまの数の時刻が付く。付かないと
    /// 押した答えが永久に勝ち、引き下げ更新でも他の人のいいねが出ない
    func testRestrictedPhotosAreStamped() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        let gallery = service(live: nil)
        let restricted = try JSONDecoder.api.decode(Photo.self, from: Data(
            #"{"id":"r","src":"https://x/r.jpg","likes":8,"audience":"followers"}"#.utf8))
        await gallery.setRestrictedLoader { [restricted] }
        let photos = try await gallery.fetchPhotos()
        let r = try XCTUnwrap(photos.first { $0.id == "r" })
        XCTAssertEqual(r.likes, 8)
        XCTAssertNotNil(r.likesAsOf)
    }

    /// 🔴 **取得の途中で引き下げ更新したら、自分でも取りに行く。**
    /// 途中の要求の結果で済ませていた版は、その要求が失敗していれば
    /// 利用者が引いたのに、いまの数なしで返っていた
    func testForceDuringInFlightFetchesAgain() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        StubProtocol.respond(path: "/photos", status: 500, body: "{}", delay: 0.3)
        let gallery = service(live: liveURL)
        async let first = gallery.fetchPhotos()
        try await Task.sleep(nanoseconds: 100_000_000)
        async let forced = gallery.fetchPhotos(force: true)
        _ = try await (first, forced)
        // 静的 JSON 2回 ＋ いまの数 2回（途中の1回に相乗りしない）
        XCTAssertEqual(StubProtocol.requestCount, 4)
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
        XCTAssertNil(store.entry(for: "a"))
        store.set("a", count: 5, at: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(store.entry(for: "a"), LikeCountStore.Entry(count: 5, at: Date(timeIntervalSince1970: 1)))
        store.set("b", count: -1)
        XCTAssertEqual(store.entry(for: "b")?.count, 0)
    }
}
