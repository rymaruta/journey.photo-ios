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
}
