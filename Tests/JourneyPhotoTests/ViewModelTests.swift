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

    // MARK: - 写真の詳細

    /// **いいねの数は自分で足さない。** サーバーが返した数を使う。
    func testLikeUsesServerCount() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(true)

        StubProtocol.respond(status: 200, body: #"{"liked":true,"likes":42}"#)
        await model.toggleLike()

        XCTAssertTrue(model.liked)
        XCTAssertEqual(model.likes, 42, "手元で足し算している")
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
    func testPostedCommentAppearsImmediately() async {
        prepare()
        let model = PhotoDetailViewModel(photoId: "p1", social: SocialService(api: api()))
        model.setSignedIn(true)
        model.draftComment = "きれい"

        StubProtocol.respond(status: 200, body: #"{"comment":{"id":"c1","uid":"u1","name":"たろう","text":"きれい"}}"#)
        await model.postComment()

        XCTAssertEqual(model.comments.first?.text, "きれい")
        XCTAssertEqual(model.commentCount, 1)
        XCTAssertEqual(model.draftComment, "", "送ったのに入力欄が残っている")
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
        guard case .photo(let photo) = model(feed: [try photo(id: "p1")]).destination(for: n) else {
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
