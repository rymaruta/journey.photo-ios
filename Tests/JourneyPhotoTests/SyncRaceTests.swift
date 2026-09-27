import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 読み込みの答えが、その間に押した操作を後から上書きしないか
/// （バグ探し 2026-09-27 の M-5・L-1・L-11）。
@MainActor
final class SyncRaceTests: XCTestCase {

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    override func tearDown() async throws {
        StubProtocol.reset()
        AppConfig.testOverrides = nil
        try await super.tearDown()
    }

    // MARK: - 起動・ログイン直後の同期（M-5）

    /// 🔴 **同期で取りに行っている間に押したいいねを、押す前の一覧で消さない**
    func testLikeSyncKeepsWhatWasPressedWhileFetching() async {
        let likes = FavoritesStore(defaults: defaults())
        likes.use(userId: "u1")
        let mark = likes.syncMark
        likes.set("押した", favorite: true)
        likes.set("外した", favorite: false)
        likes.replace(with: ["前から", "外した"], for: "u1", since: mark)
        XCTAssertEqual(likes.ids, ["前から", "押した"], "取りに行っている間の操作を上書きしている")
    }

    /// **印より前の控えは今までどおり入れ替える**（保存しただけの古い id を落とす）
    func testLikeSyncStillReplacesWhatCameBeforeTheMark() async {
        let likes = FavoritesStore(defaults: defaults())
        likes.use(userId: "u1")
        likes.set("保存しただけの古い写真", favorite: true)
        let mark = likes.syncMark
        likes.replace(with: ["本当にいいねした写真"], for: "u1", since: mark)
        XCTAssertEqual(likes.ids, ["本当にいいねした写真"])
    }

    /// 🔴 **前の人の同期の答えを、次にログインした人の控えに書かない**
    func testLikeSyncForAnotherPersonIsDropped() async {
        let likes = FavoritesStore(defaults: defaults())
        likes.use(userId: "a")
        let mark = likes.syncMark
        likes.use(userId: "b")
        likes.set("b の写真", favorite: true)
        // 持ち主の照合（`for:`）は通して、**印だけで**弾かれることを見る
        likes.replace(with: ["a の写真"], for: "b", since: mark)
        XCTAssertEqual(likes.ids, ["b の写真"], "前の人の一覧を書いている")
    }

    func testSaveSyncKeepsWhatWasPressedWhileFetching() async {
        let saves = SavedPhotosStore(defaults: defaults())
        saves.use(userId: "u1")
        let mark = saves.syncMark
        saves.set("押した", saved: true)
        saves.set("外した", saved: false)
        saves.replace(with: ["前から", "外した"], for: "u1", since: mark)
        XCTAssertEqual(saves.ids, ["前から", "押した"], "取りに行っている間の保存を上書きしている")
    }

    /// 🔴 **起動直後にブロックした人を、押す前のブロック一覧で戻さない**（審査 1.2）
    func testBlockSyncKeepsWhatWasBlockedWhileFetching() async {
        let hidden = ModerationStore(defaults: defaults())
        hidden.use(userId: "u1")
        hidden.block("解除する人")
        let mark = hidden.blockSyncMark
        hidden.block("いまブロックした人")
        hidden.unblock("解除する人")
        hidden.replaceBlocked(with: ["前から", "解除する人"], for: "u1", since: mark)
        XCTAssertEqual(hidden.blockedUserIds, ["前から", "いまブロックした人"],
                       "取りに行っている間のブロック・解除を上書きしている")
    }

    /// **同じ人を待っている間にブロックして解除した**（元に戻した）ら、古い一覧でも戻らない
    func testBlockThenUnblockWhileFetchingStaysUnblocked() async {
        let hidden = ModerationStore(defaults: defaults())
        hidden.use(userId: "u1")
        let fetch = hidden.beginBlockFetch()
        hidden.block("x")
        hidden.unblock("x")
        hidden.replaceBlocked(with: ["x"], for: "u1", fetch: fetch)
        XCTAssertFalse(hidden.blockedUserIds.contains("x"), "解除した人が古い一覧で戻った")
    }

    /// 🔴 **先に始まった取得の答えが後から返っても、後に始まった取得の答えを上書きしない**
    /// （起動時の同期の待ち中に「ブロックした人」の画面が新しい一覧を書き、その後に
    /// 起動時の同期が古い一覧で戻していた。手元で押していないので印では見分けられない）
    func testOlderFetchDoesNotOverwriteANewerOne() async {
        let hidden = ModerationStore(defaults: defaults())
        hidden.use(userId: "u1")
        let startup = hidden.beginBlockFetch()
        let screen = hidden.beginBlockFetch()
        hidden.replaceBlocked(with: [], for: "u1", fetch: screen)          // 別の端末で解除済み
        hidden.replaceBlocked(with: ["y"], for: "u1", fetch: startup)     // 古い一覧が後から
        XCTAssertTrue(hidden.blockedUserIds.isEmpty, "古い取得が新しい一覧を上書きした")
    }

