import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 公開一覧の読み込み。**壊れ方が画面に出る場所**なので、実際に走らせて見る。
final class PublicGalleryServiceTests: XCTestCase {

    private var session: URLSession!
    private let url = URL(string: "https://site.example.test/app/data/photos.json")!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset()
        AppConfig.testOverrides = [
            "JPEnvironmentName": "staging",
            "JPSiteBaseURL": "https://site.example.test",
            "JPUserApiBaseURL": "https://api.example.test",
            "JPCognitoUserPoolId": "pool",
            "JPCognitoClientId": "client",
            "JPCognitoRegion": "ap-northeast-1",
        ]
    }

    override func tearDown() {
        StubProtocol.reset()
        AppConfig.testOverrides = nil
        super.tearDown()
    }

    private func service(snapshot: String = UUID().uuidString) -> PublicGalleryService {
        PublicGalleryService(url: url, session: session, snapshot: PhotoSnapshotStore(fileName: snapshot))
    }

    private let twoPhotos = """
    [{"id":"a","src":"https://x/a.jpg","userId":"u1"},
     {"id":"b","src":"https://x/b.jpg","userId":"u2"}]
    """

    func testReadsPublishedPhotos() async throws {
        StubProtocol.respond(status: 200, body: twoPhotos)
        let photos = try await service().fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["a", "b"])
    }

    /// `published: false` が混ざっても出さない（二重の守り）。
    func testHidesUnpublishedRows() async throws {
        StubProtocol.respond(status: 200, body: """
        [{"id":"a","src":"https://x/a.jpg"},{"id":"draft","src":"https://x/d.jpg","published":false}]
        """)
        let photos = try await service().fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["a"])
    }

    /// **ブロックした相手と、通報した写真を落とす。**
    /// 公開一覧は静的な JSON なので、サーバー側では絞れない。
    func testHidesBlockedUsersAndReportedPhotos() async throws {
        StubProtocol.respond(status: 200, body: twoPhotos)
        let gallery = service()
        await gallery.setHidden(ModerationSnapshot(blocked: ["u2"], reported: []))
        var photos = try await gallery.fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["a"], "ブロックした相手の写真が出ている")

        await gallery.setHidden(ModerationSnapshot(blocked: [], reported: ["a"]))
        photos = try await gallery.fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["b"], "通報した写真が出ている")
    }

    /// **圏外なら前回のぶんを出す。**
    func testFallsBackToSnapshotWhenOffline() async throws {
        let name = UUID().uuidString
        let gallery = service(snapshot: name)
        StubProtocol.respond(status: 200, body: twoPhotos)
        _ = try await gallery.fetchPhotos()

        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        let offline = try await service(snapshot: name).fetchPhotos()
        XCTAssertEqual(offline.map(\.id), ["a", "b"])
    }

    /// **壊れた応答を控えない。** キャプティブポータル（ホテルの Wi-Fi）は
    /// 200 でログイン HTML を返す。控えると、次から圏外でそれが出る。
    func testDoesNotCacheGarbageResponse() async throws {
        let name = UUID().uuidString
        StubProtocol.respond(status: 200, body: twoPhotos)
        _ = try await service(snapshot: name).fetchPhotos()

        StubProtocol.respond(status: 200, body: "<html>Wi-Fi にログインしてください</html>")
        // HTML は配列として読めないので、控えに落ちる
        let afterGarbage = try await service(snapshot: name).fetchPhotos()
        XCTAssertEqual(afterGarbage.map(\.id), ["a", "b"], "壊れた応答で控えが潰れた")
    }

    /// **1件も読めなかった回も控えを上書きしない。**
    func testDoesNotOverwriteSnapshotWhenEverythingIsUnreadable() async throws {
        let name = UUID().uuidString
        StubProtocol.respond(status: 200, body: twoPhotos)
        _ = try await service(snapshot: name).fetchPhotos()

        StubProtocol.respond(status: 200, body: #"[{"id":"x","src":123}]"#)
        _ = try await service(snapshot: name).fetchPhotos()

        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        let offline = try await service(snapshot: name).fetchPhotos()
        XCTAssertEqual(offline.map(\.id), ["a", "b"], "読めない応答で控えが潰れた")
    }

    // MARK: - 限定公開の読み出し口の入れ替え（ログアウト・別の人のログイン）

    /// 入れ替えるたびに回数を流す。**今の回数から始める**（開き直した画面が
    /// 離れていた間の入れ替えを取りこぼさない）
    func testRestrictedChangesStartFromCurrentAndFollowSwaps() async {
        let gallery = service()
        await gallery.setRestrictedLoader { [] }
        var iterator = await gallery.restrictedChanges().makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first, 1)
        await gallery.setRestrictedLoader(nil)
        let second = await iterator.next()
        XCTAssertEqual(second, 2)
    }

    /// 🔴 **読んでいる途中で口が替わったら、前の人の分を控えに書かない。**
    /// 書くと、次にログインした人に前の人の限定公開の写真が60秒出ていた
    func testSwapDuringRestrictedFetchDoesNotCacheThePreviousUser() async throws {
        StubProtocol.respond(status: 200, body: twoPhotos)
        let gallery = service()
        let previous = try JSONDecoder.api.decode(Photo.self, from: Data(
            #"{"id":"mine","src":"https://x/m.jpg","audience":"followers"}"#.utf8))
        let next = try JSONDecoder.api.decode(Photo.self, from: Data(
            #"{"id":"theirs","src":"https://x/t.jpg","audience":"followers"}"#.utf8))
        await gallery.setRestrictedLoader {
            // 読んでいる途中で次の人がログインする
            await gallery.setRestrictedLoader { [next] }
            return [previous]
        }
        let during = try await gallery.fetchPhotos()
        XCTAssertFalse(during.contains { $0.id == "mine" }, "入れ替わった後に前の人の分を出している")
        let after = try await gallery.fetchPhotos()
        XCTAssertFalse(after.contains { $0.id == "mine" }, "前の人の分が控えに残っている")
        XCTAssertTrue(after.contains { $0.id == "theirs" })
    }
}

/// 公開一覧の控え。
///
/// **この口は画面を開くたびに全員が叩く**——一覧・検索・地図・お気に入り・
/// タグ・お知らせ、そして写真を1枚開くたびに「この近くで撮られた写真」と
/// 撮影スポットの行まで（`PhotoDetailView`）。
/// サイト側は `no-store` で配るので、控えが無いと毎回まるごと落ちてくる。
final class GalleryCacheTests: XCTestCase {

    private func service() -> PublicGalleryService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        StubProtocol.reset()
        StubProtocol.respond(status: 200, body: #"[{"id":"a","src":"https://x/a.jpg"}]"#)
        return PublicGalleryService(
            url: URL(string: "https://site.example.test/app/data/photos.json")!,
            session: URLSession(configuration: config),
            snapshot: PhotoSnapshotStore(fileName: UUID().uuidString)
        )
    }

    func testSecondReadUsesTheCache() async throws {
        let gallery = service()
        _ = try await gallery.fetchPhotos()
        let after = StubProtocol.requestCount
        _ = try await gallery.fetchPhotos()
        XCTAssertEqual(StubProtocol.requestCount, after, "控えがあるのに落とし直している")
    }

    /// **引き下げ更新は控えを無視する。** 自分で引いたのに古いものを出さない。
    func testForcedReadIgnoresTheCache() async throws {
        let gallery = service()
        _ = try await gallery.fetchPhotos()
        let after = StubProtocol.requestCount
        _ = try await gallery.fetchPhotos(force: true)
        XCTAssertEqual(StubProtocol.requestCount, after + 1, "引き下げても取り直していない")
    }

    /// **控えを返す回も絞り込みは掛かる。** ブロックの反映が遅れない。
    func testCachedReadStillHides() async throws {
        let gallery = service()
        _ = try await gallery.fetchPhotos()
        await gallery.setHidden(ModerationSnapshot(blocked: [], reported: ["a"]))
        let photos = try await gallery.fetchPhotos()
        XCTAssertTrue(photos.isEmpty, "控えを返すときに絞り込みを飛ばしている")
    }
}

/// **同時の取得は1本にまとめる**（`fetchStaticList`・docs/QUALITY_2026-10-03.md の P2）。
/// 呼び手の1つが取り消されても、ほかの呼び手の取得は止まらない（取り消しは待ちだけを外す）
final class PublicGalleryCoalescingTests: XCTestCase {

    private var session: URLSession!
    private let url = URL(string: "https://site.example.test/app/data/photos.json")!
    private let twoPhotos = """
    [{"id":"a","src":"https://x/a.jpg","userId":"u1"},
     {"id":"b","src":"https://x/b.jpg","userId":"u2"}]
    """

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset()
        StubProtocol.respond(status: 200, body: twoPhotos)
    }

    override func tearDown() {
        StubProtocol.reset()
        super.tearDown()
    }

    /// 一覧の要求の手前で `gate` に止まるサービス（端末の控えは毎回新しい名前で空）
    private func service(_ gate: Gate) -> PublicGalleryService {
        PublicGalleryService(url: url, session: session,
                             snapshot: PhotoSnapshotStore(fileName: UUID().uuidString),
                             beforeStaticRequest: { await gate.wait() })
    }

    /// 呼び手が取得まで進むのを待つ（`fetchPhotos` は actor を何度か行き来してから取りに行く）
    private func settle() async throws {
        for _ in 0..<10 { await Task.yield() }
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    /// 同時に3つ来ても、取りに行くのは1回。3つとも同じ一覧を受け取る
    func testConcurrentFetchesShareOneRequest() async throws {
        let gate = Gate()
        let gallery = service(gate)
        let calls = (0..<3).map { _ in Task { try await gallery.fetchPhotos() } }
        await gate.untilWaiting(1)
        try await settle()
        let arrived = await gate.arrived
        XCTAssertEqual(arrived, 1, "同じ一覧を同時に \(arrived) 本取りに行っている")
        await gate.open()
        for call in calls {
            let photos = try await call.value
            XCTAssertEqual(photos.map(\.id), ["a", "b"])
        }
        XCTAssertEqual(StubProtocol.requestCount, 1)
    }

    /// 先に始めた呼び手が取り消されても、相乗りした呼び手の取得は止まらない。
    /// 取り消された呼び手は**取得の終わりを待たずに**戻る（控えが無ければ unreachable）
    func testCancellingOneCallerDoesNotStopTheOthers() async throws {
        let gate = Gate()
        let gallery = service(gate)
        let first = Task { try await gallery.fetchPhotos() }
        await gate.untilWaiting(1)
        let second = Task { try await gallery.fetchPhotos() }
        try await settle()

        first.cancel()
        // 門を閉じたまま、取り消した側が戻るのを待つ（上限2秒。壊れても試験ごと固まらない）
        let returned = Returned()
        Task { _ = await first.result; await returned.mark() }
        let deadline = Date().addingTimeInterval(2)
        while await !returned.value, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let firstReturned = await returned.value
        XCTAssertTrue(firstReturned, "取り消した呼び手が、共有の取得の終わりまで待たされている")

        await gate.open()
        do {
            _ = try await first.value
            XCTFail("控えが無いのに一覧が返った")
        } catch {
            guard case APIError.unreachable = error else {
                return XCTFail("取り消された呼び手の戻り方が変わった: \(error)")
            }
        }
        let photos = try await second.value
        XCTAssertEqual(photos.map(\.id), ["a", "b"], "取り消しが、ほかの呼び手の取得まで止めた")
        let arrived = await gate.arrived
        XCTAssertEqual(arrived, 1)
        XCTAssertEqual(StubProtocol.requestCount, 1)
    }

    /// 引き下げ更新は、引く前に始まった取得に相乗りしない
    func testForceDoesNotJoinAnEarlierFetch() async throws {
        let gate = Gate()
        let gallery = service(gate)
        let first = Task { try await gallery.fetchPhotos() }
        await gate.untilWaiting(1)
        let forced = Task { try await gallery.fetchPhotos(force: true) }
        await gate.untilWaiting(2)
        await gate.open()
        _ = try await first.value
        _ = try await forced.value
        XCTAssertEqual(StubProtocol.requestCount, 2)
    }

    private actor Returned {
        private(set) var value = false
        func mark() { value = true }
    }
}
