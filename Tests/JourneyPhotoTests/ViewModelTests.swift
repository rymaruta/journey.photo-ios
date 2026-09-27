import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 画面の頭（ViewModel）を**実際に動かして**確かめる。
///
/// 見た目は Mac でしか確かめられないが、**押したときに何が起きるか**は
/// ここで押さえられる。通信は `URLProtocol` で差し替える。
@MainActor
final class ViewModelTests: XCTestCase {

    private var session: URLSession!

    /// **`setUp` はメインアクタではない。** このクラスは `@MainActor` なので、
    /// 用意は各テストの頭で行う（`setUp` から書くと分離の誤りになる）
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

    private func api(token: String? = "t") -> APIClient {
        APIClient(baseURL: URL(string: "https://api.example.test")!,
                  tokenProvider: StubTokenProvider(token: token),
                  session: session)
    }

    private func gallery(_ body: String) -> PublicGalleryService {
        prepare()
        StubProtocol.respond(status: 200, body: body)
        return PublicGalleryService(
            url: URL(string: "https://site.example.test/app/data/photos.json")!,
            session: session,
            snapshot: PhotoSnapshotStore(fileName: UUID().uuidString)
        )
    }

    private let feed = """
    [{"id":"a","src":"https://x/a.jpg","createdAt":"2026-01-02T00:00:00Z","category":"風景"},
     {"id":"b","src":"https://x/b.jpg","createdAt":"2026-03-04T00:00:00Z","category":"食"},
     {"id":"c","src":"https://x/c.jpg","category":"風景"}]
    """

    // MARK: - ギャラリー

    /// 🔴 **おすすめの横並びは「おすすめ」の札のときだけ。** 全員の写真から作る段なので、
    /// 「フォロー中」ではフォローしていない人の写真が並んでいた（owner の判断 2026-09-27）
    func testFeaturedRowsShowOnlyOnTheRecommendedFeed() async {
        let model = GalleryViewModel(gallery: gallery("""
        [{"id":"f1","src":"https://x/f1.jpg","createdAt":"2026-01-02T00:00:00Z","category":"風景","featured":true,"userId":"u1"},
         {"id":"f2","src":"https://x/f2.jpg","createdAt":"2026-01-03T00:00:00Z","category":"風景","featured":true,"userId":"u1"}]
        """))
        await model.load()
        XCTAssertFalse(model.featured.isEmpty, "前提: おすすめの段が作れていない")
        model.select(feed: .following, viewerId: "me")
        XCTAssertTrue(model.featured.isEmpty, "フォロー中で全員のおすすめを出している")
        model.select(feed: .latest, viewerId: "me")
        XCTAssertTrue(model.featured.isEmpty, "新着でおすすめの段を出している")
        model.select(feed: .recommended, viewerId: "me")
        XCTAssertFalse(model.featured.isEmpty, "おすすめに戻しても段が出ない")
    }

    /// 新しい順。**`createdAt` が無い写真は末尾**（落とさない）。
    func testGalleryOrdersNewestFirstAndKeepsUndated() async {
        let model = GalleryViewModel(gallery: gallery(feed))
        await model.load()
        guard case .loaded(let photos) = model.state else {
            return XCTFail("読み込めていない: \(model.state)")
        }
        XCTAssertEqual(photos.map(\.id), ["b", "a", "c"])
    }

    /// 🔴 **おすすめは owner が選んだ写真（featured）を先頭に**——読み込み直後も、
    /// 並びが同じまま「フォロー中」からおすすめへ戻ったとき（ログアウト）も
    func testRecommendedPutsFeaturedFirst() async {
        let body = """
        [{"id":"pop","src":"https://x/p.jpg","createdAt":"2026-03-04T00:00:00Z","likes":50},
         {"id":"picked","src":"https://x/k.jpg","createdAt":"2026-01-02T00:00:00Z","likes":1,"featured":true}]
        """
        let model = GalleryViewModel(gallery: gallery(body))
        await model.load()
        guard case .loaded(let first) = model.state else { return XCTFail("読み込めていない") }
        XCTAssertEqual(first.map(\.id), ["picked", "pop"], "読み込み直後に featured が先頭に来ない")

        model.select(feed: .following, viewerId: "me")
        model.select(sort: .popular)
        model.use(viewerId: nil, following: [])   // ログアウト → おすすめへ戻る
        guard case .loaded(let back) = model.state else { return XCTFail("状態が違う") }
        XCTAssertEqual(back.map(\.id), ["picked", "pop"], "おすすめに戻ったのに featured が先頭に来ない")
    }

    /// カテゴリの絞り込みは**押し直すと外れる**（Web の FilterBar と同じ）。
    func testGalleryCategoryFilterToggles() async {
        let model = GalleryViewModel(gallery: gallery(feed))
        await model.load()

        model.select(category: "風景")
        guard case .loaded(let filtered) = model.state else { return XCTFail("状態が違う") }
        XCTAssertEqual(filtered.map(\.id), ["a", "c"])

        model.select(category: nil)
        guard case .loaded(let all) = model.state else { return XCTFail("状態が違う") }
        XCTAssertEqual(all.count, 3)
    }

    /// 絞り込みに出すのは**実際にある種類だけ**（押しても空になるボタンを置かない）。
    /// 並びは符号位置の順で**固定**——件数順にすると日によって場所が変わり、
    /// 押す場所を覚えられない。
    func testGalleryCategoriesComeFromTheData() async {
        let model = GalleryViewModel(gallery: gallery(feed))
        await model.load()
        XCTAssertEqual(model.categories, ["風景", "食"])
    }

    /// 🔴 **取り消された読み直しを失敗の帯にしない（L-13）。** 戻ると `.task` が
    /// 走り直し、読み終わる前に次の写真を開くと取り消される。帯はフィードごと
    /// 差し替えるので、開いたばかりの詳細が閉じていた。控えの無い端末で起きる
    func testGalleryReloadCancelledKeepsTheFeed() async {
        prepare()
        let name = UUID().uuidString
        StubProtocol.respond(status: 200, body: feed)
        let model = GalleryViewModel(gallery: PublicGalleryService(
            url: URL(string: "https://site.example.test/app/data/photos.json")!,
            session: session,
            snapshot: PhotoSnapshotStore(fileName: name)
        ))
        await model.load()
        guard case .loaded(let first) = model.state else { return XCTFail("最初の読み込みが通っていない") }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: caches.appendingPathComponent(name))