    /// **通報の答えを待つ間に人が替わったら、次の人（未ログイン）の控えに書かない**
    func testReportAnsweredAfterAUserChangeIsNotKept() async {
        let hidden = ModerationStore(defaults: defaults())
        hidden.use(userId: "u1")
        let owner = hidden.owner
        hidden.use(userId: nil)                 // 待っている間に期限切れで未ログインに
        hidden.markReported("p1", for: owner)
        XCTAssertTrue(hidden.reportedPhotoIds.isEmpty, "未ログインの控えに通報が入った")
        hidden.use(userId: "u1")
        hidden.markReported("p1", for: hidden.owner)
        XCTAssertEqual(hidden.reportedPhotoIds, ["p1"])
    }

    func testBlockSyncForAnotherPersonIsDropped() async {
        let hidden = ModerationStore(defaults: defaults())
        hidden.use(userId: "a")
        let mark = hidden.blockSyncMark
        hidden.use(userId: "b")
        // 持ち主の照合（`for:`）は通して、**印だけで**弾かれることを見る
        hidden.replaceBlocked(with: ["a がブロックした人"], for: "b", since: mark)
        XCTAssertTrue(hidden.blockedUserIds.isEmpty, "前の人のブロック一覧を書いている")
    }

    /// 🔴 **前の人の送信の答えが、人が替わった後に届いても次の人の控えに書かない。**
    /// 書くと「同期の間に押した分」（`LocalEdits`）として次の人の同期の入れ替えでも
    /// 消えずに残っていた（G2 と C の併合で生まれた穴）
    func testLateAnswerForThePreviousPersonIsNotKeptBySync() async {
        let likes = FavoritesStore(defaults: defaults())
        let saves = SavedPhotosStore(defaults: defaults())
        let hidden = ModerationStore(defaults: defaults())
        likes.use(userId: "a")
        saves.use(userId: "a")
        hidden.use(userId: "a")
        // a が押して、答えを待っている
        let likeOwner = likes.owner
        let saveOwner = saves.owner
        let blockOwner = hidden.owner
        // その間にログアウトして b がログインし、b の同期が始まる
        for id in [nil, "b"] as [String?] {
            likes.use(userId: id)
            saves.use(userId: id)
            hidden.use(userId: id)
        }
        let likesMark = likes.syncMark
        let savesMark = saves.syncMark
        let blocksMark = hidden.blockSyncMark
        // a の答えが届く
        likes.set("a の写真", favorite: true, for: likeOwner)
        saves.set("a の保存", saved: true, for: saveOwner)
        hidden.block("a がブロックした人", for: blockOwner)
        // b の同期が返る
        likes.replace(with: ["b の写真"], for: "b", since: likesMark)
        saves.replace(with: ["b の保存"], for: "b", since: savesMark)
        hidden.replaceBlocked(with: [], for: "b", since: blocksMark)
        XCTAssertEqual(likes.ids, ["b の写真"], "前の人のいいねが次の人の控えに残っている")
        XCTAssertEqual(saves.ids, ["b の保存"], "前の人の保存が次の人の控えに残っている")
        XCTAssertTrue(hidden.blockedUserIds.isEmpty, "前の人のブロックで次の人の画面から人が消える")
    }

    /// 同じ人の答えは今までどおり書く（押している間の同期でも残る）
    func testAnswerForTheSamePersonIsKept() async {
        let likes = FavoritesStore(defaults: defaults())
        likes.use(userId: "b")
        let owner = likes.owner
        let mark = likes.syncMark
        likes.set("押した", favorite: true, for: owner)
        likes.replace(with: ["前から"], for: "b", since: mark)
        XCTAssertEqual(likes.ids, ["前から", "押した"])
    }

    // MARK: - 写真の詳細: 開いた直後のいいね（L-1）

