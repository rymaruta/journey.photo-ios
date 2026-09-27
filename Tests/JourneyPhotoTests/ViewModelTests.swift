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
        XCTAssertEqual(model.actionMessage, "取得に失敗しました")
        XCTAssertEqual(model.photos.map(\.id), ["p1"], "読めていた写真を捨てている")

        serve(photos: 200)
        await model.load()
        XCTAssertNil(model.actionMessage, "読めたのに失敗の知らせが残っている")
    }

    /// **読み直しで写真が落ちた回は、写真と揃わないプロフィールで上書きしない**（891fb04 のレビュー）。
    /// 新しいピンの印と古い並びが食い違う。
    ///
    /// ⚠️ 落とすのは**写真の口だけ**。プロフィールの口を落とすと、同時に走っている写真の
    /// `async let` の取り消しがスタブ（`stopLoading` が空）の上で返らず、テストがときどき止まる
    func testReloadWithOnlyTheProfileKeepsThePreviousPins() async {
        prepare()
        StubProtocol.respond(path: "/user/profile", status: 200, body: #"{"userId":"a","pinnedPhotoIds":["p1"]}"#)
        StubProtocol.respond(path: "/user/photos", status: 200, body: #"[{"id":"p1","src":"/uploads/p1.jpg"}]"#)
        let model = MyPageViewModel(api: api())
        await model.load()
        XCTAssertEqual(model.pinnedIds, ["p1"])

        StubProtocol.reset()
        StubProtocol.respond(path: "/user/profile", status: 200, body: #"{"userId":"a","pinnedPhotoIds":["p9"]}"#)
        StubProtocol.respond(path: "/user/photos", status: 500, body: #"{"error":"取得に失敗しました"}"#)
        await model.load()
        XCTAssertEqual(model.pinnedIds, ["p1"], "写真と揃わないプロフィールでピンを上書きしている")
        XCTAssertEqual(model.profile?.pinnedPhotoIds, ["p1"])
        // 読み直しの失敗でも戻る・一覧に添える（写真の口が落ちる向きなのでスタブで止まらない）
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.actionMessage, "取得に失敗しました")
    }

    /// **読み直しで写真を待つ間に留め外ししても、古いプロフィールのピンに巻き戻さない**（157b9ff のレビュー）
    func testPinChangedDuringReloadIsKept() async {
        prepare()
        StubProtocol.respond(path: "/user/profile", status: 200, body: #"{"userId":"a","pinnedPhotoIds":[]}"#)
        StubProtocol.respond(path: "/user/photos", status: 200, body: #"[{"id":"p1","src":"/uploads/p1.jpg"}]"#)
        let model = MyPageViewModel(api: api())
        await model.load()
        XCTAssertEqual(model.pinnedIds, [])

        // 読み直し: プロフィールはすぐ（ピン無し）、写真は遅れて届く
        StubProtocol.reset()
        StubProtocol.respond(path: "/user/profile", status: 200, body: #"{"userId":"a","pinnedPhotoIds":[]}"#)
        StubProtocol.respond(path: "/user/photos", status: 200,
                             body: #"[{"id":"p1","src":"/uploads/p1.jpg"}]"#, delay: 0.3)
        let reload = Task { await model.load() }
        for _ in 0..<2000 {
            if StubProtocol.requestCount >= 2 { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        // 写真を待っている間に留める（PUT も同じ道。ここからの答えはピン有り）
        StubProtocol.reset()
        StubProtocol.respond(path: "/user/profile", status: 200, body: #"{"userId":"a","pinnedPhotoIds":["p1"]}"#)
        await model.setPinned("p1", pinned: true)
        XCTAssertEqual(model.pinnedIds, ["p1"])
        await reload.value

        XCTAssertEqual(model.pinnedIds, ["p1"], "写真を待つ間に留めたピンを巻き戻している")
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
        XCTAssertNil(model.actionMessage)
        XCTAssertEqual(model.profile?.userId, "a", "初回はプロフィールだけでも見出しに出す")
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

    /// 🔴 **読み込み前・取れなかった回に 0 と出さない。** 一覧から来た数で始める
    func testLikesStartFromTheListCount() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()), initialLikes: 7)
        XCTAssertEqual(model.likes, 7)
        StubProtocol.respond(status: 500, body: "{}")
        await model.load()
        XCTAssertEqual(model.likes, 7, "取れなかった回に一覧の数を捨てている")
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

        async let first: Void = model.toggleLike()
        async let second: Void = model.toggleLike()
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