        StubProtocol.fail(with: URLError(.cancelled))
        let task = Task { await model.load(force: true) }
        task.cancel()
        await task.value
        guard case .loaded(let after) = model.state else { return XCTFail("取り消しを失敗の帯にしている") }
        XCTAssertEqual(after.map(\.id), first.map(\.id))
    }

    /// 🔴 **人のページ: 取り消された読み直しを失敗の帯にしない（H-5）。** 戻って走り直した
    /// `.task` が、次の写真・ハイライトを開いて取り消されると、`publicProfile` が
    /// 「通信できません」を投げ、格子が帯に差し替わって開いたばかりの詳細が閉じていた
    func testProfileReloadCancelledKeepsWhatWasShown() async {
        prepare()
        StubProtocol.respond(path: "/profile/u1", status: 200, body: #"{"userId":"u1","displayName":"U"}"#)
        StubProtocol.respond(path: "/app/data/photos.json", status: 200,
                             body: #"[{"id":"p1","src":"https://x/p1.jpg","userId":"u1"}]"#)
        let env = AppEnvironment(tokenProvider: StubTokenProvider(token: "t"),
                                 gallery: PublicGalleryService(
                                    url: URL(string: "https://site.example.test/app/data/photos.json")!,
                                    session: session,
                                    snapshot: PhotoSnapshotStore(fileName: UUID().uuidString)),
                                 api: api())
        let model = UserProfileViewModel()
        await model.load(userId: "u1", environment: env, viewerId: nil)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.photos.map(\.id), ["p1"])

        StubProtocol.reset()
        StubProtocol.fail(with: URLError(.cancelled))
        let task = Task { await model.load(userId: "u1", environment: env, viewerId: nil) }
        task.cancel()
        await task.value
        XCTAssertNil(model.errorMessage, "取り消しを失敗の帯にしている")
        XCTAssertEqual(model.photos.map(\.id), ["p1"])
        XCTAssertEqual(model.photoCount, .loaded(1))
    }

    /// **まだ何も出していない初回が取り消された回は、今までどおり失敗を書く**（c408c05 のレビュー）。
    /// 書かずに戻ると、読み込み中の丸のまま引き下げも再試行も効かない画面が残る
    func testGalleryFirstLoadCancelledDoesNotStayLoading() async {
        prepare()
        StubProtocol.fail(with: URLError(.cancelled))
        let model = GalleryViewModel(gallery: PublicGalleryService(
            url: URL(string: "https://site.example.test/app/data/photos.json")!,
            session: session,
            snapshot: PhotoSnapshotStore(fileName: UUID().uuidString)
        ))
        let task = Task { await model.load() }
        task.cancel()
        await task.value
        guard case .failed = model.state else { return XCTFail("読み込み中のまま残している") }
    }

    /// 人のページも同じ。見出しの無い画面に「まだありません」を出さない（c408c05 のレビュー）
    func testProfileFirstLoadCancelledShowsFailure() async {
        prepare()
        StubProtocol.fail(with: URLError(.cancelled))
        let env = AppEnvironment(tokenProvider: StubTokenProvider(token: "t"),
                                 gallery: PublicGalleryService(
                                    url: URL(string: "https://site.example.test/app/data/photos.json")!,
                                    session: session,
                                    snapshot: PhotoSnapshotStore(fileName: UUID().uuidString)),
                                 api: api())
        let model = UserProfileViewModel()
        let task = Task { await model.load(userId: "u1", environment: env, viewerId: nil) }
        task.cancel()
        await task.value
        XCTAssertNotNil(model.errorMessage, "取れていないのに失敗を出していない")
    }

    /// 圏外は「読み込めませんでした」を出す（例外を投げっぱなしにしない）。
    func testGalleryShowsMessageWhenOffline() async {
        prepare()
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        let model = GalleryViewModel(gallery: PublicGalleryService(
            url: URL(string: "https://site.example.test/app/data/photos.json")!,
            session: session,
            snapshot: PhotoSnapshotStore(fileName: UUID().uuidString)
        ))
        await model.load()
        guard case .failed(let message) = model.state else { return XCTFail("状態が違う") }
        XCTAssertFalse(message.isEmpty)
    }

    /// **ブロックしたら、探す画面からもすぐ消える。**
    ///
    /// `loadPhotos` は `guard allPhotos.isEmpty` で一度しか読まない作りなので、
    /// 読み直す口（`reloadPhotos`）が無いと、ブロックした相手の写真が
    /// 検索結果に残り続けた（アプリを閉じるまで消えない）。
    ///
    /// **要求の回数では見ない。** `PublicGalleryService` は短い間 控えを
    /// 使い回すので、読み直しても往復は起きないことがある。見るべきは
    /// 「消えたかどうか」。
    func testSearchDropsBlockedPhotosAfterReload() async {
        let blocked = """
        [{"id":"a","src":"https://x/a.jpg","userId":"u1","location":"パリ"},
         {"id":"b","src":"https://x/b.jpg","userId":"u2","location":"パリ"}]
        """
        let service = gallery(blocked)
        let env = AppEnvironment(tokenProvider: StubTokenProvider(token: "t"), gallery: service)
        let model = SearchViewModel()

        await model.loadPhotos(environment: env, epoch: 0)
        await model.search("パリ", environment: env)
        XCTAssertEqual(model.shown.count, 2, "下ごしらえが効いていない")

        await service.setHidden(userIds: ["u2"], photoIds: [])
        await model.reloadPhotos(environment: env)
        await model.search("パリ", environment: env)

        XCTAssertEqual(model.shown.map(\.id), ["a"],
                       "ブロックした相手の写真が検索結果に残っている")
    }

    /// **チップの数は、押したときに出る枚数。** 「すべて」はタグの語を撮影地にも
    /// 当てるので、タグの数（1）を出すと押して2枚出ていた
    func testTagChipCountMatchesWhatTappingShows() async {
        let service = gallery("""
        [{"id":"a","src":"https://x/a.jpg","userId":"u1","tags":["山"]},
         {"id":"b","src":"https://x/b.jpg","userId":"u1","location":"富士山"}]
        """)
        let env = AppEnvironment(tokenProvider: StubTokenProvider(token: "t"), gallery: service)
        let model = SearchViewModel()
        await model.loadPhotos(environment: env, epoch: 0)
        let chip = model.tagChips.first { $0.tag == "山" }
        await model.search("山", environment: env)
        XCTAssertEqual(chip?.count, model.shown.count, "チップの数と押した後の枚数が違う")
    }

    /// 🔴 **限定公開の読み出し口が替わったら（ログアウト・別の人のログイン）読み直す。**
    /// 探すは一度読んだら読み直さない作りで、前の人の「フォロワーのみ」の
    /// 写真が次の人の探すに残っていた。同じ回なら読み直さない
    func testSearchReloadsWhenTheViewerChanges() async {
        let service = gallery("""
        [{"id":"a","src":"https://x/a.jpg","userId":"u1","location":"パリ"},
         {"id":"b","src":"https://x/b.jpg","userId":"u2","location":"パリ"}]
        """)
        let env = AppEnvironment(tokenProvider: StubTokenProvider(token: "t"), gallery: service)
        let model = SearchViewModel()
        await model.loadPhotos(environment: env, epoch: 0)
        await service.setHidden(userIds: ["u2"], photoIds: [])

        await model.loadPhotos(environment: env, epoch: 0)
        await model.search("パリ", environment: env)
        XCTAssertEqual(model.shown.count, 2, "同じ回なのに読み直している")

        await service.setRestrictedLoader(nil)   // 人が替わった（回が 1 に進む）
        await model.loadPhotos(environment: env, epoch: 1)
        await model.search("パリ", environment: env)
        XCTAssertEqual(model.shown.map(\.id), ["a"], "人が替わったのに前の一覧のまま")
    }

    /// **人が替わったら、読み直しが返る前から前の人の段を出さない。**
    /// 一覧だけ空にして、チップ・季節の写真などは読み直しが返るまで前の人のまま残っていた
    func testSwitchingViewerClearsDerivedSectionsImmediately() async {
        let service = gallery("""
        [{"id":"a","src":"https://x/a.jpg","userId":"u1","tags":["山"]}]
        """)
        let env = AppEnvironment(tokenProvider: StubTokenProvider(token: "t"), gallery: service)
        let model = SearchViewModel()
        await model.loadPhotos(environment: env, epoch: 0)
        XCTAssertFalse(model.tagChips.isEmpty, "前提: チップが出ていない")

        // 人が替わった（限定公開の読み出し口を入れ替えた）。読み出しを遅くして、
        // 読み直しが返る前の画面を見る
        await service.setRestrictedLoader {
            try await Task.sleep(nanoseconds: 300_000_000)
            return []
        }
        let loading = Task { await model.loadPhotos(environment: env, epoch: 1) }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(model.tagChips.isEmpty, "読み直しの間、前の人のチップが残っている")
        XCTAssertFalse(model.hasLoaded, "読み直しの間に「読み込み済み」のまま")
        await loading.value
    }

    /// **最初の読み込みより先に読み直しが終わっても、その後の人の切り替えを見分ける。**
    /// 回を控えないまま抜けていたので、以後ずっと前の人の一覧のままだった
    func testViewerSwitchIsDetectedAfterAnEarlyReload() async {
        let service = gallery("""
        [{"id":"a","src":"https://x/a.jpg","userId":"u1","location":"パリ"},
         {"id":"b","src":"https://x/b.jpg","userId":"u2","location":"パリ"}]
        """)
        let env = AppEnvironment(tokenProvider: StubTokenProvider(token: "t"), gallery: service)
        let model = SearchViewModel()
        await model.reloadPhotos(environment: env)       // 引き下げが先に終わった
        await model.loadPhotos(environment: env, epoch: 0)
        await service.setHidden(userIds: ["u2"], photoIds: [])

        await service.setRestrictedLoader(nil)   // 人が替わった（回が 1 に進む）
        await model.loadPhotos(environment: env, epoch: 1)
        await model.search("パリ", environment: env)
        XCTAssertEqual(model.shown.map(\.id), ["a"], "人が替わったのに前の一覧のまま")
    }

    /// **最初の読み込みの前に始めた読み直しは、最初の読み込みが届いても捨てない**
    /// （ブロック直後の読み直しが捨てられ、ブロックした相手の写真が残っていた）
    func testReloadStartedBeforeFirstLoadIsKept() async {
        let service = gallery("""
        [{"id":"a","src":"https://x/a.jpg","userId":"u1","location":"パリ"},
         {"id":"b","src":"https://x/b.jpg","userId":"u2","location":"パリ"}]
        """)
        let env = AppEnvironment(tokenProvider: StubTokenProvider(token: "t"), gallery: service)
        let model = SearchViewModel()
        await model.reloadPhotos(environment: env)       // 1本目が先に終わる
        await service.setHidden(userIds: ["u2"], photoIds: [])
        await service.setRestrictedLoader {
            try await Task.sleep(nanoseconds: 200_000_000)
            return []
        }
        let blockReload = Task { await model.reloadPhotos(environment: env, force: true) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        await model.loadPhotos(environment: env, epoch: 0)   // 最初の回が届く
        await blockReload.value
        await model.search("パリ", environment: env)
        XCTAssertEqual(model.shown.map(\.id), ["a"], "ブロック後の読み直しが捨てられた")
    }

    /// 🔴 **知らせより先に終わった読み直しが前の人の一覧を持っていたら、読み直す。**
    /// 画面の回が nil の間に人が替わると、前の人の限定公開を含む一覧が残っていた
    func testListReadBeforeTheFirstNoticeIsReplacedAfterASwitch() async {
        let service = gallery("""
        [{"id":"a","src":"https://x/a.jpg","userId":"u1","location":"パリ"}]
        """)
        let env = AppEnvironment(tokenProvider: StubTokenProvider(token: "t"), gallery: service)
        await service.setRestrictedLoader {
            [try JSONDecoder.api.decode(Photo.self, from: Data(#"{"id":"secret","src":"https://x/s.jpg","userId":"u9","location":"パリ","audience":"closeFriends"}"#.utf8))]
        }
        let model = SearchViewModel()
        await model.reloadPhotos(environment: env)       // 前の人の口で読んだ（回 1）
        await service.setRestrictedLoader(nil)           // 知らせが届く前に人が替わった（回 2）
        await model.loadPhotos(environment: env, epoch: 2)
        await model.search("パリ", environment: env)
        XCTAssertEqual(model.shown.map(\.id), ["a"], "前の人の限定公開が残っている")
    }

    /// **新しい人の一覧が知らせより先に届いても、選んでいたカテゴリは外す**
    /// （一覧の古さだけで人の切り替えを見ていたので、この順だとカテゴリが残った）
    func testCategoryClearsEvenWhenTheNewListArrivesFirst() async {
        let service = gallery(feed)
        let env = AppEnvironment(tokenProvider: StubTokenProvider(token: "t"), gallery: service)
        let model = SearchViewModel()
        await model.loadPhotos(environment: env, epoch: 0)
        model.select(category: "風景")
        await service.setRestrictedLoader(nil)            // 人が替わった（回 1）
        await model.reloadPhotos(environment: env)       // ブロックの差し替えで先に読み直した
        await model.loadPhotos(environment: env, epoch: 1)
        XCTAssertNil(model.category, "知らせより先に一覧が届くと、カテゴリが残る")
    }

    /// **最初の知らせより先に一覧が入り、そこで選んだカテゴリも、人が替わったら外す**
    func testCategoryClearsOnTheFirstNoticeAfterAnEarlyList() async {
        let service = gallery(feed)
        let env = AppEnvironment(tokenProvider: StubTokenProvider(token: "t"), gallery: service)
        let model = SearchViewModel()
        await model.reloadPhotos(environment: env)       // 知らせより先に一覧が入った（回 0）
        model.select(category: "風景")
        await service.setRestrictedLoader(nil)            // 人が替わった（回 1）
        await model.loadPhotos(environment: env, epoch: 1) // 最初の知らせ
        XCTAssertNil(model.category, "最初の知らせでカテゴリが外れない")
    }

    /// **人が替わったら、選んでいたカテゴリも外す**（次の人の一覧に無いと0件のまま）
    func testSwitchingViewerClearsTheCategory() async {
        let service = gallery(feed)
        let env = AppEnvironment(tokenProvider: StubTokenProvider(token: "t"), gallery: service)
        let model = SearchViewModel()
        await model.loadPhotos(environment: env, epoch: 0)
        model.select(category: "風景")
        XCTAssertNotNil(model.category)
        await service.setRestrictedLoader(nil)   // 人が替わった（回が 1 に進む）
        await model.loadPhotos(environment: env, epoch: 1)
        XCTAssertNil(model.category, "前の人の画面で選んだカテゴリが残っている")
    }

    /// **「フォロー中」を選んだあとにフォロー一覧を入れ替えても、範囲は戻らない。**
    ///
    /// `use(viewerId:following:)` を使い回すと、あちらは範囲を既定
    /// （ログイン中は「自分」）へ倒すので、選んだ瞬間に自分の写真へ
    /// 戻ってしまう。入れ替え専用の口を分けてある。
    func testRefreshingFollowingKeepsTheChosenScope() async {
        let model = GalleryViewModel(gallery: gallery(feed))
        await model.load()
        model.use(viewerId: "me", following: [])
        model.select(scope: .following)

        model.refreshFollowing(["u2"], viewerId: "me")

        XCTAssertEqual(model.scope, .following, "範囲が勝手に戻っている")
    }

    /// **上限で断られたら、サーバーの一覧に揃える。**
    ///
    /// 揃えないと、別の端末で留めたぶんが画面に出ないまま
    /// 「3枚までです」と言われ続ける——見えていないものは外せないので、
    /// 画面の中に直す手立てが無くなる。
    func testRefusedPinSyncsWithTheServer() async {
        prepare()
        let model = MyPageViewModel(api: api())
        StubProtocol.respondInOrder([
            (status: 409, body: #"{"error":"ピン留めは3枚までです","pinnedPhotoIds":["a","b","c"]}"#),
            (status: 200, body: #"{"userId":"me","pinnedPhotoIds":["a","b","c"]}"#),
        ])

        await model.setPinned("d", pinned: true)

        // **一覧を消さない側に入っていること。** `errorMessage` に入れると
        // 画面が写真グリッドごと知らせに差し替わり、解除する長押しメニューも
        // 消えて、断られた人が直す手立てを失う
        XCTAssertNotNil(model.actionMessage, "断られたことを伝えていない")
        XCTAssertNil(model.errorMessage, "一覧を消す側に入れている")
        XCTAssertEqual(model.pinnedIds, ["a", "b", "c"],
                       "断られたのにサーバーの一覧へ揃えていない")
    }

    /// **一度読めていれば、読み直しの失敗で格子ごと知らせに置き換えない**（バグ探し 2026-09-27 #18）。
    /// 戻ってくるたびに読み直すので、圏外で写真を開いて戻っただけで格子が消えていた。
    /// 次に読めたら知らせを消す。
    ///
    /// ⚠️ 失敗させるのは**写真の口だけ**。プロフィールを落とすと、同時に走っている写真の要求が
    /// 取り消され、Linux の FoundationNetworking ではスタブの取り消しが返らずに止まることがある
    func testReloadFailureIsAddedToTheGridNotReplacingIt() async {
        prepare()
        func serve(photos status: Int) {
            StubProtocol.reset()
            StubProtocol.respond(path: "/user/profile", status: 200, body: #"{"userId":"a"}"#)
            StubProtocol.respond(path: "/user/photos", status: status,
                                 body: status == 200 ? #"[{"id":"p1","src":"/uploads/p1.jpg"}]"# : #"{"error":"取得に失敗しました"}"#)
        }
        serve(photos: 200)
        let model = MyPageViewModel(api: api())
        await model.load()
        XCTAssertEqual(model.photos.map(\.id), ["p1"])

        serve(photos: 500)
        await model.load()
        XCTAssertNil(model.errorMessage, "読み直しの失敗で格子ごと知らせに置き換えている")
        XCTAssertEqual(model.reloadError, "取得に失敗しました")
        XCTAssertNil(model.actionMessage, "読み直しの失敗をピン留めの断りの欄に混ぜている")
        XCTAssertEqual(model.photos.map(\.id), ["p1"], "読めていた写真を捨てている")

        serve(photos: 200)
        await model.load()
        XCTAssertNil(model.reloadError, "読めたのに失敗の知らせが残っている")
    }

    /// **初回にプロフィールだけ取れて写真で落ちた回も「読めていない」。** プロフィールは
    /// 写真より先に入るので、`profile` で決めると格子に「まだ写真がありません」と嘘が出た（a1734cc のレビュー）
    func testFirstLoadWithOnlyTheProfileIsStillAFailure() async {
        prepare()
        StubProtocol.respond(path: "/user/profile", status: 200, body: #"{"userId":"a"}"#)
        StubProtocol.respond(path: "/user/photos", status: 500, body: #"{"error":"取得に失敗しました"}"#)
        let model = MyPageViewModel(api: api())
        await model.load()
        XCTAssertNotNil(model.errorMessage, "写真を読めていないのに一覧に添える側に入れている")
        XCTAssertNil(model.reloadError)
    }

    /// **人が替わったら前の人の写真を手放す。** 残すと、次の人の読み込みが
    /// 落ちたとき前の人の写真（非公開を含む）が保存の引き当て先に残る
    func testForgetPhotosDropsThePreviousUsersPhotos() async {
        prepare()
        StubProtocol.respond(path: "/user/profile", status: 200,
                             body: #"{"userId":"a","pinnedPhotoIds":["p1"]}"#)
        StubProtocol.respond(path: "/user/photos", status: 200,
                             body: #"[{"id":"p1","src":"/uploads/p1.jpg","published":false}]"#)
        let model = MyPageViewModel(api: api())
        await model.load()
        XCTAssertEqual(model.photos.map(\.id), ["p1"], "前提: 前の人の写真を読めていない")

        model.forgetPhotos()

        XCTAssertTrue(model.photos.isEmpty, "前の人の写真が残っている")
        XCTAssertTrue(model.pinnedIds.isEmpty, "前の人の留めた写真が残っている")
    }

    /// 🔴 **人が替わった後に返った前の人の読み込みは、何も入れない。**
    /// `onAppear` の Task は人が替わっても止まらず、`forgetPhotos` で空にした
    /// 後に前の人の写真（非公開を含む）が入っていた（c8a8781 のレビュー）。
    /// 次の人の最初の読み込みも「走っている」と見て帰らないこと
    func testLateLoadForThePreviousUserIsDropped() async {
        prepare()
        StubProtocol.respond(path: "/user/profile", status: 200,
                             body: #"{"userId":"a","displayName":"前の人"}"#, delay: 0.3)
        StubProtocol.respond(path: "/user/photos", status: 200,
                             body: #"[{"id":"secret","src":"/uploads/s.jpg","published":false}]"#)
        let model = MyPageViewModel(api: api())
        let late = Task { await model.load(for: "a") }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(model.isLoading, "前提: 前の人の読み込みが走っていない")

        model.forgetPhotos(for: "b")
        XCTAssertFalse(model.isLoading, "次の人の最初の読み込みが止められる")
        await late.value

        XCTAssertTrue(model.photos.isEmpty, "前の人の写真が次の人の画面に入った")
        XCTAssertNil(model.profile, "前の人のプロフィールが次の人の画面に入った")
    }

    /// **`.task(id:)` が `.onChange` より先に走っても、次の人の読み込みは捨てない。**
    /// 前の人の読み込みが走っている最中でも、次の人の分は走り、答えが入る
    /// （6f29a3e は「走っている」と見て帰り、そのあと前の人の分が捨てられて空のままだった）
    func testNextUsersLoadSurvivesEitherOrder() async {
        prepare()
        StubProtocol.respond(path: "/user/profile", status: 200,
                             body: #"{"userId":"b","displayName":"次の人"}"#, delay: 0.2)
        StubProtocol.respond(path: "/user/photos", status: 200,
                             body: #"[{"id":"p1","src":"/uploads/p1.jpg"}]"#)
        let model = MyPageViewModel(api: api())
        let previous = Task { await model.load(for: "a") }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let next = Task { await model.load(for: "b") }   // task が先
        try? await Task.sleep(nanoseconds: 20_000_000)
        model.forgetPhotos(for: "b")                     // onChange が後
        await previous.value
        await next.value

        XCTAssertEqual(model.profile?.displayName, "次の人", "次の人の読み込みが捨てられた")
        XCTAssertEqual(model.photos.map(\.id), ["p1"])
        XCTAssertFalse(model.isLoading)
    }

    /// **写真だけ落ちても、見出し（名前）は出す。** 写真の欄だけが知らせになる
    func testProfileShowsEvenWhenPhotosFail() async {
        prepare()
        StubProtocol.respond(path: "/user/profile", status: 200,
                             body: #"{"userId":"a","displayName":"わたし"}"#)
        StubProtocol.respond(path: "/user/photos", status: 500, body: #"{"error":"x"}"#)
        StubProtocol.respond(path: "/users/a/follow", status: 200,
                             body: #"{"followers":7,"following":3}"#)
        let model = MyPageViewModel(api: api())
        await model.load(for: "a")
        XCTAssertEqual(model.profile?.displayName, "わたし", "写真の失敗で見出しまで消えた")
        XCTAssertEqual(model.followers, 7, "写真の失敗でフォロー数を取りに行かず 0 と出る")
        XCTAssertNotNil(model.errorMessage)
    }

    /// **フォロー数が遅くても、写真は待たずに入る**（3ecb6a5 は数を待ってから
    /// 写真を入れていたので、格子が往復1回ぶん遅れていた）
    func testSlowFollowStatsDoNotHoldBackPhotos() async {
        prepare()
        StubProtocol.respond(path: "/user/profile", status: 200, body: #"{"userId":"a"}"#)
        StubProtocol.respond(path: "/user/photos", status: 200,
                             body: #"[{"id":"p1","src":"/uploads/p1.jpg"}]"#)
        StubProtocol.respond(path: "/users/a/follow", status: 200,
                             body: #"{"followers":2,"following":1}"#, delay: 0.5)
        let model = MyPageViewModel(api: api())
        let loading = Task { await model.load(for: "a") }
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(model.photos.map(\.id), ["p1"], "フォロー数を待って写真が遅れている")
        await loading.value
        XCTAssertEqual(model.followers, 2)
    }

    /// **ログインしていない呼び出しは何もしない**（読み込み中の印も立てない）
    func testLoadWithoutAUserDoesNothing() async {
        prepare()
        StubProtocol.respond(path: "/user/profile", status: 200, body: #"{"userId":"a"}"#)
        let model = MyPageViewModel(api: api())
        await model.load(for: nil)
        XCTAssertNil(model.profile)
        XCTAssertEqual(StubProtocol.requestCount, 0, "ログインしていないのに鍵の要る口を叩いた")
    }

    /// 🔴 **前の人の読み込みの途中で人が替わったら、その答えを書かない。**
    /// 次の人の読み込みも押さえで弾かない（書き込まれた前の人の下書きが残っていた）
    func testSlowLoadOfThePreviousUserIsDiscarded() async {
        prepare()
        StubProtocol.respond(path: "/user/profile", status: 200,
                             body: #"{"userId":"a"}"#, delay: 0.3)
        StubProtocol.respond(path: "/user/photos", status: 200,
                             body: #"[{"id":"p1","src":"/uploads/p1.jpg","published":false}]"#, delay: 0.3)
        let model = MyPageViewModel(api: api())
        async let previous: Void = model.load()
        try? await Task.sleep(nanoseconds: 100_000_000)
        model.forgetPhotos()
        XCTAssertFalse(model.isLoading, "人が替わったのに前の人の読み込み中のまま")
        await previous
        XCTAssertTrue(model.photos.isEmpty, "前の人の写真（下書き）が次の人に書き込まれた")
        XCTAssertNil(model.profile, "前の人の見出しが次の人に書き込まれた")
    }

    #if DEBUG
    /// 🔴 **鍵を持たずに入っている回、マイページが丸ごと「ログインが必要です」
    /// になっていた。**
    ///
    /// `PreviewSession`（Debug のみ・絵を撮るための ID だけのログイン）は
    /// 「作品の格子は本物のデータで描かれる」と書いてあったのに、
    /// `load()` は鍵の要る `/user/profile` と `/user/photos` しか見ておらず、
    /// トークンが無いので**何も出ないまま知らせだけ**が出ていた
    /// （run 63・64 のマイページの絵）。
    ///
    /// 逃がす先は人のページと同じ経路＝公開プロフィール＋公開一覧の絞り込み。
    func testPreviewSessionDrawsMyPageWithoutAToken() async {
        prepare()
        UserDefaults.standard.set("u1", forKey: PreviewSession.defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: PreviewSession.defaultsKey) }

        // **道ごとに返す。** 鍵の要る口（`/user/...`）には何も置かないので、
        // そこを叩いたら 404 になり、写真は1枚も入らない
        StubProtocol.respond(path: "/profile/u1",
                             status: 200,
                             body: #"{"userId":"u1","displayName":"ルズ","pinnedPhotoIds":["b"]}"#)
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: """
        [{"id":"a","src":"https://x/a.jpg","userId":"u1","createdAt":"2026-01-02T00:00:00Z"},
         {"id":"b","src":"https://x/b.jpg","userId":"u1","createdAt":"2026-01-01T00:00:00Z"},
         {"id":"z","src":"https://x/z.jpg","userId":"other","createdAt":"2026-03-04T00:00:00Z"}]
        """)

        // **トークンは渡さない**（鍵を持たないログインの再現）
        let model = MyPageViewModel(
            api: api(token: nil),
            gallery: PublicGalleryService(
                url: URL(string: "https://site.example.test/app/data/photos.json")!,
                session: session,
                snapshot: PhotoSnapshotStore(fileName: UUID().uuidString)
            )
        )
        await model.load()

        XCTAssertNil(model.errorMessage, "鍵が無いだけで画面ごと知らせに差し替わっている")
        XCTAssertEqual(model.photos.map(\.id), ["b", "a"],
                       "自分の公開写真が出ていない（留めたぶんが先頭）")
        XCTAssertEqual(model.profile?.displayName, "ルズ", "公開プロフィールを見ていない")
    }
    #endif

    // MARK: - 写真の詳細

    /// 🔴 **読み込み前・取れなかった回に 0 と出さない。** 一覧から来た数で始める
    func testLikesStartFromTheListCount() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()), initialLikes: 7)
        XCTAssertEqual(model.likes, 7)
        StubProtocol.respond(status: 500, body: "{}")
        await model.load()
        XCTAssertEqual(model.likes, 7, "取れなかった回に一覧の数を捨てている")
    }

    /// 🔴 **束の隣へ送ったら、数・ハート・コメントをその1枚のものに替える。**
    /// 開いた1枚のままだと、2枚目を見ながら押したいいねが1枚目に付いていた
    func testShowAnotherPhotoInTheBundleSwitchesTheTarget() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()), initialLikes: 7)
        model.setSignedIn(true)
        StubProtocol.respond(status: 200, body: #"{"liked":true,"likes":8}"#)
        await model.toggleLike()
        model.draftComment = "1枚目へのコメント"

        model.show(photoId: "p2", initialLikes: 3, liked: false)
        XCTAssertEqual(model.likes, 3, "前の1枚の数が残っている")
        XCTAssertFalse(model.liked, "前の1枚のハートが残っている")
        XCTAssertNil(model.lastLikeAnswer)
        XCTAssertNil(model.commentCount)
        XCTAssertEqual(model.draftComment, "", "前の1枚への書きかけが残っている")

        StubProtocol.respond(status: 200, body: #"{"liked":true,"likes":4}"#)
        await model.toggleLike()
        XCTAssertTrue(StubProtocol.lastRequest?.url?.path.contains("p2") == true,
                      "送った先ではなく開いた1枚にいいねを送っている")
    }

    /// 🔴 **送っている間に束の隣へ送っても、答えは押した1枚のもの。**
    /// 今の1枚の画面には書かず、押した1枚の id で返す（呼び出し側が控えに書く）
    func testLikeAnswerKeepsThePressedPhotoAfterSwiping() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(true)
        StubProtocol.respond(path: "/photos/p1/like", status: 200,
                             body: #"{"liked":true,"likes":9}"#, delay: 0.2)
        async let pressed = model.toggleLike()
        try? await Task.sleep(nanoseconds: 50_000_000)
        model.show(photoId: "p2", initialLikes: 2, liked: false)
        let answer = await pressed
        XCTAssertEqual(answer, PhotoDetailViewModel.LikeAnswer(photoId: "p1", liked: true, likes: 9),
                       "押した1枚の答えを返していない（控えに入らない）")
        XCTAssertFalse(model.liked, "前の1枚の答えを今の1枚に書いている")
        XCTAssertEqual(model.likes, 2)
    }

    /// 🔴 **圏外で開いたいいね済みの写真を白いハートにしない。** 端末の控えで始め、
    /// 押して届かなかった回は「答えなし」を返す（呼び出し側が控えを消さない）
    func testOfflineKeepsTheStoredHeart() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(true)
        model.show(photoId: "p1", initialLikes: 3, liked: true)
        StubProtocol.respond(status: 500, body: "{}")
        await model.load()
        XCTAssertTrue(model.liked, "引けなかった回に控えのハートを消している")
        let answered = await model.toggleLike()
        XCTAssertNil(answered, "届かなかったのに答えがあった扱い")
        XCTAssertTrue(model.liked)
    }

    /// **コメントの読み直しと、投稿・削除を同時に走らせない。** 後から着いた古いページが
    /// 入れた・消したコメントを上書きする（画面は互いのボタンを押せなくしている）
    func testCommentReloadExcludesPostAndDelete() async throws {
        prepare()
        let page = #"{"items":[{"id":"c1","uid":"u1","name":"a","text":"hi"}],"count":1}"#
        StubProtocol.respond(path: "/photos/p1/comments", status: 200, body: page, delay: 0.3)
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(true)
        await model.reloadComments()
        let comment = try XCTUnwrap(model.comments.first)
        let before = StubProtocol.requestCount

        let reload = Task { await model.reloadComments() }
        for _ in 0..<2000 where !model.isReloadingComments { try? await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(model.isReloadingComments)
        model.draftComment = "new"
        await model.postComment()
        await model.deleteComment(comment)
        await reload.value

        XCTAssertEqual(StubProtocol.requestCount, before + 1, "読み直しの最中に投稿・削除を投げている")
        XCTAssertEqual(model.draftComment, "new", "投げていないのに下書きを消している")
    }

    /// 投稿している間は読み直さない
    func testCommentPostExcludesReload() async {
        prepare()
        StubProtocol.respond(path: "/photos/p1/comments", status: 200,
                             body: #"{"comment":{"id":"c2","uid":"me","name":"me","text":"x"}}"#, delay: 0.3)
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(true)
        model.draftComment = "x"
        let post = Task { await model.postComment() }
        for _ in 0..<2000 where !model.isPosting { try? await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(model.isPosting)
        await model.reloadComments()
        await post.value
        XCTAssertEqual(StubProtocol.requestCount, 1, "投稿の最中に読み直しを投げている")
    }

    /// **前の1枚の読み直しで、隣の1枚の送信を止めない。** 読み直しの印が画面で
    /// 1つだったので、p1 の読み直し（圏外で長く待つ）の間、p2 で送れなかった
    func testCommentReloadOfPreviousPhotoDoesNotBlockNextPhoto() async throws {
        prepare()
        StubProtocol.respond(path: "/photos/p1/comments", status: 200,
                             body: #"{"items":[],"count":0}"#, delay: 0.3)
        StubProtocol.respond(path: "/photos/p2/comments", status: 200,
                             body: #"{"items":[],"count":0,"comment":{"id":"c9","uid":"me","name":"me","text":"new"}}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(true)

        let reload = Task { await model.reloadComments() }
        for _ in 0..<2000 where !model.isReloadingComments { try? await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(model.isReloadingComments)
        model.show(photoId: "p2", initialLikes: nil, liked: false)
        XCTAssertFalse(model.isReloadingComments, "前の1枚の読み直しで、今の1枚のボタンまで止めている")
        model.draftComment = "new"
        await model.postComment()
        XCTAssertEqual(model.comments.map(\.id), ["c9"], "前の1枚の読み直しの間、今の1枚に送れない")
        await reload.value
        XCTAssertEqual(model.comments.map(\.id), ["c9"], "前の1枚の読み直しの答えを今の1枚に出している")
    }

    /// **読み直しの印は1枚ごと。** 1つの枠だと、p1→p2 で p2 の読み直しが印を
    /// 上書きし、p1 に戻ると p1 の読み直しが走ったまま再試行を押せた
    func testCommentReloadMarkSurvivesAnotherPhotosReload() async throws {
        prepare()
        StubProtocol.respond(path: "/photos/p1/comments", status: 200,
                             body: #"{"items":[],"count":0}"#, delay: 0.3)
        StubProtocol.respond(path: "/photos/p2/comments", status: 200,
                             body: #"{"items":[],"count":0}"#, delay: 0.3)
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(true)
        let first = Task { await model.reloadComments() }
        for _ in 0..<2000 where !model.isReloadingComments { try? await Task.sleep(for: .milliseconds(1)) }
        model.show(photoId: "p2", initialLikes: nil, liked: false)
        let second = Task { await model.reloadComments() }
        for _ in 0..<2000 where !model.isReloadingComments { try? await Task.sleep(for: .milliseconds(1)) }
        model.show(photoId: "p1", initialLikes: nil, liked: false)
        XCTAssertTrue(model.isReloadingComments, "別の1枚の読み直しで、この1枚の読み直し中の印が消えた")
        await first.value
        await second.value
        XCTAssertFalse(model.isReloadingComments)
    }

    /// コメントの削除の 404: **読み込んだコメントは「もう無い」として外す**が、
    /// **この画面で投稿したばかりのものは外さない**（サーバーの最初の読みが結果整合で、
    /// 「まだ見えない」だけの 404 がある。外すと他の人には見えたまま自分からだけ消える）
    func testCommentDeleteNotFoundDependsOnWhetherItWasJustPosted() async throws {
        prepare()
        StubProtocol.respond(path: "/photos/p1/comments/c1", status: 404, body: #"{"error":"コメントが見つかりません"}"#)
        StubProtocol.respond(path: "/photos/p1/comments/c2", status: 404, body: #"{"error":"コメントが見つかりません"}"#)
        StubProtocol.respond(path: "/photos/p1/comments", status: 200,
                             body: #"{"items":[{"id":"c1","uid":"u1","name":"a","text":"hi"}],"count":1,"comment":{"id":"c2","uid":"me","name":"me","text":"new"}}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(true)
        await model.reloadComments()
        model.draftComment = "new"
        await model.postComment()
        XCTAssertEqual(model.comments.map(\.id), ["c2", "c1"])
        let loaded = try XCTUnwrap(model.comments.first { $0.id == "c1" })
        let posted = try XCTUnwrap(model.comments.first { $0.id == "c2" })

        XCTAssertEqual(model.commentCount, 2)

        await model.deleteComment(loaded)
        XCTAssertFalse(model.comments.contains { $0.id == "c1" }, "もう無いコメントが残っている")
        XCTAssertEqual(model.commentCount, 1, "もう無いコメントを外したのに数を減らしていない")
        XCTAssertNil(model.errorMessage)

        await model.deleteComment(posted)
        XCTAssertTrue(model.comments.contains { $0.id == "c2" }, "投稿直後の 404 で外している（サーバーには残る）")
        XCTAssertEqual(model.commentCount, 1)
        XCTAssertEqual(model.errorMessage,
                       L("まだ反映されていないため削除できませんでした。少し待ってからもう一度お試しください",
                         "Couldn't delete it yet. Please wait a moment and try again."),
                       "「見つかりません」と言っている")

        // 時間が経ってからの 404 は「もう無い」（持ち主が先に消した など）。失敗の文も残さない
        let later = Date().addingTimeInterval(PhotoDetailViewModel.justPostedWindow + 1)
        model.now = { later }
        await model.deleteComment(posted)
        XCTAssertFalse(model.comments.contains { $0.id == "c2" }, "時間が経っても外せず詰まる")
        XCTAssertNil(model.errorMessage, "前の失敗の文が残っている")
    }

    /// **いいねの数は自分で足さない。** サーバーが返した数を使う。
    func testLikeUsesServerCount() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(true)

        StubProtocol.respond(status: 200, body: #"{"liked":true,"likes":42}"#)
        await model.toggleLike()

        XCTAssertTrue(model.liked)
        XCTAssertEqual(model.likes, 42, "手元で足し算している")
        // ホームへ渡すのは押した答え
        XCTAssertEqual(model.lastLikeAnswer, 42)
    }

    /// **開いて読んだ数は、ホームへ渡す答えにしない。** 読み取りは
    /// 「あとで揃う」ので、押した直後に開くと押す前の数が返りうる
    func testLoadedCountIsNotAnAnswer() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        StubProtocol.respond(status: 200, body: #"{"likes":4}"#)
        await model.load()
        XCTAssertEqual(model.likes, 4)
        XCTAssertNil(model.lastLikeAnswer)
    }

    /// 未ログインで押した回も、前の答えを残さない（呼び出し側が「いま」の
    /// 答えとしてホームへ渡し直すため）
    func testSignedOutPressClearsAnswer() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(true)
        StubProtocol.respond(status: 200, body: #"{"liked":true,"likes":5}"#)
        await model.toggleLike()
        XCTAssertEqual(model.lastLikeAnswer, 5)
        model.setSignedIn(false)
        await model.toggleLike()
        XCTAssertNil(model.lastLikeAnswer)
    }

    /// 押して失敗したら、前の答えも残さない（古い答えをホームへ渡さない）
    func testFailedLikeClearsAnswer() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(true)
        StubProtocol.respond(status: 200, body: #"{"liked":true,"likes":5}"#)
        await model.toggleLike()
        XCTAssertEqual(model.lastLikeAnswer, 5)
        StubProtocol.respond(status: 500, body: "{}")
        await model.toggleLike()
        XCTAssertNil(model.lastLikeAnswer)
    }

    /// **素早く2回叩いても1回しか投げない。**
    ///
    /// 押さえが無いと、1回目の応答が返る前に2回目が古い `liked` を見て走り、
    /// 「いいね」と「取り消し」が同時に飛ぶ。どちらが後に返るかでハートの
    /// 色が決まるので、押した結果と食い違う。
    func testDoubleTapLikesOnlyOnce() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(true)
        StubProtocol.respond(status: 200, body: #"{"liked":true,"likes":1}"#)

        async let first: PhotoDetailViewModel.LikeAnswer? = model.toggleLike()
        async let second: PhotoDetailViewModel.LikeAnswer? = model.toggleLike()
        _ = await (first, second)

        XCTAssertEqual(StubProtocol.requestCount, 1, "二度押しで2回投げている")
        XCTAssertTrue(model.liked)
    }

    /// 未ログインでいいねを押したら、**通信せずに**案内を出す。
    func testLikeWithoutSignInAsksToSignIn() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api(token: nil)))
        model.setSignedIn(false)
        await model.toggleLike()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(StubProtocol.lastRequest, "未ログインなのに要求を投げている")
    }

    /// コメントは送ったら**その場で先頭に出す**（再読み込みを待たせない）。
    ///
    /// **総数が分からない回は分からないまま。** 取れていない数に +1 すると
    /// 「1」という嘘の総数になる。一覧には載るので、数だけ無いのが正直
    func testPostedCommentAppearsImmediately() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(true)
        model.draftComment = "きれい"

        StubProtocol.respond(status: 200, body: #"{"comment":{"id":"c1","uid":"u1","name":"たろう","text":"きれい"}}"#)
        await model.postComment()

        XCTAssertEqual(model.comments.first?.text, "きれい")
        XCTAssertNil(model.commentCount, "総数を引いていないのに数を作っている")
        XCTAssertEqual(model.draftComment, "", "送ったのに入力欄が残っている")

        // 総数が取れているなら、そこに足す（読んだ一覧には書いた1件も載っている）
        StubProtocol.respond(status: 200,
                             body: #"{"items":[{"id":"c1","uid":"u1","name":"たろう","text":"きれい"}],"count":3}"#)
        await model.load()
        XCTAssertEqual(model.commentCount, 3)

        model.draftComment = "すてき"
        StubProtocol.respond(status: 200, body: #"{"comment":{"id":"c2","uid":"u1","name":"たろう","text":"すてき"}}"#)
        await model.postComment()
        XCTAssertEqual(model.commentCount, 4)
    }

    /// **引けなかった回に「0」を出さない。** 0 は「まだ無い」と読まれる
    func testCommentCountIsUnknownWhenFetchFails() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(false)
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        await model.load()
        XCTAssertNil(model.commentCount, "圏外なのに数を出している")
        XCTAssertTrue(model.commentsUnavailable, "取れなかったことを画面に伝えていない")
    }

    /// **数はサーバーの総数。** 手元の1ページ分を数え直さない
    /// （items が1件でも count が 24 なら 24）
    func testCommentCountFollowsServerPage() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(false)
        StubProtocol.respond(status: 200,
                             body: #"{"items":[{"id":"c1","uid":"u1","name":"たろう","text":"きれい"}],"count":24}"#)
        await model.load()
        XCTAssertEqual(model.commentCount, 24, "1ページ分を数え直している")
        XCTAssertEqual(model.comments.count, 1)
        XCTAssertFalse(model.commentsUnavailable)

        // 消したら総数からも引く（0 未満にはしない）
        StubProtocol.respond(status: 200, body: "{}")
        await model.deleteComment(model.comments[0])
        XCTAssertEqual(model.commentCount, 23)
        XCTAssertTrue(model.comments.isEmpty)
    }

    /// 🔴 **一覧に一度載った自分のコメントは、以後サーバーを信じる。**
    /// 持ち主が消したコメントを手元の控えから復活させ、数も1つずらしていた
    func testPostedCommentRemovedOnServerDoesNotComeBack() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(true)
        model.draftComment = "きれい"
        StubProtocol.respond(status: 200, body: #"{"comment":{"id":"c1","uid":"u1","name":"たろう","text":"きれい"}}"#)
        await model.postComment()

        StubProtocol.respond(status: 200,
                             body: #"{"items":[{"id":"c1","uid":"u1","name":"たろう","text":"きれい"}],"count":3}"#)
        await model.load()
        XCTAssertEqual(model.commentCount, 3)

        // 持ち主が消した
        StubProtocol.respond(status: 200, body: #"{"items":[],"count":2}"#)
        await model.load()
        XCTAssertTrue(model.comments.isEmpty, "消されたコメントを戻している")
        XCTAssertEqual(model.commentCount, 2)
    }

    /// 🔴 **束の隣へ送っても、前の1枚で書いたコメントを持ち込まない。**
    /// 控えが1本だったので、p1 で書いたコメントが p2 の先頭に差し込まれ、数も +1 された
    func testPostedCommentStaysWithItsPhoto() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(true)
        model.draftComment = "きれい"
        StubProtocol.respond(status: 200, body: #"{"comment":{"id":"c1","uid":"u1","name":"たろう","text":"きれい"}}"#)
        await model.postComment()

        model.show(photoId: "p2", initialLikes: nil, liked: false)
        StubProtocol.respond(status: 200, body: #"{"items":[],"count":0}"#)
        await model.load()
        XCTAssertTrue(model.comments.isEmpty, "p1 のコメントが p2 に出ている")
        XCTAssertEqual(model.commentCount, 0)
    }

    /// **送っている間に隣へ送っても、戻れば書いたコメントが出る**
    /// （控えは送った先の1枚に付く。一覧への反映が遅れていても消えない）
    func testCommentPostedWhileAwayShowsOnReturn() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(true)
        model.draftComment = "きれい"
        StubProtocol.respond(path: "/comments", status: 200,
                             body: #"{"comment":{"id":"c1","uid":"u1","name":"たろう","text":"きれい"}}"#, delay: 0.2)
        let posting = Task { await model.postComment() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        model.show(photoId: "p2", initialLikes: nil, liked: false)
        await posting.value

        model.show(photoId: "p1", initialLikes: nil, liked: false)
        StubProtocol.reset()
        StubProtocol.respond(status: 200, body: #"{"items":[],"count":0}"#)
        await model.load()
        XCTAssertEqual(model.comments.map(\.id), ["c1"], "書いたコメントが戻っても出ない")
        XCTAssertEqual(model.commentCount, 1)
    }

    /// **送っている間の読み直しに既に載っていたら、二重に足さない**
    func testPostedCommentIsNotDuplicatedWhenAlreadyListed() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(true)
        StubProtocol.respond(status: 200,
                             body: #"{"items":[{"id":"c1","uid":"u1","name":"たろう","text":"きれい"}],"count":1}"#)
        await model.load()
        model.draftComment = "きれい"
        StubProtocol.respond(status: 200, body: #"{"comment":{"id":"c1","uid":"u1","name":"たろう","text":"きれい"}}"#)
        await model.postComment()
        XCTAssertEqual(model.comments.map(\.id), ["c1"], "同じコメントが2つ出ている")
        XCTAssertEqual(model.commentCount, 1)
    }

    /// 空のコメントは送らない。
    func testEmptyCommentIsNotSent() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(true)
        model.draftComment = "   "
        await model.postComment()
        XCTAssertNil(StubProtocol.lastRequest)
    }
    /// 投稿を待っている1枚（テスト用。本物は `ImagePreparer` が作る）。
    private func pending(location: String = "") -> PendingPhoto {
        var photo = PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data([0xff]), fileName: "photo.jpg", contentType: "image/jpeg",
            exif: nil, coords: Photo.Coords(lat: 34.28, lng: 133.8), takenOn: nil))
        photo.location = location
        return photo
    }

    private func uploadModel() -> UploadViewModel {
        UploadViewModel(uploads: UploadService(api: api(), session: session),
                        albums: AlbumService(api: api()),
                        photos: PhotoService(api: api()),
                        discovery: DiscoveryService(api: api()))
    }

    /// **引けなかった回に「押していない」と言わない。**
    /// 電波が悪いだけでハートが白に戻ると、押した人は「取り消された」と読む。
    func testLikeStateSurvivesAFailedReload() async throws {
        prepare()
        // いいね数・コメント・自分のいいね、の3本のうち最後だけ落とす
        StubProtocol.respond(status: 200, body: #"{"likes":3}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(true)
        await model.load()
        XCTAssertFalse(model.liked, "まだ押していない")

        StubProtocol.respond(status: 200, body: #"{"liked":true}"#)
        await model.load()
        XCTAssertTrue(model.liked)

        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        await model.load()
        XCTAssertTrue(model.liked, "圏外でハートが白に戻らない")
    }

    /// **撮影地は、写真の座標から先に埋める**（Web の `reverseGeocode` と同じ）。
    ///
    /// 実データでは公開30枚のうち13枚が空だった。撮影地 → 地図 →
    /// `/location/*` → 検索流入 がこのサイトの価値なので、空のまま出さない。
    func testPlaceNameIsFilledFromTheCoordinates() async throws {
        prepare()
        StubProtocol.respond(status: 200, body: #"{"place":"高松市"}"#)
        let model = uploadModel()
        model.items = [pending()]

        await model.fillPlaceName(for: model.items[0].id, lat: 34.28, lng: 133.8)

        XCTAssertEqual(model.items[0].location, "高松市")
    }

    /// **打ってあるものは奪わない。** 本人が入れた固有名詞の方が、
    /// 市区町村レベルの地名より強い（`/location/*` に効く語はそちら）。
    func testTypedPlaceIsNotOverwritten() async throws {
        prepare()
        StubProtocol.respond(status: 200, body: #"{"place":"高松市"}"#)
        let model = uploadModel()
        model.items = [pending(location: "高屋神社")]

        await model.fillPlaceName(for: model.items[0].id, lat: 34.28, lng: 133.8)

        XCTAssertEqual(model.items[0].location, "高屋神社")
    }

    /// 引けなくても投稿は止めない（空のまま進む）。
    func testFailureLeavesThePlaceEmpty() async throws {
        prepare()
        StubProtocol.respond(status: 500, body: #"{"error":"だめでした"}"#)
        let model = uploadModel()
        model.items = [pending()]

        await model.fillPlaceName(for: model.items[0].id, lat: 34.28, lng: 133.8)

        XCTAssertEqual(model.items[0].location, "")
        XCTAssertNil(model.errorMessage, "引けなかったことを画面のエラーにしない")
    }

    /// **地名は「その写真」に入る。** 並びが変わっても番号ではなく id で
    /// 引き直すので、待っている間に1枚外しても別の写真に入らない。
    func testPlaceGoesToItsOwnPhotoEvenIfTheListChanges() async throws {
        prepare()
        StubProtocol.respond(status: 200, body: #"{"place":"高松市"}"#)
        let model = uploadModel()
        model.items = [pending(), pending(location: "先に打った")]
        let second = model.items[1].id
        model.items.removeFirst()

        await model.fillPlaceName(for: second, lat: 34.28, lng: 133.8)

        XCTAssertEqual(model.items[0].location, "先に打った", "打ってあるものは奪わない")
    }

    /// **参加しているアルバムも投稿の行き先に出る。**
    ///
    /// `GET /albums` は自分が作ったものしか返さない（`albums.ts` が
    /// `ownerId !== userId` を落とす）ので、端末が覚えている分を足さないと
    /// 招待された人は**そのアルバムに1枚も投稿できない**。
    func testJoinedAlbumsAppearInTheUploadPicker() async throws {
        prepare()
        StubProtocol.respond(status: 200, body: #"{"albums":[{"id":"mine","title":"自分の"}]}"#)
        let model = uploadModel()

        await model.loadAlbums(joined: [
            JoinedAlbumsStore.Entry(id: "joined", title: "呼ばれた方", token: "t1"),
            // **自分が作ったものと重ならない。** 同じアルバムが2行出ると、
            // どちらを選んでも同じなのに選び直しを迫ることになる
            JoinedAlbumsStore.Entry(id: "mine", title: "自分の（控え）", token: "t2"),
        ])

        XCTAssertEqual(model.albums.map { $0.id }, ["mine", "joined"])
    }
}

/// お知らせを押したときの行き先。**空振りを作らない。**
@MainActor
final class NotificationDestinationTests: XCTestCase {

    private func notification(_ json: String) throws -> AppNotification {
        try JSONDecoder.api.decode(AppNotification.self, from: Data(json.utf8))
    }

    private func model(feed: [Photo]) -> NotificationsViewModel {
        let model = NotificationsViewModel()
        model.setFeedForTesting(feed)
        return model
    }

    private func photo(id: String) throws -> Photo {
        try JSONDecoder.api.decode(
            Photo.self, from: Data(#"{"id":"\#(id)","src":"https://x/\#(id).jpg"}"#.utf8)
        )
    }

    /// **投稿直後の写真でも押せる。**
    ///
    /// いいね・コメントの相手は必ず自分の写真。ところが公開一覧は
    /// ビルド時に固まる静的 JSON で、投稿直後はまだ載っていない
    /// （下書きに至っては一生載らない）。公開一覧しか見ていなかった頃は、
    /// **押しても何も起きない行**になっていた。
    func testLikeOnAPhotoNotYetInTheFeedStillOpens() async throws {
        let n = try notification(#"{"type":"like","photoId":"p1"}"#)
        let model = NotificationsViewModel()
        model.setFeedForTesting([])                       // 公開一覧にはまだ無い
        model.setMineForTesting([try photo(id: "p1")])    // 自分の一覧にはある

        guard case .photo(let photo, let fromPublicFeed) = model.destination(for: n) else {
            return XCTFail("押しても何も起きない")
        }
        XCTAssertEqual(photo.id, "p1")
        XCTAssertFalse(fromPublicFeed, "個別ページがまだ無いのに公開扱いしている")
    }

    func testFollowGoesToTheProfile() async throws {
        let n = try notification(#"{"type":"follow","targetUserId":"u1","byId":"u1"}"#)
        guard case .user(let id) = model(feed: []).destination(for: n) else {
            return XCTFail("プロフィールへ行かない")
        }
        XCTAssertEqual(id, "u1")
    }

    /// **退会した人のプロフィールへは行かせない。**
    func testFollowFromDeletedUserGoesNowhere() async throws {
        let n = try notification(#"{"type":"follow","targetUserId":"u1","deleted":true}"#)
        guard case .none = model(feed: []).destination(for: n) else {
            return XCTFail("退会した人へ飛ばしている")
        }
    }

    func testLikeGoesToThePhoto() async throws {
        let n = try notification(#"{"type":"like","photoId":"p1"}"#)
        guard case .photo(let photo, _) = model(feed: [try photo(id: "p1")]).destination(for: n) else {
            return XCTFail("写真へ行かない")
        }
        XCTAssertEqual(photo.id, "p1")
    }

    /// **手元の一覧に無い写真は押せないまま。** 非公開にされた／消された
    /// 写真を押して空振りさせない。
    func testLikeForAMissingPhotoGoesNowhere() async throws {
        let n = try notification(#"{"type":"like","photoId":"gone"}"#)
        guard case .none = model(feed: []).destination(for: n) else {
            return XCTFail("無い写真へ飛ばしている")
        }
    }

    /// ストーリーへの返信は行き先が無い（24時間で消えるため）。
    func testStoryReplyGoesNowhere() async throws {
        let n = try notification(#"{"type":"storyreply","photoId":"s1"}"#)
        guard case .none = model(feed: []).destination(for: n) else {
            return XCTFail("消えるものへ飛ばしている")
        }
    }

}
