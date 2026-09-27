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
        likes.replace(with: ["前から", "外した"], since: mark)
        XCTAssertEqual(likes.ids, ["前から", "押した"], "取りに行っている間の操作を上書きしている")
    }

    /// **印より前の控えは今までどおり入れ替える**（保存しただけの古い id を落とす）
    func testLikeSyncStillReplacesWhatCameBeforeTheMark() async {
        let likes = FavoritesStore(defaults: defaults())
        likes.use(userId: "u1")
        likes.set("保存しただけの古い写真", favorite: true)
        let mark = likes.syncMark
        likes.replace(with: ["本当にいいねした写真"], since: mark)
        XCTAssertEqual(likes.ids, ["本当にいいねした写真"])
    }

    /// 🔴 **前の人の同期の答えを、次にログインした人の控えに書かない**
    func testLikeSyncForAnotherPersonIsDropped() async {
        let likes = FavoritesStore(defaults: defaults())
        likes.use(userId: "a")
        let mark = likes.syncMark
        likes.use(userId: "b")
        likes.set("b の写真", favorite: true)
        likes.replace(with: ["a の写真"], since: mark)
        XCTAssertEqual(likes.ids, ["b の写真"], "前の人の一覧を書いている")
    }

    func testSaveSyncKeepsWhatWasPressedWhileFetching() async {
        let saves = SavedPhotosStore(defaults: defaults())
        saves.use(userId: "u1")
        let mark = saves.syncMark
        saves.set("押した", saved: true)
        saves.set("外した", saved: false)
        saves.replace(with: ["前から", "外した"], since: mark)
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
        hidden.replaceBlocked(with: ["前から", "解除する人"], since: mark)
        XCTAssertEqual(hidden.blockedUserIds, ["前から", "いまブロックした人"],
                       "取りに行っている間のブロック・解除を上書きしている")
    }

    func testBlockSyncForAnotherPersonIsDropped() async {
        let hidden = ModerationStore(defaults: defaults())
        hidden.use(userId: "a")
        let mark = hidden.blockSyncMark
        hidden.use(userId: "b")
        hidden.replaceBlocked(with: ["a がブロックした人"], since: mark)
        XCTAssertTrue(hidden.blockedUserIds.isEmpty, "前の人のブロック一覧を書いている")
    }

    // MARK: - 写真の詳細: 開いた直後のいいね（L-1）

    private func stubbedSocial() -> SocialService {
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
        return SocialService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                            tokenProvider: StubTokenProvider(token: "t"), session: session))
    }

    /// 🔴 **束の隣へ送った後に前の1枚の答えが届いても、今の1枚の読み込みは捨てない**
    /// （9abb5ea のレビュー: 押した写真を区別せずに数えていた）
    func testLikeAnswerForThePreviousPhotoDoesNotDiscardTheNextLoad() async {
        let social = stubbedSocial()
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"liked":true,"likes":8}"#, delay: 0.2)
        StubProtocol.respond(path: "/user/likes/p2", status: 200, body: #"{"liked":true}"#, delay: 0.4)
        StubProtocol.respond(path: "/photos/p2/comments", status: 200, body: #"{"items":[],"count":0}"#)
        StubProtocol.respond(path: "/photos/p2/like", status: 200, body: #"{"likes":9}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: social, initialLikes: 7)
        model.setSignedIn(true)

        async let pressed = model.toggleLike()
        try? await Task.sleep(nanoseconds: 50_000_000)
        model.show(photoId: "p2", initialLikes: 3, liked: false)
        await model.load()
        _ = await pressed
        XCTAssertTrue(model.liked, "前の1枚の答えのせいで、今の1枚のハートを読み捨てている")
        XCTAssertEqual(model.likes, 9, "前の1枚の答えのせいで、今の1枚の数を読み捨てている")
    }

    /// **断られたいいねは数えない**（サーバーは変わっていないので、読み込みの答えが正しい）
    func testRejectedLikeDoesNotDiscardTheLoad() async {
        let social = stubbedSocial()
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":true}"#, delay: 0.3)
        StubProtocol.respond(path: "/photos/p1/comments", status: 200, body: #"{"items":[],"count":0}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 500, body: "{}")
        let model = PhotoDetailViewModel(photoId: "p1", social: social, initialLikes: 5)
        model.setSignedIn(true)

        async let loading: Void = model.load()
        try? await Task.sleep(nanoseconds: 100_000_000)
        _ = await model.toggleLike()
        await loading
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
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        // 「自分が押しているか」は押す前の答え（押していない）が遅れて届く
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":false}"#, delay: 0.3)
        StubProtocol.respond(path: "/photos/p1/comments", status: 200, body: #"{"items":[],"count":0}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"liked":true,"likes":6}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api), initialLikes: 5)
        model.setSignedIn(true)

        async let loading: Void = model.load()
        try? await Task.sleep(nanoseconds: 100_000_000)
        _ = await model.toggleLike()
        XCTAssertTrue(model.liked, "前提: 押した答えが入っていない")
        await loading
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
