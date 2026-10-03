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

    // MARK: - 画面をまたいだ送信中の印

    /// 🔴 **ホーム（や大きく見る画面）で送っている写真を、詳細で押しても送らない。**
    /// 以前は詳細が自分の `isLiking` しか見ず、逆向きが同時に飛んでいた
    func testDetailDoesNotSendWhileAnotherScreenIsSendingThatPhoto() async {
        let social = stubbedSocial()
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"liked":true,"likes":6}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: social, initialLikes: 5)
        model.setSignedIn(true)
        let store = LikeCountStore()
        XCTAssertTrue(store.beginSending("p1"), "前提: ホームが送り始めた")

        let answer = await model.toggleLike(gate: store)
        XCTAssertNil(answer, "別の画面が送っている写真を、詳細からも送っている")
        XCTAssertEqual(StubProtocol.requestCount, 0, "別の画面が送っている写真を、詳細からも送っている")
        XCTAssertTrue(store.isSending("p1"), "他の画面の印を詳細が外している")
    }

    /// 🔴 **詳細で送っている間は、他の画面（ホームのカード・大きく見る画面）が送れない。**
    /// 答えが来たら印を外す（外さないと二度と押せない）
    func testDetailHoldsTheSharedMarkWhileSending() async {
        let liking = Gate()
        let social = stubbedSocial(gates: PathGates(["POST /photos/p1/like": liking]))
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"liked":true,"likes":6}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: social, initialLikes: 5)
        model.setSignedIn(true)
        let store = LikeCountStore()

        let pressed = Task { await model.toggleLike(gate: store) }
        await liking.untilWaiting()
        XCTAssertFalse(store.beginSending("p1"), "詳細が送っている間に、他の画面から逆向きを送れる")
        XCTAssertTrue(store.beginSending("p2"), "別の写真まで止めている")
        await liking.open()
        let answer = await pressed.value
        XCTAssertEqual(answer?.liked, true)
        XCTAssertFalse(store.isSending("p1"), "答えの後も印が残り、二度と押せない")
    }

    /// 届かなかった回も印を外す
    func testDetailReleasesTheSharedMarkOnFailure() async {
        let social = stubbedSocial()
        StubProtocol.respond(path: "/photos/p1/like", status: 500, body: "{}")
        let model = PhotoDetailViewModel(photoId: "p1", social: social, initialLikes: 5)
        model.setSignedIn(true)
        let store = LikeCountStore()
        _ = await model.toggleLike(gate: store)
        XCTAssertFalse(store.isSending("p1"), "失敗の後も印が残り、二度と押せない")
    }

    // MARK: - 写真詳細: 取り消し・送信中の読み・写真ごとの送信中（2026-10-03）

    /// 🔴 **取り消された読み込みを失敗として書かない**（ログイン中）。
    /// `try?` が取り消しを nil に変え、「コメントを読み込めませんでした」が出ていた
    func testCancelledLoadIsNotRecordedAsFailure() async {
        let mine = Gate()
        let page = Gate()
        let social = stubbedSocial(gates: PathGates(["/user/likes/p1": mine, "GET /user/comments/p1": page]))
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":false}"#)
        StubProtocol.respond(path: "/user/comments/p1", status: 200, body: #"{"items":[],"count":0}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":9}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: social, initialLikes: 5)
        model.setSignedIn(true)
        model.show(photoId: "p1", initialLikes: 5, liked: true)

        let loading = Task { await model.load() }
        await mine.untilWaiting()
        await page.untilWaiting()
        loading.cancel()
        await mine.open()
        await page.open()
        await loading.value
        XCTAssertFalse(model.commentsUnavailable, "取り消しを「コメントを読み込めませんでした」と書いている")
        XCTAssertTrue(model.liked, "取り消された読み込みでハートを書き換えている")
        XCTAssertEqual(model.likes, 5, "取り消された読み込みで数を書き換えている")
    }

    /// 🔴 **取り消された読み込みでハートを倒さない**（未ログイン: 読めなかった回は白にする道がある）
    func testCancelledLoadDoesNotKnockTheHeartDownWhenSignedOut() async {
        let count = Gate()
        let page = Gate()
        let social = stubbedSocial(gates: PathGates(["GET /photos/p1/like": count, "GET /photos/p1/comments": page]))
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":9}"#)
        StubProtocol.respond(path: "/photos/p1/comments", status: 200, body: #"{"items":[],"count":0}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: social, initialLikes: 5)
        model.show(photoId: "p1", initialLikes: 5, liked: true)

        let loading = Task { await model.load() }
        await count.untilWaiting()
        await page.untilWaiting()
        loading.cancel()
        await count.open()
        await page.open()
        await loading.value
        XCTAssertTrue(model.liked, "取り消された読み込みで、ハートを白に倒している")
        XCTAssertFalse(model.commentsUnavailable, "取り消しを「コメントを読み込めませんでした」と書いている")
        XCTAssertEqual(model.likes, 5)
    }

    /// ホームで♥を押した直後（答えの前）に詳細を開いた形。押す前の読みは「押していない・5」
    private func socialWithPrePressRead(_ mine: Gate) -> SocialService {
        let social = stubbedSocial(gates: PathGates(["/user/likes/p1": mine]))
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":false}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":5}"#)
        StubProtocol.respond(path: "/user/comments/p1", status: 200, body: #"{"items":[],"count":0}"#)
        return social
    }

    /// 🔴 **ホームが送っている間に読み始め・読み終えた読みで、数とハートを固めない。**
    /// beginSending → 読み込み（送信中に読み終わる）→ ホームの答え の順。
    /// 以前は押す前の 5 を書いて `likesFromServer` が立ち、答え（`show`）の 6 が入らなかった
    func testLoadWhileHomeIsSendingDoesNotFreezeTheDetail() async {
        let mine = Gate()
        let model = PhotoDetailViewModel(photoId: "p1", social: socialWithPrePressRead(mine), initialLikes: 5)
        model.setSignedIn(true)
        let store = LikeCountStore()
        XCTAssertTrue(store.beginSending("p1"), "前提: ホームが送り始めた")
        // 開いた時点: ホームが先に灯したハート（`FavoritesStore`）と一覧の数
        model.show(photoId: "p1", initialLikes: 5, liked: true)

        let loading = Task { await model.load(gate: store) }
        await mine.untilWaiting()
        await mine.open()                    // 送っている間に読み終わる
        await loading.value
        // ホームの答えが届いた（画面の onChange が入れ直す）
        store.set("p1", count: 6)
        store.endSending("p1")
        model.show(photoId: "p1", initialLikes: 6, liked: true, answeredAt: store.entry(for: "p1")?.at)
        XCTAssertEqual(model.likes, 6, "送っている間の読みで数が固まり、ホームの答えが入らない")
        XCTAssertTrue(model.liked)
    }

    /// 🔴 **読んでいる途中で送り始めた回も書かない**（読み終わりの印を見る）。
    /// 読みは押す前の答えでありうるのに、書くと `likesFromServer` が立って答えが入らない
    func testLoadFinishedAfterASendBeganDoesNotFreezeTheDetail() async {
        let mine = Gate()
        let model = PhotoDetailViewModel(photoId: "p1", social: socialWithPrePressRead(mine), initialLikes: 5)
        model.setSignedIn(true)
        let store = LikeCountStore()
        model.show(photoId: "p1", initialLikes: 5, liked: false)

        let loading = Task { await model.load(gate: store) }
        await mine.untilWaiting()
        XCTAssertTrue(store.beginSending("p1"), "前提: 読んでいる途中で送り始めた")
        await mine.open()                    // 送っている間に読み終わる
        await loading.value
        // ホームの答えが届いた（画面の onChange が入れ直す）
        store.set("p1", count: 6)
        store.endSending("p1")
        model.show(photoId: "p1", initialLikes: 6, liked: true, answeredAt: store.entry(for: "p1")?.at)
        XCTAssertEqual(model.likes, 6, "送っている間の読みで数が固まり、ホームの答えが入らない")
        XCTAssertTrue(model.liked)
    }

    /// 🔴 **送っている間に読み始めた読みも書かない。** 答えが印を外した後、画面の
    /// onChange（`show`）より先に読み込みの続きが走る回がある
    func testLoadStartedWhileHomeIsSendingDoesNotFreezeTheDetail() async {
        let mine = Gate()
        let model = PhotoDetailViewModel(photoId: "p1", social: socialWithPrePressRead(mine), initialLikes: 5)
        model.setSignedIn(true)
        let store = LikeCountStore()
        XCTAssertTrue(store.beginSending("p1"), "前提: ホームが送り始めた")
        model.show(photoId: "p1", initialLikes: 5, liked: true)

        let loading = Task { await model.load(gate: store) }
        await mine.untilWaiting()
        store.set("p1", count: 6)            // ホームの答え（印も外れる）
        store.endSending("p1")
        await mine.open()                    // 画面が入れ直す前に、読み込みの続きが走る
        await loading.value
        model.show(photoId: "p1", initialLikes: 6, liked: true, answeredAt: store.entry(for: "p1")?.at)
        XCTAssertEqual(model.likes, 6, "送っている間に読み始めた読みで数が固まる")
        XCTAssertTrue(model.liked)
    }

    /// 🔴 **束を左右に送った後の♥は、前の1枚を送っている間も送る**（印は写真ごと）
    func testLikeOnTheNextPhotoIsSentWhileThePreviousOneIsSending() async {
        let liking = Gate()
        let social = stubbedSocial(gates: PathGates(["POST /photos/p1/like": liking]))
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"liked":true,"likes":8}"#)
        StubProtocol.respond(path: "/photos/p2/like", status: 200, body: #"{"liked":true,"likes":4}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: social, initialLikes: 7)
        model.setSignedIn(true)
        let store = LikeCountStore()

        let pressed = Task { await model.toggleLike(gate: store) }
        await liking.untilWaiting()
        model.show(photoId: "p2", initialLikes: 3, liked: false)
        let answer = await model.toggleLike(gate: store)
        XCTAssertEqual(answer, PhotoDetailViewModel.LikeAnswer(photoId: "p2", liked: true, likes: 4),
                       "前の1枚を送っている間、隣の1枚の♥を黙って捨てている")
        XCTAssertTrue(StubProtocol.requests.contains("POST /photos/p2/like"))
        XCTAssertTrue(model.liked)
        XCTAssertEqual(model.likes, 4)
        await liking.open()
        _ = await pressed.value
        XCTAssertFalse(store.isSending("p1"))
        XCTAssertFalse(store.isSending("p2"))
    }

    // MARK: - 写真詳細: 中身の印・確かめた♥（2026-10-03 レビュー）

    /// 🔴 **「いまコメントの中身が入っている写真」は読み終えたときだけ立ち、読みに行く前・
    /// 取り消し・失敗・別の1枚へ送ったときに外れる。** 前の1枚の印が残り、戻った1枚が
    /// 空のまま読み直されなかった
    func testCommentsPhotoIdTracksOnlyLoadedContent() async {
        let page = Gate(holds: 1, skip: 1)   // 1回目は通し、2回目（取り消す回）を止める
        let social = stubbedSocial(gates: PathGates(["GET /user/comments/p1": page]))
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":true}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":5}"#)
        StubProtocol.respond(path: "/user/comments/p1", status: 200, body: #"{"items":[],"count":0}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: social, initialLikes: 5)
        model.setSignedIn(true)
        XCTAssertNil(model.commentsPhotoId)

        await model.load()
        XCTAssertEqual(model.commentsPhotoId, "p1", "読み終えたのに中身の印が立たない")

        let loading = Task { await model.load() }
        await page.untilWaiting(2)
        XCTAssertNil(model.commentsPhotoId, "読みに行く前に印を外していない（抜けた回に読み済みと扱う）")
        loading.cancel()
        await page.open()
        await loading.value
        XCTAssertNil(model.commentsPhotoId, "取り消された回に、読めていない1枚を読み済みと扱っている")

        await model.load()
        XCTAssertEqual(model.commentsPhotoId, "p1")
        model.show(photoId: "p2", initialLikes: 3, liked: false)
        XCTAssertNil(model.commentsPhotoId, "別の1枚へ送ったのに、前の1枚の印が残っている")
    }

    /// 読めなかった回も印は立たない
    func testCommentsPhotoIdStaysEmptyWhenCommentsFail() async {
        let social = stubbedSocial()
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":true}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":5}"#)
        StubProtocol.respond(path: "/user/comments/p1", status: 500, body: "{}")
        let model = PhotoDetailViewModel(photoId: "p1", social: social, initialLikes: 5)
        model.setSignedIn(true)
        await model.load()
        XCTAssertTrue(model.commentsUnavailable)
        XCTAssertNil(model.commentsPhotoId, "読めなかったのに読み済みと扱っている")
    }

    /// 🔴 **サーバーで確かめた♥を、端末の控えの白で上書きしない**（同じ1枚・それより古い答え）。
    /// 大きく見る画面を閉じた後の `.task` が控えで上書きし、白い♥のまま固まっていた
    func testConfirmedHeartIsNotOverwrittenByAnOlderStoredValue() async {
        let social = stubbedSocial()
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":true}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":5}"#)
        StubProtocol.respond(path: "/user/comments/p1", status: 200, body: #"{"items":[],"count":0}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: social, initialLikes: 5)
        model.setSignedIn(true)
        model.show(photoId: "p1", initialLikes: 5, liked: false)   // 端末の控えはまだ白
        await model.load()
        XCTAssertTrue(model.liked, "前提: サーバーは押してあると答えた")

        model.show(photoId: "p1", initialLikes: 5, liked: false)
        XCTAssertTrue(model.liked, "確かめた♥を、控えの白で上書きしている")
        // 確かめた後に押した答え（ホーム・大きく見る画面）が控えに入ったら、そちらを出す
        model.show(photoId: "p1", initialLikes: 4, liked: false, answeredAt: Date().addingTimeInterval(1))
        XCTAssertFalse(model.liked, "確かめた後の押した答えを出していない")
    }

    /// 人が替わったら、前の人で確かめたハートは信じない（控えを出す）
    func testConfirmedHeartIsForgottenWhenThePersonChanges() async {
        let social = stubbedSocial()
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":true}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":5}"#)
        StubProtocol.respond(path: "/user/comments/p1", status: 200, body: #"{"items":[],"count":0}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: social, initialLikes: 5)
        model.setSignedIn(true)
        await model.load()
        model.setSignedIn(false)
        model.show(photoId: "p1", initialLikes: 5, liked: false)
        XCTAssertFalse(model.liked, "ログアウトした後も、前の人の♥を出している")
    }

    /// 控えで書き換えてよいかの規則（`LiveLikes.storedLikedWins`）
    func testStoredLikedWinsRule() async {
        let t = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(LiveLikes.storedLikedWins(confirmedAt: nil, answeredAt: nil), "確かめていなければ控えを出す")
        XCTAssertFalse(LiveLikes.storedLikedWins(confirmedAt: t, answeredAt: nil))
        XCTAssertFalse(LiveLikes.storedLikedWins(confirmedAt: t, answeredAt: t.addingTimeInterval(-1)))
        XCTAssertTrue(LiveLikes.storedLikedWins(confirmedAt: t, answeredAt: t.addingTimeInterval(1)))
    }

    /// 🔴 **A から B へ直接切り替えたら、A で確かめた♥を B に残さない**（ログインの有無は変わらない）
    func testConfirmedHeartIsForgottenWhenSwitchingAccounts() async {
        let social = stubbedSocial()
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":true}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":5}"#)
        StubProtocol.respond(path: "/user/comments/p1", status: 200, body: #"{"items":[],"count":0}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: social, initialLikes: 5)
        model.setUser("a")
        await model.load()
        XCTAssertTrue(model.liked, "前提: A は押してある")
        model.setUser("b")
        model.show(photoId: "p1", initialLikes: 5, liked: false)
        XCTAssertFalse(model.liked, "B に切り替えた後も、A で確かめた♥を出している")
        // 同じ人のまま入れ直しても、確かめた♥は残る
        model.setUser("b")
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":true}"#)
        await model.load()
        model.setUser("b")
        model.show(photoId: "p1", initialLikes: 5, liked: false)
        XCTAssertTrue(model.liked, "同じ人なのに、確かめた♥を忘れている")
    }

    /// 🔴 **数を返さない押した答えでも、時刻は残る**（ハートだけ書き換わった答えが、
    /// サーバーで確かめた古い♥に負けていた）
    func testAnswerWithoutCountStillBeatsAnOlderConfirmedHeart() async {
        let social = stubbedSocial()
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":false}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":5}"#)
        StubProtocol.respond(path: "/user/comments/p1", status: 200, body: #"{"items":[],"count":0}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: social, initialLikes: 5)
        model.setSignedIn(true)
        await model.load()
        XCTAssertFalse(model.liked, "前提: サーバーは押していないと答えた")
        let store = LikeCountStore()
        // 別の画面（ホームのカード）で押した。答えに数が無い
        store.recordAnswer("p1", count: nil, at: Date().addingTimeInterval(1))
        XCTAssertNil(store.entry(for: "p1"), "数の無い答えで数を作っている")
        // 画面は `showStoredLike` と同じく、最後の答えの時刻を渡す
        model.show(photoId: "p1", initialLikes: 5, liked: true, answeredAt: store.lastAnswer(for: "p1"))
        XCTAssertTrue(model.liked, "数の無い押した答えが、確かめた古い♥に負けている")
    }
}
