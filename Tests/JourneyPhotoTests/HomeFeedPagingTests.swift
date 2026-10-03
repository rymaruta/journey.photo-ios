import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// ホームの「新着」を `GET /feed` のページで読む（2026-10-03）。
///
/// 契約: 続きの有無は **`nextCursor` だけ**で決める（`items` が少なくても・空でも、
/// 札があれば続きがある）。`/feed` が使えない回（道が無い 404・500・圏外）は
/// `photos.json` の並びに戻り、ホームを空にしない。
@MainActor
final class HomeFeedPagingTests: XCTestCase {

    private var session: URLSession!

    private func prepare() {
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

    /// 全件（`photos.json`）の中身。ページの写真（p…）と見分けるため s… にする
    private let snapshotBody = """
    [{"id":"s1","src":"https://x/s1.jpg","createdAt":"2026-01-01T00:00:00Z"},
     {"id":"s2","src":"https://x/s2.jpg","createdAt":"2026-02-01T00:00:00Z"}]
    """

    private func photo(_ id: String) -> String {
        // 新しい順に並ぶよう、番号が小さいほど新しい日付にする
        let day = 28 - (Int(id.dropFirst()) ?? 0)
        return #"{"id":"\#(id)","src":"https://x/\#(id).jpg","createdAt":"2026-09-\#(String(format: "%02d", day))T00:00:00Z"}"#
    }

    private func page(_ ids: [String], next: String?) -> String {
        let items = ids.map(photo).joined(separator: ",")
        let cursor = next.map { "\"\($0)\"" } ?? "null"
        return #"{"items":[\#(items)],"nextCursor":\#(cursor)}"#
    }

    /// 「新着」を選んだホーム。`gates` を渡すと `/feed` の要求を手前で止められる
    private func makeModel(gates: PathGates? = nil,
                           snapshot: PhotoSnapshotStore = PhotoSnapshotStore(fileName: UUID().uuidString)) -> GalleryViewModel {
        let gallery = PublicGalleryService(
            url: URL(string: "https://site.example.test/app/data/photos.json")!,
            session: session,
            snapshot: snapshot
        )
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: nil),
                            session: session,
                            beforeRequest: gates.map { gates in { (request: URLRequest) async in await gates.wait(for: request) } })
        let model = GalleryViewModel(gallery: gallery, feed: PublicFeedService(api: api))
        model.select(feed: .latest, viewerId: nil)
        return model
    }

    private func shown(_ model: GalleryViewModel, file: StaticString = #filePath, line: UInt = #line) -> [String] {
        guard case .loaded(let photos) = model.state else {
            XCTFail("一覧が出ていない: \(model.state)", file: file, line: line)
            return []
        }
        return photos.map(\.id)
    }

    /// `/feed` に渡した札（1ページ目は nil）を、頼んだ順に
    private var feedCursors: [String?] {
        StubProtocol.allRequests
            .compactMap(\.url)
            .filter { $0.path.hasSuffix("/feed") }
            .map { url in
                URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "cursor" }?.value
            }
    }

    // MARK: - ページ送り

    /// 最初の1ページで出し、下まで送ったら次のページを足す。**`items` が `limit` より
    /// 少なくても札があれば続きを読む**（2枚のページでも止まらない）
    func testFirstPageShowsAndScrollingAppendsTheNextPage() async {
        prepare()
        StubProtocol.respond(path: "/feed?cursor=c1", status: 200, body: page(["p3", "p4"], next: nil))
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p1", "p2"], next: "c1"))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let model = makeModel()

        await model.load()
        XCTAssertEqual(shown(model), ["p1", "p2"], "1ページ目で出していない（photos.json の並びのまま）")
        XCTAssertTrue(model.usesPagedFeed)
        XCTAssertTrue(model.hasMorePages, "2枚しか来なかったページで、札があるのに止まった")
        let request = StubProtocol.allRequests.first { $0.url?.path.hasSuffix("/feed") == true }
        XCTAssertNil(request?.value(forHTTPHeaderField: "Authorization"), "認証なしの口に鍵を付けた")
        XCTAssertTrue(request?.url?.query?.contains("limit=30") == true)

        await model.loadNextPage()
        XCTAssertEqual(shown(model), ["p1", "p2", "p3", "p4"])
        XCTAssertEqual(feedCursors, [nil, "c1"], "前の答えの札をそのまま渡していない")
    }

    /// **`nextCursor` が null なら止まる。** 目印も出さず、頼まれても叩かない
    func testStopsAtTheLastPage() async {
        prepare()
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p1", "p2"], next: nil))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let model = makeModel()

        await model.load()
        XCTAssertEqual(shown(model), ["p1", "p2"])
        XCTAssertFalse(model.hasMorePages, "最後のページなのに続きの目印を出す")
        await model.loadNextPage()
        await model.loadNextPage()
        XCTAssertEqual(feedCursors.count, 1, "最後のページの後も /feed を叩いた")
    }

    /// **`items` が空で `nextCursor` だけのページでも続きを読む**（空を「終わり」と取らない）
    func testEmptyPageWithCursorKeepsReading() async {
        prepare()
        StubProtocol.respond(path: "/feed?cursor=c1", status: 200, body: page(["p1"], next: "c2"))
        StubProtocol.respond(path: "/feed?cursor=c2", status: 200, body: page(["p2"], next: nil))
        StubProtocol.respond(path: "/feed", status: 200, body: page([], next: "c1"))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let model = makeModel()

        await model.load()
        XCTAssertEqual(shown(model), ["p1"], "空のページで止まり、0枚のホームになった")
        XCTAssertTrue(model.hasMorePages)
        await model.loadNextPage()
        XCTAssertEqual(shown(model), ["p1", "p2"])
        XCTAssertFalse(model.hasMorePages)
        XCTAssertEqual(feedCursors, [nil, "c1", "c2"])
    }

    /// ページの境目で同じ写真が2度来ても1枚（id で除く）
    func testDuplicatesAcrossPagesAreDroppedById() async {
        prepare()
        StubProtocol.respond(path: "/feed?cursor=c1", status: 200, body: page(["p2", "p3"], next: nil))
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p1", "p2"], next: "c1"))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let model = makeModel()

        await model.load()
        await model.loadNextPage()
        XCTAssertEqual(shown(model), ["p1", "p2", "p3"], "境目の写真が2枚並んだ")
    }

    /// **読んでいる最中に頼まれても、同じ続きを2度頼まない**
    func testDoesNotRequestTheSamePageTwiceWhileLoading() async {
        prepare()
        StubProtocol.respond(path: "/feed?cursor=c1", status: 200, body: page(["p3"], next: nil))
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p1", "p2"], next: "c1"))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        // 1回目（1ページ目）は通し、2回目（続き）を止める
        let gate = Gate(holds: 1, skip: 1)
        let model = makeModel(gates: PathGates(["/feed": gate]))

        await model.load()
        let first = Task { await model.loadNextPage() }
        await gate.untilWaiting(2)
        XCTAssertTrue(model.isLoadingPage)
        await model.loadNextPage()   // 目印がもう一度出た
        await gate.open()
        await first.value
        XCTAssertEqual(feedCursors.filter { $0 == "c1" }.count, 1, "読んでいる最中に同じ続きをもう一度頼んだ")
        XCTAssertEqual(shown(model), ["p1", "p2", "p3"])
        XCTAssertFalse(model.isLoadingPage)
    }

    // MARK: - 引っぱって更新

    /// 引き下げは**1ページ目から**読み直す（下まで送った続きを持ち越さない）
    func testPullToRefreshStartsOverFromTheFirstPage() async {
        prepare()
        StubProtocol.respond(path: "/feed?cursor=c1", status: 200, body: page(["p3", "p4"], next: nil))
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p1", "p2"], next: "c1"))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let model = makeModel()
        await model.load()
        await model.loadNextPage()
        XCTAssertEqual(shown(model), ["p1", "p2", "p3", "p4"])

        // 新しい写真 p0 が載った
        StubProtocol.reset()
        StubProtocol.respond(path: "/feed?cursor=c9", status: 200, body: page(["p2", "p3"], next: nil))
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p0", "p1"], next: "c9"))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        await model.load(force: true)
        XCTAssertEqual(shown(model), ["p0", "p1"], "引き下げで1ページ目から読み直していない")
        XCTAssertEqual(feedCursors, [nil])
        XCTAssertTrue(model.hasMorePages)
        await model.loadNextPage()
        XCTAssertEqual(feedCursors, [nil, "c9"], "引き下げの後に、前の札で続きを頼んだ")
        XCTAssertEqual(shown(model), ["p0", "p1", "p2", "p3"])
    }

    /// 引き下げの前に頼んだ続きが遅れて着いても、読み直した一覧に足さない
    func testStaleNextPageIsDroppedAfterRefresh() async {
        prepare()
        StubProtocol.respond(path: "/feed?cursor=c1", status: 200, body: page(["p8", "p9"], next: nil))
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p1", "p2"], next: "c1"))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let gate = Gate(holds: 1, skip: 1)
        let model = makeModel(gates: PathGates(["/feed": gate]))
        await model.load()

        let stale = Task { await model.loadNextPage() }
        await gate.untilWaiting(2)
        // 続きが止まっていない（壊れた）回は、引き下げが止まる側に入って試験ごと固まる。先に開けて落とす
        guard await gate.arrived >= 2 else {
            await gate.open()
            await stale.value
            return
        }
        await model.load(force: true)   // 3回目の /feed は止めずに通る
        await gate.open()
        await stale.value
        XCTAssertEqual(shown(model), ["p1", "p2"], "引き下げの前に頼んだ続きを、読み直した一覧に足した")
        XCTAssertTrue(model.hasMorePages)
    }

    // MARK: - 戻り道（photos.json）

    /// 道が無い 404（API Gateway の `{"message":"Not Found"}`）なら photos.json の並びで出す
    func testMissingRouteFallsBackToTheSnapshot() async {
        prepare()
        StubProtocol.respond(path: "/feed", status: 404, body: #"{"message":"Not Found"}"#)
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let model = makeModel()

        await model.load()
        XCTAssertEqual(shown(model), ["s2", "s1"], "/feed が無いのに photos.json に戻らない")
        XCTAssertFalse(model.usesPagedFeed)
        XCTAssertFalse(model.hasMorePages)
        // 戻っている間は、読み直しのたびに /feed を叩き直さない（次の引き下げで試す）
        await model.load()
        XCTAssertEqual(feedCursors.count, 1)
    }

    /// 500（本番に索引が無いあいだ）も photos.json に戻る
    func testServerErrorFallsBackToTheSnapshot() async {
        prepare()
        StubProtocol.respond(path: "/feed", status: 500, body: #"{"error":"取得に失敗しました"}"#)
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let model = makeModel()

        await model.load()
        XCTAssertEqual(shown(model), ["s2", "s1"], "500 のときにホームが空・失敗になった")
        XCTAssertFalse(model.usesPagedFeed)
    }

    /// 圏外。/feed も photos.json も届かなくても、端末の控えでホームを出す
    func testOfflineFallsBackToTheSavedSnapshot() async {
        prepare()
        let snapshot = PhotoSnapshotStore(fileName: UUID().uuidString)
        snapshot.save(Data(snapshotBody.utf8))
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        let model = makeModel(snapshot: snapshot)

        await model.load()
        XCTAssertEqual(shown(model), ["s2", "s1"], "圏外でホームが空になった")
        XCTAssertFalse(model.usesPagedFeed)
    }

    /// 戻った後の引き下げで、/feed が直っていればページ読みに戻る
    func testRefreshRetriesTheFeedAfterFallingBack() async {
        prepare()
        StubProtocol.respond(path: "/feed", status: 500, body: #"{"error":"取得に失敗しました"}"#)
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let model = makeModel()
        await model.load()
        XCTAssertFalse(model.usesPagedFeed)

        StubProtocol.reset()
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p1"], next: nil))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        await model.load(force: true)
        XCTAssertEqual(shown(model), ["p1"])
        XCTAssertTrue(model.usesPagedFeed)
    }

    // MARK: - 全件のまま残す札（2026-10-03 判断）

    /// おすすめ・絞り込みは全件（photos.json）の並び。ページだけで並べると全体の答えと食い違う
    func testRecommendedAndFiltersKeepUsingTheSnapshot() async {
        prepare()
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p1"], next: "c1"))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let model = makeModel()
        await model.load()
        XCTAssertEqual(shown(model), ["p1"])

        model.select(feed: .recommended, viewerId: nil)
        XCTAssertEqual(Set(shown(model)), ["s1", "s2"], "おすすめがページの並びになった")
        XCTAssertFalse(model.hasMorePages)

        model.select(feed: .latest, viewerId: nil)
        XCTAssertEqual(shown(model), ["p1"])
        model.query = "s"
        XCTAssertFalse(model.usesPagedFeed, "検索中にページの並びを使った")
        model.query = ""
        XCTAssertEqual(shown(model), ["p1"])
    }

    /// 限定公開は**読んだ範囲に入るものだけ**混ぜる。まだ読んでいない古い時期の
    /// 限定写真を1ページ目の末尾に並べない（次のページで並びが入れ替わる）
    func testRestrictedPhotosMergeOnlyWithinTheLoadedRange() async {
        func photo(_ id: String, _ date: String) -> Photo {
            try! JSONDecoder.api.decode(Photo.self, from: Data(#"{"id":"\#(id)","src":"https://x/\#(id).jpg","createdAt":"\#(date)"}"#.utf8))
        }
        let loaded = [photo("p1", "2026-09-20"), photo("p2", "2026-09-10")]
        let restricted = [photo("r-new", "2026-09-15"), photo("r-old", "2026-08-01")]

        let partial = RestrictedFeed.mergeLoaded(publicPhotos: loaded, restricted: restricted, reachedEnd: false)
        XCTAssertEqual(partial.map(\.id), ["p1", "r-new", "p2"])
        let complete = RestrictedFeed.mergeLoaded(publicPhotos: loaded, restricted: restricted, reachedEnd: true)
        XCTAssertEqual(complete.map(\.id), ["p1", "r-new", "p2", "r-old"])
        XCTAssertTrue(RestrictedFeed.mergeLoaded(publicPhotos: [], restricted: restricted, reachedEnd: false).isEmpty)
    }

    /// 答えの形。`items` の読めない行は落として続ける・`nextCursor` が無ければ最後
    func testFeedPageDecoding() async throws {
        let page = try JSONDecoder.api.decode(FeedPage.self, from: Data(#"{"items":[{"id":"a","src":"https://x/a.jpg"},{"bad":1}],"nextCursor":"abc"}"#.utf8))
        XCTAssertEqual(page.items.map(\.id), ["a"])
        XCTAssertEqual(page.nextCursor, "abc")
        let last = try JSONDecoder.api.decode(FeedPage.self, from: Data(#"{"items":[],"nextCursor":null}"#.utf8))
        XCTAssertNil(last.nextCursor)
        XCTAssertThrowsError(try JSONDecoder.api.decode(FeedPage.self, from: Data("[]".utf8)))
    }
}
