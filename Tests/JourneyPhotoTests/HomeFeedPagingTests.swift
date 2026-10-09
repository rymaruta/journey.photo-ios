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

    private func photo(_ id: String, user: String? = nil) -> String {
        // 新しい順に並ぶよう、番号が小さいほど新しい日付にする
        let day = 28 - (Int(id.dropFirst()) ?? 0)
        let owner = user.map { #","userId":"\#($0)""# } ?? ""
        return #"{"id":"\#(id)","src":"https://x/\#(id).jpg","createdAt":"2026-09-\#(String(format: "%02d", day))T00:00:00Z"\#(owner)}"#
    }

    private func page(_ ids: [String], next: String?) -> String {
        let items = ids.map { photo($0) }.joined(separator: ",")
        let cursor = next.map { "\"\($0)\"" } ?? "null"
        return #"{"items":[\#(items)],"nextCursor":\#(cursor)}"#
    }

    /// 最後に作ったホームの公開一覧（ブロック・限定公開の口を入れるため）
    private var lastGallery: PublicGalleryService!

    /// 「新着」を選んだホーム。`gates` を渡すと `/feed` の要求を手前で止められる
    private func makeModel(gates: PathGates? = nil, startsOnLatest: Bool = true,
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
        lastGallery = gallery
        let model = GalleryViewModel(gallery: gallery, feed: PublicFeedService(api: api))
        if startsOnLatest { model.select(feed: .latest, viewerId: nil) }
        return model
    }

    /// 条件が立つまで待つ。**上限（既定2秒）で false**（壊れた回に試験ごと固まらない）
    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return true
    }

    /// 1ページ目の読み込み。**門で止まって終わらない（1ページ目を2度読む壊れ方）回は、
    /// 門を開けて落とす**——開けないと試験ごと固まる
    private func loadWithoutHanging(_ model: GalleryViewModel, opening gate: Gate,
                                    file: StaticString = #filePath, line: UInt = #line) async {
        var finished = false
        let loading = Task { await model.load(); finished = true }
        if !(await waitUntil { finished }) {
            XCTFail("1ページ目の読み込みが終わらない（/feed を2度読んで門で止まった）", file: file, line: line)
            await gate.open()
        }
        await loading.value
    }

    private func isShowing(_ model: GalleryViewModel, _ ids: [String]) -> Bool {
        if case .loaded(let photos) = model.state { return photos.map(\.id) == ids }
        return false
    }

    private func decodePhoto(_ json: String) -> Photo {
        try! JSONDecoder.api.decode(Photo.self, from: Data(json.utf8))
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

    /// 🔴 2026-10-09: **ページの境目をまたぐ複数枚の投稿を、前半だけの束で出さない。**
    /// 続きが届くまで末尾の束を出さず、届いたらそろった束で出す
    /// （以前は前半だけの束が出て、続きが届くと表紙と枚数が変わり、先に開くと一部しか送れなかった）
    func testPostStraddlingThePageBoundaryWaitsForTheNextPage() async {
        prepare()
        func grouped(_ id: String) -> String {
            photo(id, user: "u1").replacingOccurrences(of: #""userId""#, with: #""groupId":"post1","userId""#)
        }
        StubProtocol.respond(path: "/feed?cursor=c1", status: 200,
                             body: #"{"items":[\#(grouped("p3")),\#(photo("p4"))],"nextCursor":null}"#)
        StubProtocol.respond(path: "/feed", status: 200,
                             body: #"{"items":[\#(photo("p1")),\#(grouped("p2"))],"nextCursor":"c1"}"#)
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let model = makeModel()

        await model.load()
        XCTAssertEqual(shown(model), ["p1"], "ページの境目をまたぐ投稿の前半だけを出した")
        XCTAssertTrue(model.hasMorePages)

        await model.loadNextPage()
        let photos: [Photo] = { if case .loaded(let p) = model.state { return p } else { return [] } }()
        XCTAssertEqual(Set(photos.map(\.id)), ["p1", "p2", "p3", "p4"])
        let post = PhotoGroups.group(photos).first { $0.isMultiple }
        XCTAssertEqual(post.map { Set($0.photos.map(\.id)) }, ["p2", "p3"], "続きが届いても束がそろわない")
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

        await loadWithoutHanging(model, opening: gate)
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
        await loadWithoutHanging(model, opening: gate)

        let stale = Task { await model.loadNextPage() }
        await gate.untilWaiting(2)
        // 続きが止まっていない（壊れた）回は、引き下げが止まる側に入って試験ごと固まる。先に開けて落とす
        guard await gate.arrived >= 2 else {
            await gate.open()
            await stale.value
            return
        }
        // 読み直した1ページ目は前と違う（p0 が載った）。止めていた続き（c1 → p8・p9）は道を
        // 選ぶのが門を開けた後なので、同じ答えを返すよう登録し直す
        StubProtocol.reset()
        StubProtocol.respond(path: "/feed?cursor=c1", status: 200, body: page(["p8", "p9"], next: nil))
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p0"], next: "c5"))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        await model.load(force: true)   // 3回目の /feed は止めずに通る
        XCTAssertEqual(shown(model), ["p0"], "前提: 引き下げの1ページ目が出ていない")
        await gate.open()
        await stale.value
        XCTAssertEqual(shown(model), ["p0"], "引き下げの前に頼んだ続きを、読み直した一覧に足した")
        XCTAssertTrue(model.hasMorePages)
        // 続きの札も読み直した回のもの
        await model.loadNextPage()
        XCTAssertEqual(feedCursors.last ?? nil, "c5", "引き下げの前の札が残っている")
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

    // MARK: - レビュー（2026-10-03）

    /// 🔴 **おすすめでは `/feed` を読まない・待たない。** `/feed` が遅くても、おすすめは
    /// photos.json が着いた時点で出る。「新着」を選んだら初めて1ページ目を読む
    func testRecommendedNeitherReadsNorWaitsForTheFeed() async {
        prepare()
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p1"], next: nil))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let gate = Gate(holds: 1)
        let model = makeModel(gates: PathGates(["/feed": gate]), startsOnLatest: false)
        XCTAssertEqual(model.feed, .recommended)

        var finished = false
        let loading = Task { await model.load(); finished = true }
        let done = await waitUntil { finished }
        XCTAssertTrue(done, "おすすめの読み込みが /feed を待っている")
        XCTAssertEqual(Set(shown(model)), ["s1", "s2"])
        let arrived = await gate.arrived
        XCTAssertEqual(arrived, 0, "おすすめで /feed を読んだ")
        await gate.open()
        await loading.value

        // 「新着」を選ぶと読む
        model.select(feed: .latest, viewerId: nil)
        await model.pagesTask?.value
        XCTAssertEqual(shown(model), ["p1"], "「新着」を選んでも1ページ目を読まない")
        XCTAssertEqual(feedCursors, [nil])
    }

    /// 「新着」でも全件の結果はその場で書く（1ページ目を待たない）。1ページ目が着いたら差し替える
    func testLatestWritesTheSnapshotWithoutWaitingForTheFirstPage() async {
        prepare()
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p1", "p2"], next: nil))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let gate = Gate(holds: 1)
        let model = makeModel(gates: PathGates(["/feed": gate]))

        let loading = Task { await model.load() }
        await gate.untilWaiting(1)
        let wrote = await waitUntil { self.isShowing(model, ["s2", "s1"]) }
        XCTAssertTrue(wrote, "1ページ目を待つ間、全件の結果を書いていない: \(model.state)")
        await gate.open()
        await loading.value
        await model.pagesTask?.value
        XCTAssertEqual(shown(model), ["p1", "p2"])
        // 札を選んだ回の読み込みと起動の読み込みは、同じ1ページ目を使い回す
        XCTAssertEqual(feedCursors, [nil], "1ページ目を2度読んだ")
    }

    /// 読み込みが重なっても `/feed` の1ページ目は1回（読んでいる最中の要求を使い回す）
    func testOverlappingLoadsShareTheFirstPage() async {
        prepare()
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p1", "p2"], next: "c1"))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let gate = Gate(holds: 1)
        let model = makeModel(gates: PathGates(["/feed": gate]))
        let first = Task { await model.load() }
        let second = Task { await model.load() }
        await gate.untilWaiting(1)
        // もう1本が着く隙を与えてから開ける
        _ = await waitUntil(timeout: 0.2) { false }
        await gate.open()
        await first.value
        await second.value
        await model.pagesTask?.value
        XCTAssertEqual(feedCursors, [nil], "重なった読み込みで /feed の1ページ目を2度読んだ")
        XCTAssertEqual(shown(model), ["p1", "p2"])
    }

    /// 全件を読んでいる最中に「新着」を選んでも、`/feed/restricted` は全件の回の1回だけ。
    /// 1ページ目は手元の控えで先に出し、全件が読み終えたら限定公開を重ね直す
    func testFirstPageDuringASnapshotLoadDoesNotReadRestrictedAgain() async {
        prepare()
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p1", "p2"], next: nil))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let restrictedGate = Gate(holds: 1)
        let model = makeModel(startsOnLatest: false)
        let limited = decodePhoto(#"{"id":"r1","src":"https://x/r.jpg","createdAt":"2026-09-26T12:00:00Z","audience":"followers"}"#)
        await lastGallery.setRestrictedLoader {
            await restrictedGate.wait()
            return [limited]
        }
        let loading = Task { await model.load() }
        await restrictedGate.untilWaiting(1)   // 全件の回が限定公開を読んでいる最中
        model.select(feed: .latest, viewerId: nil)
        await model.pagesTask?.value
        XCTAssertEqual(shown(model), ["p1", "p2"], "限定公開を待つ間、1ページ目が出ない")
        await restrictedGate.open()
        await loading.value
        let reads = await restrictedGate.arrived
        XCTAssertEqual(reads, 1, "/feed/restricted を2度読んだ")
        XCTAssertEqual(shown(model), ["p1", "r1", "p2"], "全件の回のあと限定公開を重ね直していない")
    }

    /// 書くかどうかの判定（純関数）。画面に出ていない間にページの並びへ足すと詳細が閉じる
    func testPageWriteWaitsWhileTheDetailIsOpen() async {
        XCTAssertEqual(GalleryViewModel.pageWrite(isOnScreen: true, showsPages: true), .now)
        XCTAssertEqual(GalleryViewModel.pageWrite(isOnScreen: false, showsPages: true), .whenVisible)
        XCTAssertEqual(GalleryViewModel.pageWrite(isOnScreen: false, showsPages: false), .now)
        XCTAssertEqual(GalleryViewModel.pageWrite(isOnScreen: true, showsPages: false), .now)
    }

    /// 詳細を開いている間に届いた続きは足さず、戻ってから足す
    func testNextPageArrivingWhileAwayIsAppliedOnReturn() async {
        prepare()
        StubProtocol.respond(path: "/feed?cursor=c1", status: 200, body: page(["p3", "p4"], next: "c2"))
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p1", "p2"], next: "c1"))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let model = makeModel()
        await model.load()

        model.leaveScreen()
        await model.loadNextPage()
        XCTAssertEqual(shown(model), ["p1", "p2"], "詳細を開いている間に続きを足した（詳細が閉じる）")
        await model.loadNextPage()   // 足していない続きがある間は次を頼まない
        XCTAssertEqual(feedCursors, [nil, "c1"])
        // 他の書き込み（検索を打って消した）でも、まだ足さない
        model.query = ""
        XCTAssertEqual(shown(model), ["p1", "p2"])

        model.markOnScreen()
        await model.applyPendingPages()
        XCTAssertEqual(shown(model), ["p1", "p2", "p3", "p4"], "戻っても続きを足さない")
        XCTAssertTrue(model.hasMorePages)
    }

    /// 🔴 続きの札を断られた（400）ら1ページ目から読み直す（同じ札の再試行は永遠に 400）
    func testRejectedCursorStartsOverFromTheFirstPage() async {
        prepare()
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p1", "p2"], next: "c1"))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let model = makeModel()
        await model.load()

        StubProtocol.reset()
        StubProtocol.respond(path: "/feed?cursor=c1", status: 400, body: #"{"error":"cursor が不正です"}"#)
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p0", "p1"], next: "c2"))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        await model.loadNextPage()
        XCTAssertEqual(feedCursors, ["c1", nil], "400 のあとに1ページ目から読み直していない")
        XCTAssertEqual(shown(model), ["p0", "p1"])
        XCTAssertFalse(model.pageFailed, "読み直せたのに「もう一度試す」のまま")
        XCTAssertTrue(model.hasMorePages)
    }

    /// ページの並びにもブロックを掛ける（`presentFeed` の `visible`）
    func testPagedFeedDropsBlockedUsers() async {
        prepare()
        StubProtocol.respond(path: "/feed", status: 200,
                             body: #"{"items":[\#(photo("p1", user: "u1")),\#(photo("p2", user: "u2"))],"nextCursor":null}"#)
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let model = makeModel()
        var hiding = ModerationSnapshot()
        hiding.blocked = ["u2"]
        await lastGallery.setHidden(hiding)
        await model.load()
        XCTAssertEqual(shown(model), ["p1"], "ブロックした人の写真がページの並びに出た")
    }

    /// 人が替わったら読んだページを捨て、次の読み込みで1ページ目から読み直す
    func testViewerSwitchDropsPagesAndRereadsTheFirstPage() async {
        prepare()
        StubProtocol.respond(path: "/feed?cursor=c1", status: 200, body: page(["p3"], next: nil))
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p1", "p2"], next: "c1"))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let model = makeModel()
        await model.switchViewer(from: nil, to: "a")
        await model.loadNextPage()
        XCTAssertEqual(shown(model), ["p1", "p2", "p3"])

        await model.switchViewer(from: "a", to: "b")
        XCTAssertFalse(model.hasMorePages)
        XCTAssertEqual(model.loadedPageCount, 0, "前の人のページを持ったまま")
        StubProtocol.reset()
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p1", "p2"], next: "c1"))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        await model.load()
        XCTAssertEqual(feedCursors, [nil], "人が替わった後に1ページ目から読み直していない")
        XCTAssertEqual(shown(model), ["p1", "p2"], "前の人の続き（p3）が残っている")
    }

    /// 空のページが続いても、1回の頼みで読むのは上限（5回）まで
    func testEmptyPagesStopAtTheHopLimit() async {
        prepare()
        XCTAssertEqual(GalleryViewModel.maxEmptyPageHops, 5)
        StubProtocol.respond(path: "/feed", status: 200, body: page([], next: "c1"))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let model = makeModel()
        await model.load()
        XCTAssertEqual(feedCursors.count, 5, "空のページの読み足しが上限で止まらない")
        XCTAssertTrue(model.hasMorePages)
        await model.loadNextPage()
        XCTAssertEqual(feedCursors.count, 10)
    }

    /// 限定公開は、ページ読みの経路でも読んだ範囲だけ混ぜ、最後まで読んだら全部混ぜる
    func testRestrictedPhotosFollowTheLoadedRangeThroughPaging() async {
        prepare()
        StubProtocol.respond(path: "/feed?cursor=c1", status: 200, body: page(["p3"], next: nil))
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p1", "p2"], next: "c1"))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let model = makeModel()
        let old = decodePhoto(#"{"id":"r-old","src":"https://x/r.jpg","createdAt":"2026-08-01T00:00:00Z","audience":"followers"}"#)
        await lastGallery.setRestrictedLoader { [old] }
        await model.load()
        XCTAssertEqual(shown(model), ["p1", "p2"], "まだ読んでいない時期の限定写真を混ぜた")
        await model.loadNextPage()
        XCTAssertEqual(shown(model), ["p1", "p2", "p3", "r-old"], "最後まで読んだのに限定写真を混ぜない")
    }

    // MARK: - 再レビュー（2026-10-03）

    /// 印は同期で立てる。**戻ってすぐ詳細を開き直したら、遅れて走った足し込みは何もしない**
    /// （Task の中で印を立てていた頃は、`leaveScreen` の後に立って逆転し、詳細の裏で続きを足した）
    func testOnScreenMarkIsSynchronousAndPendingApplyRespectsALaterLeave() async {
        prepare()
        StubProtocol.respond(path: "/feed?cursor=c1", status: 200, body: page(["p3", "p4"], next: nil))
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p1", "p2"], next: "c1"))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let model = makeModel()
        await model.load()
        model.leaveScreen()
        await model.loadNextPage()
        XCTAssertEqual(shown(model), ["p1", "p2"])

        // 戻った（onAppear）→ 足し込みが走る前にまた詳細を開いた（onDisappear）
        model.markOnScreen()
        XCTAssertTrue(model.isOnScreen, "印が同期で立っていない")
        model.leaveScreen()
        await model.applyPendingPages()
        XCTAssertFalse(model.isOnScreen, "遅れて走った足し込みが印を立て直した")
        XCTAssertEqual(shown(model), ["p1", "p2"], "詳細を開いている間に続きを足した")

        model.markOnScreen()
        await model.applyPendingPages()
        XCTAssertEqual(shown(model), ["p1", "p2", "p3", "p4"])
    }

    /// 時計を差し替えたホーム（1ページ目 p1・p2、続きあり）を作って読む
    private func loadedWithClock(_ now: @escaping () -> Date) async -> GalleryViewModel {
        prepare()
        StubProtocol.respond(path: "/feed?cursor=c1", status: 200, body: page(["p3", "p4"], next: nil))
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p1", "p2"], next: "c1"))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
        let model = makeModel()
        model.clock = now
        await model.load()
        XCTAssertEqual(shown(model), ["p1", "p2"])
        return model
    }

    /// 新しい写真 p0 が載った後の /feed
    private func publishNewPhoto() {
        StubProtocol.reset()
        StubProtocol.respond(path: "/feed?cursor=c1", status: 200, body: page(["p2", "p3"], next: nil))
        StubProtocol.respond(path: "/feed", status: 200, body: page(["p0", "p1"], next: "c1"))
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: snapshotBody)
    }

    /// 🔴 おすすめを見ている間に60秒過ぎたら、「新着」に戻ったとき1ページ目を読み直す。60秒以内は読まない
    func testReturningToLatestRereadsAStaleFirstPage() async {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let model = await loadedWithClock { now }
        model.select(feed: .recommended, viewerId: nil)
        publishNewPhoto()

        now += 30
        model.select(feed: .latest, viewerId: nil)
        await model.pagesTask?.value
        XCTAssertEqual(feedCursors, [], "60秒以内なのに読み直した")
        XCTAssertEqual(shown(model), ["p1", "p2"])

        model.select(feed: .recommended, viewerId: nil)
        now += 31
        model.select(feed: .latest, viewerId: nil)
        await model.pagesTask?.value
        XCTAssertEqual(feedCursors, [nil], "古い1ページ目を読み直さない")
        XCTAssertEqual(shown(model), ["p0", "p1"], "「新着」が古いまま")
    }

    /// 詳細から戻った・ブロックの後の読み直し（force なしの load）でも、古ければ読み直す
    func testPlainReloadRereadsAStaleFirstPage() async {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let model = await loadedWithClock { now }
        publishNewPhoto()
        now += 61
        await model.load()
        XCTAssertEqual(feedCursors, [nil], "古い1ページ目のまま読み直しを終えた")
        XCTAssertEqual(shown(model), ["p0", "p1"])
    }

    /// おすすめで引き下げたら、時間に関係なく次の「新着」で読み直す
    func testRefreshOnAnotherFeedMarksTheFirstPageStale() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let model = await loadedWithClock { now }
        model.select(feed: .recommended, viewerId: nil)
        publishNewPhoto()
        await model.load(force: true)
        XCTAssertEqual(feedCursors, [], "おすすめの引き下げで /feed を読んだ")
        model.select(feed: .latest, viewerId: nil)
        await model.pagesTask?.value
        XCTAssertEqual(shown(model), ["p0", "p1"], "おすすめで引き下げた後も「新着」が古いまま")
    }

    /// 下まで送った一覧は、古くても1ページ目に縮めない（引き下げで新しくする）
    func testDeepListIsNotShrunkWhenStale() async {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let model = await loadedWithClock { now }
        await model.loadNextPage()
        XCTAssertEqual(shown(model), ["p1", "p2", "p3", "p4"])
        publishNewPhoto()
        now += 120
        await model.load()
        model.select(feed: .recommended, viewerId: nil)
        model.select(feed: .latest, viewerId: nil)
        await model.pagesTask?.value
        XCTAssertEqual(feedCursors, [], "下まで送った一覧を読み直して縮めた")
        XCTAssertEqual(shown(model), ["p1", "p2", "p3", "p4"])
    }
}
