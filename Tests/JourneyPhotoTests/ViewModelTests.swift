import XCTest
@testable import JourneyPhoto
import PhotosUI
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

    /// 新しい順。**`createdAt` が無い写真は末尾**（落とさない）。
    func testGalleryOrdersNewestFirstAndKeepsUndated() async {
        let model = GalleryViewModel(gallery: gallery(feed))
        await model.load()
        guard case .loaded(let photos) = model.state else {
            return XCTFail("読み込めていない: \(model.state)")
        }
        XCTAssertEqual(photos.map(\.id), ["b", "a", "c"])
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

        await model.loadPhotos(environment: env)
        await model.search("パリ", environment: env)
        XCTAssertEqual(model.shown.count, 2, "下ごしらえが効いていない")

        await service.setHidden(userIds: ["u2"], photoIds: [])
        await model.reloadPhotos(environment: env)
        await model.search("パリ", environment: env)

        XCTAssertEqual(model.shown.map(\.id), ["a"],
                       "ブロックした相手の写真が検索結果に残っている")
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

        model.refreshFollowing(["u2"])

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

    /// **いいねの数は自分で足さない。** サーバーが返した数を使う。
    func testLikeUsesServerCount() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setViewer("u1")

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
        model.setViewer("u1")
        StubProtocol.respond(status: 200, body: #"{"liked":true,"likes":5}"#)
        await model.toggleLike()
        XCTAssertEqual(model.lastLikeAnswer, 5)
        model.setViewer(nil)
        await model.toggleLike()
        XCTAssertNil(model.lastLikeAnswer)
    }

    /// 押して失敗したら、前の答えも残さない（古い答えをホームへ渡さない）
    func testFailedLikeClearsAnswer() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setViewer("u1")
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
        model.setViewer("u1")
        StubProtocol.respond(status: 200, body: #"{"liked":true,"likes":1}"#)

        async let first = model.toggleLike()
        async let second = model.toggleLike()
        _ = await (first, second)

        XCTAssertEqual(StubProtocol.requestCount, 1, "二度押しで2回投げている")
        XCTAssertTrue(model.liked)
    }

    /// 未ログインでいいねを押したら、**通信せずに**案内を出す。
    func testLikeWithoutSignInAsksToSignIn() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api(token: nil)))
        model.setViewer(nil)
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
        model.setViewer("u1")
        model.draftComment = "きれい"

        StubProtocol.respond(status: 200, body: #"{"comment":{"id":"c1","uid":"u1","name":"たろう","text":"きれい"}}"#)
        await model.postComment()

        XCTAssertEqual(model.comments.first?.text, "きれい")
        XCTAssertNil(model.commentCount, "総数を引いていないのに数を作っている")
        XCTAssertEqual(model.draftComment, "", "送ったのに入力欄が残っている")

        // 総数が取れているなら、そこに足す
        StubProtocol.respond(status: 200, body: #"{"items":[],"count":3}"#)
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
        model.setViewer(nil)
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
        model.setViewer(nil)
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

    /// 空のコメントは送らない。
    func testEmptyCommentIsNotSent() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setViewer("u1")
        model.draftComment = "   "
        await model.postComment()
        XCTAssertNil(StubProtocol.lastRequest)
    }
    /// 🔴 **人が替わったら、前の人の「サーバーの答え」を持ち越さない。**
    ///
    /// 前の人で読めた答えが残っていると、次の人の控え（`seed`）が
    /// 「サーバーの答えがある」扱いで無視される。圏外で開くと、
    /// 次の人が自分で押しているハートが白く出た（画面の流れどおり:
    /// ログアウト中の読み込みで一度 false になり、そのまま戻らない）
    func testSwitchingPeopleLetsTheNextPersonsSeedThrough() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setViewer("me")
        StubProtocol.respond(status: 200, body: #"{"liked":true,"likes":5}"#)
        await model.load()
        XCTAssertTrue(model.liked, "前提: 前の人のいいねを読めていない")

        // ログアウト（画面は `.task(id:)` で読み直す）
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        model.setViewer(nil)
        model.seed(liked: false, likes: nil)
        await model.load()
        XCTAssertFalse(model.liked)

        // 次の人でログイン。この人は押している（端末の控え）が、読み込みは圏外で落ちる
        model.setViewer("me")
        model.seed(liked: true, likes: nil)
        await model.load()
        XCTAssertTrue(model.liked, "次の人の控えが、前の人の答えの名残で無視された")
    }

    /// **ログアウト中の読み込みが走る前に次の人へ替わっても**、前の人のハートを残さない
    func testSwitchingPeopleDropsThePreviousLike() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setViewer("me")
        StubProtocol.respond(status: 200, body: #"{"liked":true,"likes":5}"#)
        await model.load()
        XCTAssertTrue(model.liked, "前提: 前の人のいいねを読めていない")

        model.setViewer(nil)
        model.setViewer("me")
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        model.seed(liked: false, likes: nil)
        await model.load()

        XCTAssertFalse(model.liked, "前の人のハートが次の人に灯っている")
    }

    /// 🔴 **ログインしたまま A から B へ直接替わっても、A の答えを持ち越さない。**
    /// ログインの有無（Bool）で比べていたので、この替わり方では
    /// 「サーバーの答え」の印が残り、B の控えが無視されて A のハートが灯っていた
    func testDirectSwitchBetweenPeopleDropsThePreviousAnswer() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setViewer("a")
        StubProtocol.respond(status: 200, body: #"{"liked":true,"likes":5}"#)
        await model.load()
        XCTAssertTrue(model.liked, "前提: A のいいねを読めていない")

        model.setViewer("b")
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        model.seed(liked: false, likes: nil)
        await model.load()

        XCTAssertFalse(model.liked, "A のハートが B に灯っている")
    }

    /// 🔴 **大きく見る画面のダブルタップは、いいね済みなら取り消さない。**
    /// 下のハートと同じ `toggleLike` を通していたので、押し済みの回は
    /// 取り消しが飛んでいた（注記は「解除はしない」）
    func testDoubleTapDoesNotUnlikeALikedPhoto() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setViewer("me")
        StubProtocol.respond(status: 200, body: #"{"liked":true,"likes":5}"#)
        await model.load()
        XCTAssertTrue(model.liked, "前提: いいね済みを読めていない")
        let before = StubProtocol.requestCount

        StubProtocol.respond(status: 200, body: #"{"liked":false,"likes":4}"#)
        await model.likeFromDoubleTap()

        XCTAssertTrue(model.liked, "ダブルタップでいいねが取り消された")
        XCTAssertEqual(StubProtocol.requestCount, before, "いいね済みなのに送っている")
    }

    /// まだなら、ダブルタップで「いいね」を送る
    func testDoubleTapLikesAnUnlikedPhoto() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setViewer("me")
        StubProtocol.respond(status: 200, body: #"{"liked":true,"likes":6}"#)
        await model.likeFromDoubleTap()
        XCTAssertTrue(model.liked)
        XCTAssertEqual(model.lastLikeAnswer, 6)
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "POST", "いいねではない口を叩いている")
    }

    /// 🔴 **圏外で開いても、いいね済みのハートを白くしない。** 読めるまでは
    /// 端末の控えと既知の数で描く（以前は `false`・`0` 始まりで控えを見なかった）
    func testOfflineDetailKeepsStoredLikeAndCount() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setViewer("me")
        model.seed(liked: true, likes: 7)
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        await model.load()
        XCTAssertTrue(model.liked, "圏外で、いいね済みのハートが白く出る")
        XCTAssertEqual(model.likes, 7, "圏外で、数が既知の数でなくなっている")
    }

    /// **数が分からないうちは描かない**（0 は「まだ無い」と読まれる）
    func testUnknownLikeCountIsNotZero() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setViewer(nil)
        model.seed(liked: false, likes: nil)
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        await model.load()
        XCTAssertNil(model.likes, "分からない数を 0 と出している")
    }

    /// **控えでサーバーの答えを上書きしない**（押した直後に画面が作り直されても）
    func testSeedDoesNotOverrideServerAnswer() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setViewer("me")
        StubProtocol.respond(status: 200, body: #"{"liked":true,"likes":3}"#)
        await model.toggleLike()
        model.seed(liked: false, likes: 1)
        XCTAssertTrue(model.liked)
        XCTAssertEqual(model.likes, 3)
    }

    /// 🔴 **届かなかった回は「答えなし」を返す**——画面はそのとき端末の控えに
    /// 写さない。写すと、押す前の見え方で本物のいいねを控えから消しうる
    func testFailedLikeIsNotReportedAsAnswered() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setViewer("me")
        model.seed(liked: true, likes: 7)
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        let answered = await model.toggleLike()
        XCTAssertFalse(answered, "届かなかったのに、控えに写してよい扱いになっている")
        XCTAssertTrue(model.liked, "届かなかったのにハートが変わっている")

        StubProtocol.respond(status: 200, body: #"{"liked":false,"likes":6}"#)
        let second = await model.toggleLike()
        XCTAssertTrue(second)
        XCTAssertFalse(model.liked)
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
        model.setViewer("u1")
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

    /// 🔴 **一部だけ上がった回は、上がった写真をライブラリの選択からも外す。**
    /// 残すと、× で失敗の1枚を外した／「追加」を開いて閉じた瞬間の選び直しで
    /// 上がった写真が「足した分」として読み直され、**二重に投稿される**
    func testPartlyPostedPhotosLeaveThePickerSelection() async throws {
        prepare()
        let presign = #"{"presignedUrl":"https://s3.example.test/put","key":"uploads/u/1.jpg","publicUrl":"https://site.example.test/uploads/u/1.jpg","contentType":"image/jpeg"}"#
        let saved = #"{"success":true}"#
        // a は上がる・b は置き場所をもらえずに落ちる・c は上がる
        StubProtocol.respondInOrder([
            (200, presign), (200, ""), (200, saved),
            (500, #"{"error":"だめでした"}"#),
            (200, presign), (200, ""), (200, saved),
        ])
        let model = uploadModel()
        let keys = ["a", "b", "c"].map { PhotosPickerItem(itemIdentifier: $0) }
        model.items = keys.map { key in
            var photo = pending()
            photo.pickerItem = key
            return photo
        }
        model.pickerItems = keys

        await model.submit()

        XCTAssertEqual(model.items.map(\.pickerItem), [keys[1]], "失敗した b だけが残る")
        XCTAssertEqual(model.pickerItems, [keys[1]], "上がった a・c が選択に残っている（選び直しで二重に投稿される）")
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