    /// `gates` を渡すと、その道の要求だけ手前で止める（「この口だけ遅い」）
    private func stubbedSocial(gates: PathGates? = nil) -> SocialService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        StubProtocol.reset()
        AppConfig.testOverrides = [
            "JPEnvironmentName": "staging",
            "JPSiteBaseURL": "https://site.example.test",
            "JPUserApiBaseURL": "https://api.example.test",
            "JPCognitoUserPoolId": "pool",
            "JPCognitoClientId": "client",
            "JPCognitoRegion": "ap-northeast-1",
        ]
        return SocialService(api: APIClient(
            baseURL: URL(string: "https://api.example.test")!,
            tokenProvider: StubTokenProvider(token: "t"), session: session,
            beforeRequest: gates.map { gates in { (request: URLRequest) async in await gates.wait(for: request) } }))
    }

    /// 🔴 **束の隣へ送った後に前の1枚の答えが届いても、今の1枚の読み込みは捨てない**
    /// （9abb5ea のレビュー: 押した写真を区別せずに数えていた）
    func testLikeAnswerForThePreviousPhotoDoesNotDiscardTheNextLoad() async {
        // 押したいいねの答え（先に届く）と、今の1枚の「自分が押しているか」（後に届く）を止めておく
        let liking = Gate()
        let mine = Gate()
        let social = stubbedSocial(gates: PathGates(["POST /photos/p1/like": liking, "/user/likes/p2": mine]))
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"liked":true,"likes":8}"#)
        StubProtocol.respond(path: "/user/likes/p2", status: 200, body: #"{"liked":true}"#)
        StubProtocol.respond(path: "/photos/p2/comments", status: 200, body: #"{"items":[],"count":0}"#)
        StubProtocol.respond(path: "/photos/p2/like", status: 200, body: #"{"likes":9}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: social, initialLikes: 7)
        model.setSignedIn(true)

        let pressed = Task { await model.toggleLike() }
        await liking.untilWaiting()
        model.show(photoId: "p2", initialLikes: 3, liked: false)
        let loading = Task { await model.load() }
        await mine.untilWaiting()
        await liking.open()                 // 前の1枚の答えが先に届く
        _ = await pressed.value
        await mine.open()                   // そのあと今の1枚の答え
        await loading.value
        XCTAssertTrue(model.liked, "前の1枚の答えのせいで、今の1枚のハートを読み捨てている")
        XCTAssertEqual(model.likes, 9, "前の1枚の答えのせいで、今の1枚の数を読み捨てている")
    }

    /// **断られたいいねは数えない**（サーバーは変わっていないので、読み込みの答えが正しい）
    func testRejectedLikeDoesNotDiscardTheLoad() async {
        // 「自分が押しているか」の答えを止めておき、その間に押す
        let mine = Gate()
        let social = stubbedSocial(gates: PathGates(["/user/likes/p1": mine]))
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":true}"#)
        StubProtocol.respond(path: "/photos/p1/comments", status: 200, body: #"{"items":[],"count":0}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 500, body: "{}")
        let model = PhotoDetailViewModel(photoId: "p1", social: social, initialLikes: 5)
        model.setSignedIn(true)

        let loading = Task { await model.load() }
        await mine.untilWaiting()
        _ = await model.toggleLike()
        await mine.open()
        await loading.value
        XCTAssertTrue(model.liked, "断られた回に、サーバーの答え（押してある）を捨てている")
    }

    /// 🔴 **開いた直後に押したいいねを、先に出ていた読み込みの答えで戻さない**
    func testDetailLoadDoesNotUndoALikePressedWhileLoading() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        StubProtocol.reset()
        AppConfig.testOverrides = [
            "JPEnvironmentName": "staging",
            "JPSiteBaseURL": "https://site.example.test",
            "JPUserApiBaseURL": "https://api.example.test",
            "JPCognitoUserPoolId": "pool",
            "JPCognitoClientId": "client",
            "JPCognitoRegion": "ap-northeast-1",
        ]
        // 「自分が押しているか」は押す前の答え（押していない）が遅れて届く（止めておく）
        let mine = Gate()
        let gates = PathGates(["/user/likes/p1": mine])
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session,
                            beforeRequest: { (request: URLRequest) async in await gates.wait(for: request) })
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":false}"#)
        StubProtocol.respond(path: "/photos/p1/comments", status: 200, body: #"{"items":[],"count":0}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"liked":true,"likes":6}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api), initialLikes: 5)
        model.setSignedIn(true)

        let loading = Task { await model.load() }
        await mine.untilWaiting()
        _ = await model.toggleLike()
        XCTAssertTrue(model.liked, "前提: 押した答えが入っていない")
        await mine.open()
        await loading.value
        XCTAssertTrue(model.liked, "押す前の読み込みの答えでハートを戻している")
        XCTAssertEqual(model.likes, 6)
    }

    // MARK: - ホームのカードの連打（L-11）

    /// 🔴 **送っている印はカードの外に持つ**（作り直されたカードでも二度目を止める）
    func testLikeSendingMarkIsSharedAcrossCards() async {
        let store = LikeCountStore()
        XCTAssertTrue(store.beginSending("p1"))
        XCTAssertFalse(store.beginSending("p1"), "答えを待っている間に二度目を通している")
        XCTAssertTrue(store.beginSending("p2"), "別の写真まで止めている")
        store.endSending("p1")
        XCTAssertTrue(store.beginSending("p1"), "答えの後も押せない")
    }
}
