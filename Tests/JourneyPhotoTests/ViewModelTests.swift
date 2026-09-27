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

    /// 🔴 **先に始めた読み込みが後から戻っても、後の答えを上書きしない。**
    ///
    /// 人が替わった直後は「見せない」の読み直し（`hidden.revision`）と
    /// 人の替わりの読み直しが同時に走る。先の方は前の人向けの控えを
    /// 読んでいることがあり、それが後に戻ると前の人の写真が残る
    func testGalleryOlderLoadDoesNotOverwriteNewerOne() async throws {
        let service = gallery(feed)
        let gate = Gate()
        let calls = CallCounter()
        let older = try JSONDecoder.api.decode(Photo.self, from: Data(
            #"{"id":"older","src":"https://x/o.jpg","userId":"u9","audience":"followers"}"#.utf8))
        let newer = try JSONDecoder.api.decode(Photo.self, from: Data(
            #"{"id":"newer","src":"https://x/n.jpg","userId":"u9","audience":"followers"}"#.utf8))
        await service.setRestrictedLoader(owner: "A") {
            if await calls.next() == 1 {
                await gate.wait()
                return [older]
            }
            return [newer]
        }
        let model = GalleryViewModel(gallery: service)
        let first = Task { await model.load() }
        await gate.untilWaiting()
        await model.load()
        await gate.open()
        await first.value

        guard case .loaded(let photos) = model.state else { return XCTFail("状態が違う") }
        XCTAssertTrue(photos.contains { $0.id == "newer" }, "後の読み込みの答えが出ていない")
        XCTAssertFalse(photos.contains { $0.id == "older" }, "先に始めた読み込みの答えで上書きされた")
    }

    /// 🔴 **人が替わったら、前の人のために始まった回の答えは入れない**
    /// （探すの `loadPhotos(userId:)` と同じ）。「先に始めた回の答えを残す」は
    /// 同じ人の間だけ——次の人の回より先に戻ると、前の人の「見せない」・
    /// 限定公開の取り口で読んだ写真が画面に移っていた
    func testGallerySwitchingPeopleDropsThePreviousPersonsLoad() async throws {
        let service = gallery(feed)
        let gate = Gate()
        let older = try JSONDecoder.api.decode(Photo.self, from: Data(
            #"{"id":"older","src":"https://x/o.jpg","userId":"u9","audience":"followers"}"#.utf8))
        await service.setRestrictedLoader(owner: "A") {
            await gate.wait()
            return [older]
        }
        let model = GalleryViewModel(gallery: service)
        model.switchViewer(to: "A")
        let first = Task { await model.load() }
        await gate.untilWaiting()

        model.switchViewer(to: "B")
        await gate.open()
        await first.value

        if case .loaded(let photos) = model.state {
            XCTAssertFalse(photos.contains { $0.id == "older" }, "前の人の回の答えが画面に移った")
        }
        XCTAssertEqual(model.state, .loading, "前の人の回の答えで状態を書いた")
    }

    /// 🔴 **人が替わったら、手元の一覧（前の人の限定公開を含む）も捨てる。**
    /// 回を古くするだけでは `all` が残り、次の人の読み込みが落ちたあとに
    /// カテゴリ・範囲・フィード・並び・文字・タグを触ると、前の人の写真が画面に戻っていた
    func testGallerySwitchingPeopleForgetsThePreviousPersonsList() async throws {
        let service = gallery(feed)
        let secret = try JSONDecoder.api.decode(Photo.self, from: Data(
            #"{"id":"secret","src":"https://x/s.jpg","userId":"u9","audience":"followers","category":"風景","tags":["sunset"]}"#.utf8))
        await service.setRestrictedLoader(owner: "A") { [secret] }
        let model = GalleryViewModel(gallery: service)
        model.switchViewer(to: "A")
        await model.load()
        guard case .loaded(let before) = model.state, before.contains(where: { $0.id == "secret" }) else {
            return XCTFail("前提: A の一覧に限定公開が入っていない: \(model.state)")
        }

        // B に替わり、B の読み込みは落ちる（控えも無い）
        model.switchViewer(to: "B")
        StubProtocol.respond(status: 500, body: "{}")
        model.use(gallery: PublicGalleryService(
            url: URL(string: "https://site.example.test/app/data/photos.json")!,
            session: session,
            snapshot: PhotoSnapshotStore(fileName: UUID().uuidString)
        ))
        await model.load()
        guard case .failed = model.state else { return XCTFail("前提: B の読み込みが落ちていない: \(model.state)") }

        func shown() -> [String] {
            if case .loaded(let photos) = model.state { return photos.map(\.id) }
            return []
        }
        model.select(category: "風景")
        XCTAssertFalse(shown().contains("secret"), "カテゴリを押したら前の人の写真が戻った")
        model.select(category: nil)
        XCTAssertFalse(shown().contains("secret"), "カテゴリを外したら前の人の写真が戻った")
        model.select(feed: .latest, viewerId: "B")
        XCTAssertFalse(shown().contains("secret"), "フィードを替えたら前の人の写真が戻った")
        model.select(sort: .popular)
        XCTAssertFalse(shown().contains("secret"), "並びを替えたら前の人の写真が戻った")
        model.query = "s"
        XCTAssertFalse(shown().contains("secret"), "文字を打ったら前の人の写真が戻った")
        XCTAssertTrue(model.categories.isEmpty, "前の人の一覧から作ったチップが残っている")
        XCTAssertTrue(model.tags.isEmpty, "タグの候補が前の人の一覧を読んでいる")
        XCTAssertTrue(model.allPhotosForTheme.isEmpty, "今日のテーマの背景が前の人の一覧を読んでいる")
    }

    /// **未ログイン → ログイン済み（起動時の確認中 → A）では一覧を捨てない。**
    /// 未ログインの一覧は公開分だけ。捨てると起動のたびに読み込み中へ戻っていた
    func testGallerySignInFromNobodyKeepsTheShownList() async throws {
        let model = GalleryViewModel(gallery: gallery(feed))
        model.switchViewer(to: nil)
        await model.load()
        guard case .loaded(let before) = model.state, !before.isEmpty else {
            return XCTFail("前提: 未ログインの一覧が出ていない: \(model.state)")
        }
        model.switchViewer(to: "A")
        guard case .loaded(let after) = model.state else {
            return XCTFail("未ログイン → A で一覧を捨てて読み込み中に戻った: \(model.state)")
        }
        XCTAssertEqual(after.map(\.id), before.map(\.id))
    }

    /// **同じ人のまま画面に戻っただけでは捨てない**（`.task` は出入りのたびに走る）
    func testGallerySameViewerAgainKeepsTheRunningLoad() async throws {
        let service = gallery(feed)
        let gate = Gate()
        await service.setRestrictedLoader(owner: "A") {
            await gate.wait()
            return []
        }
        let model = GalleryViewModel(gallery: service)
        model.switchViewer(to: "A")
        let first = Task { await model.load() }
        await gate.untilWaiting()
        model.switchViewer(to: "A")
        await gate.open()
        await first.value

        guard case .loaded(let photos) = model.state else { return XCTFail("同じ人の回を捨てた: \(model.state)") }
        XCTAssertEqual(photos.count, 3)
    }

    /// 🔴 **後から始めた回が落ちても、先に成功した回の答えを捨てない。**
    /// 古い回を捨てるのは、より新しい回が画面に移し終えたときだけ
    func testGalleryNewerFailureKeepsTheOlderSuccess() async {
        prepare()
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: feed, delay: 0.3)
        let model = GalleryViewModel(gallery: PublicGalleryService(
            url: URL(string: "https://site.example.test/app/data/photos.json")!,
            session: session,
            snapshot: PhotoSnapshotStore(fileName: UUID().uuidString)
        ))
        let first = Task { await model.load() }
        while StubProtocol.requestCount < 1 { try? await Task.sleep(nanoseconds: 5_000_000) }

        // 先の回の返事を待っている間に、後の回が圏外で落ちる
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        await model.load()
        await first.value

        guard case .loaded(let photos) = model.state else {
            return XCTFail("先に成功した回の答えを捨てて失敗のまま: \(model.state)")
        }
        XCTAssertEqual(photos.count, 3)
    }

    /// 🔴 **引き下げ更新の最中に始まった読み込みが、60秒の控えで引き下げの答えを負かさない。**
    /// 控えを使う読み込みはすぐ戻って「新しい回」として画面に移り、あとから戻った
    /// 引き下げの答えは「古い回」として捨てられていた
    func testGalleryPullToRefreshIsNotBeatenByACachedLoad() async throws {
        let service = gallery(feed)
        let gate = Gate()
        let calls = CallCounter()
        let stale = try JSONDecoder.api.decode(Photo.self, from: Data(
            #"{"id":"stale","src":"https://x/s.jpg","userId":"u9","audience":"followers"}"#.utf8))
        let fresh = try JSONDecoder.api.decode(Photo.self, from: Data(
            #"{"id":"fresh","src":"https://x/f.jpg","userId":"u9","audience":"followers"}"#.utf8))
        await service.setRestrictedLoader(owner: "A") {
            if await calls.next() == 1 { return [stale] }
            await gate.wait()
            return [fresh]
        }
        let model = GalleryViewModel(gallery: service)
        await model.load()
        guard case .loaded(let before) = model.state, before.contains(where: { $0.id == "stale" }) else {
            return XCTFail("前提: 控えに古い答えが入っていない")
        }

        let refresh = Task { await model.load(force: true) }
        await gate.untilWaiting()
        // 引き下げの最中に、控えを使う読み込み（「見せない」の読み直しなど）が始まる
        let cached = Task { await model.load() }
        try await Task.sleep(nanoseconds: 50_000_000)
        await gate.open()
        await refresh.value
        await cached.value

        guard case .loaded(let photos) = model.state else { return XCTFail("状態が違う") }
        XCTAssertTrue(photos.contains { $0.id == "fresh" }, "引き下げの答えが出ていない")
        XCTAssertFalse(photos.contains { $0.id == "stale" }, "控えの古い答えで引き下げの答えが負けた")
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

        await model.loadPhotos(environment: env, userId: nil)
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

    /// 🔴 **ログアウトしたら、前の人の名前・アイコン・フォロー数を手放す。**
    /// 以前は写真とピン留めだけ捨てていて、次の人の画面に前の人の
    /// 名前とフォロー数が出ていた
    func testSignOutForgetsThePreviousUsersProfile() async {
        prepare()
        StubProtocol.respond(path: "/user/profile", status: 200,
                             body: #"{"userId":"a","displayName":"前の人","pinnedPhotoIds":[]}"#)
        StubProtocol.respond(path: "/user/photos", status: 200,
                             body: #"[{"id":"p1","src":"/uploads/p1.jpg"}]"#)
        StubProtocol.respond(path: "/users/a/follow", status: 200, body: #"{"followers":7,"following":3}"#)
        let model = MyPageViewModel(api: api())
        await model.load(for: "a")
        XCTAssertEqual(model.profile?.displayName, "前の人", "前提: 読めていない")
        XCTAssertEqual(model.followers, 7, "前提: 数を読めていない")

        await model.load(for: nil)

        XCTAssertNil(model.profile, "前の人の名前・アイコンが残っている")
        XCTAssertEqual(model.followers, 0, "前の人のフォロワー数が残っている")
        XCTAssertEqual(model.following, 0, "前の人のフォロー数が残っている")
        XCTAssertTrue(model.photos.isEmpty)
    }

    /// 🔴 **前の人の読み込み中に人が替わっても、次の人のぶんを読む。**
    /// 以前は `guard !isLoading` で次の人の読み込みが飛ばされ、
    /// 遅れて戻った前の人の答えがそのまま入っていた
    func testSwitchingPeopleMidLoadLoadsTheNewPerson() async {
        prepare()
        StubProtocol.respond(path: "/user/profile", status: 200,
                             body: #"{"userId":"a","displayName":"前の人"}"#, delay: 0.4)
        StubProtocol.respond(path: "/user/photos", status: 200,
                             body: #"[{"id":"a1","src":"/uploads/a1.jpg"}]"#, delay: 0.4)
        StubProtocol.respond(path: "/users/a/follow", status: 200, body: #"{"followers":7,"following":3}"#)
        let model = MyPageViewModel(api: api())
        let first = Task { await model.load(for: "a") }
        while StubProtocol.requestCount < 2 { try? await Task.sleep(nanoseconds: 5_000_000) }

        // A の返事を待っている間に B へ替わる
        StubProtocol.reset()
        StubProtocol.respond(path: "/user/profile", status: 200,
                             body: #"{"userId":"b","displayName":"次の人"}"#)
        StubProtocol.respond(path: "/user/photos", status: 200,
                             body: #"[{"id":"b1","src":"/uploads/b1.jpg"}]"#)
        StubProtocol.respond(path: "/users/b/follow", status: 200, body: #"{"followers":1,"following":2}"#)
        await model.load(for: "b")
        await first.value

        XCTAssertEqual(model.profile?.displayName, "次の人", "次の人の読み込みが飛ばされた／前の人の答えで上書きされた")
        XCTAssertEqual(model.photos.map(\.id), ["b1"], "前の人の写真が入っている")
        XCTAssertEqual(model.followers, 1)
        XCTAssertFalse(model.isLoading, "読み終えたのに読み込み中のまま")
    }

    /// 🔴 **人が替わった合図（`onChange`）の時点で、前の人のぶんを消す。**
    /// `.task(id:)` の読み込みを待つと、上に積んだ画面から戻った最初の描画で
    /// 前の人の名前・写真（下書きを含む）が1描画ぶん映る
    func testSwitchViewerForgetsThePreviousPersonAtOnce() async {
        prepare()
        StubProtocol.respond(path: "/user/profile", status: 200,
                             body: #"{"userId":"a","displayName":"前の人"}"#)
        StubProtocol.respond(path: "/user/photos", status: 200,
                             body: #"[{"id":"a1","src":"/uploads/a1.jpg","published":false}]"#)
        StubProtocol.respond(path: "/users/a/follow", status: 200, body: #"{"followers":7,"following":3}"#)
        let model = MyPageViewModel(api: api())
        await model.load(for: "a")
        XCTAssertEqual(model.profile?.displayName, "前の人", "前提: 読めていない")

        model.switchViewer(to: "b")

        XCTAssertNil(model.profile, "前の人の名前・アイコンが次の人の最初の描画に残る")
        XCTAssertTrue(model.photos.isEmpty, "前の人の写真（下書き）が残る")
        XCTAssertEqual(model.followers, 0)
    }

    /// **`.task(id:)` が先に走っても、あとから来た合図で次の人の読み込みを捨てない。**
    /// 合図のたびに捨てると、始まったばかりの次の人の答えが世代違いで捨てられる
    func testSwitchViewerAfterLoadStartedKeepsTheNewPersonsLoad() async {
        prepare()
        StubProtocol.respond(path: "/user/profile", status: 200,
                             body: #"{"userId":"b","displayName":"次の人"}"#, delay: 0.3)
        StubProtocol.respond(path: "/user/photos", status: 200,
                             body: #"[{"id":"b1","src":"/uploads/b1.jpg"}]"#, delay: 0.3)
        StubProtocol.respond(path: "/users/b/follow", status: 200, body: #"{"followers":1,"following":2}"#)
        let model = MyPageViewModel(api: api())
        let loading = Task { await model.load(for: "b") }
        while StubProtocol.requestCount < 2 { try? await Task.sleep(nanoseconds: 5_000_000) }

        model.switchViewer(to: "b")
        await loading.value

        XCTAssertEqual(model.profile?.displayName, "次の人", "同じ人の合図で読み込み中の答えを捨てた")
        XCTAssertEqual(model.photos.map(\.id), ["b1"])
        XCTAssertFalse(model.isLoading)
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
        model.setViewer("me")

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

    /// 未ログインで押した回も、前の答えを残さない（呼び出し側が「いま」の
    /// 答えとしてホームへ渡し直すため）
    func testSignedOutPressClearsAnswer() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setViewer("me")
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
        model.setViewer("me")
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
        model.setViewer("me")
        StubProtocol.respond(status: 200, body: #"{"liked":true,"likes":1}"#)

        async let first: Bool = model.toggleLike()
        async let second: Bool = model.toggleLike()
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
        model.setViewer("me")
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
        model.setViewer("me")
        model.draftComment = "   "
        await model.postComment()
        XCTAssertNil(StubProtocol.lastRequest)
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
        model.setViewer("me")
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

/// 何回目の呼び出しかを数える（最初の1回だけ待たせる、のような試験用）
actor CallCounter {
    private var count = 0
    func next() -> Int {
        count += 1
        return count
    }
}
