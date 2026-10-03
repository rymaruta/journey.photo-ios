import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 公開範囲を絞った写真（`audience` あり）のコメントといいね数を、**ログイン中は認証つきの口で読む**
/// （photo-gallery #269）。
///
/// 絞った写真は未認証の `GET /photos/{id}/comments`・`GET /photos/{id}/like` が 404 になる。
/// 未認証で読んだままだと、本人・フォロワーにもコメント欄が「読み込めませんでした」になり、
/// いいね数が更新されない。
@MainActor
final class RestrictedAuthedReadsTests: XCTestCase {

    private var session: URLSession!

    /// `setUp` はメインアクタではないので、用意は各テストの頭で行う（`ViewModelTests` と同じ）
    private func prepare() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset()
    }

    private func social(token: String? = "t") -> SocialService {
        SocialService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                     tokenProvider: StubTokenProvider(token: token),
                                     session: session))
    }

    /// API Gateway の「道が無い」404（新しい口がまだデプロイされていない）
    private let missingRoute = #"{"message":"Not Found"}"#
    /// サーバー（api-user）が断った 404
    private let refused = #"{"error":"写真が見つかりません"}"#
    private let page = #"{"items":[{"id":"c1","uid":"u1","name":"a","text":"hi"}],"count":1}"#

    // MARK: - 「道が無い」404 の見分け

    func testMissingRouteIsOnlyA404WithoutOurErrorBody() async {
        XCTAssertTrue(APIError.server(status: 404, message: "").isMissingRoute)
        XCTAssertFalse(APIError.server(status: 404, message: "写真が見つかりません").isMissingRoute,
                       "サーバーが断った 404 を「道が無い」と読んでいる")
        XCTAssertFalse(APIError.server(status: 500, message: "").isMissingRoute)
        XCTAssertFalse(APIError.unreachable.isMissingRoute)
    }

    /// 本文の読み方（`APIClient.errorMessage`）と合わせて、API Gateway の本文が「道が無い」になる
    func testGatewayNotFoundBodyReadsAsMissingRoute() async {
        prepare()
        StubProtocol.respond(status: 404, body: missingRoute)
        do {
            _ = try await APIClient(baseURL: URL(string: "https://api.example.test")!,
                                    tokenProvider: StubTokenProvider(token: "t"),
                                    session: session)
                .authorized(.get, "/user/comments/p1", as: SocialService.CommentPage.self)
            XCTFail("404 なのに成功している")
        } catch {
            XCTAssertEqual((error as? APIError)?.isMissingRoute, true)
        }
    }

    // MARK: - コメント

    /// 🔴 ログイン中は認証つきの口を読む（未認証の口は叩かない）
    func testSignedInReadsCommentsThroughTheAuthedRoute() async throws {
        prepare()
        StubProtocol.respond(path: "/user/comments/p1", status: 200, body: page)
        let result = try await social().comments(photoId: "p1", signedIn: true)
        XCTAssertEqual(result.items.map(\.id), ["c1"])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(StubProtocol.requests, ["GET /user/comments/p1"], "未認証の口で読んでいる（絞った写真で 404）")
        XCTAssertEqual(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer t")
    }

    /// 新しい口がまだデプロイされていない（道が無い 404）ときだけ、未認証の口に戻る
    func testMissingRouteFallsBackToThePublicComments() async throws {
        prepare()
        StubProtocol.respond(path: "/user/comments/p1", status: 404, body: missingRoute)
        StubProtocol.respond(path: "/photos/p1/comments", status: 200, body: page)
        let result = try await social().comments(photoId: "p1", signedIn: true)
        XCTAssertEqual(result.items.map(\.id), ["c1"], "道が無い回に未認証の口へ戻っていない")
        XCTAssertEqual(StubProtocol.requests, ["GET /user/comments/p1", "GET /photos/p1/comments"])
        XCTAssertNil(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"),
                     "未認証の口に鍵を付けている")
    }

    /// サーバーが断った 404（`error` 付き）では戻らない——戻っても同じ 404 で往復が増えるだけ
    func testRefused404DoesNotFallBack() async {
        prepare()
        StubProtocol.respond(path: "/user/comments/p1", status: 404, body: refused)
        StubProtocol.respond(path: "/photos/p1/comments", status: 200, body: page)
        do {
            _ = try await social().comments(photoId: "p1", signedIn: true)
            XCTFail("サーバーが断ったのに未認証の口で読めたことにしている")
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 404, message: "写真が見つかりません"))
            XCTAssertEqual(StubProtocol.requests, ["GET /user/comments/p1"], "断られた 404 で未認証の口に戻っている")
        }
    }

    /// 404 以外の失敗（500）でも戻らない
    func testServerErrorDoesNotFallBack() async {
        prepare()
        StubProtocol.respond(path: "/user/comments/p1", status: 500, body: #"{"error":"取得に失敗しました"}"#)
        StubProtocol.respond(path: "/photos/p1/comments", status: 200, body: page)
        do {
            _ = try await social().comments(photoId: "p1", signedIn: true)
            XCTFail("500 なのに成功している")
        } catch {
            XCTAssertEqual(StubProtocol.requests, ["GET /user/comments/p1"])
        }
    }

    /// 未ログインは今までどおり未認証の口（鍵を求めない）
    func testSignedOutReadsThePublicComments() async throws {
        prepare()
        StubProtocol.respond(path: "/photos/p1/comments", status: 200, body: page)
        let result = try await social(token: nil).comments(photoId: "p1", signedIn: false)
        XCTAssertEqual(result.items.map(\.id), ["c1"])
        XCTAssertEqual(StubProtocol.requests, ["GET /photos/p1/comments"])
        XCTAssertNil(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: - いいね数

    /// 🔴 ログイン中は自分の印の口の `count` を数にする（未認証の数の口は叩かない・1本だけ）
    func testSignedInTakesTheCountFromMyLike() async {
        prepare()
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":true,"count":4}"#)
        let snapshot = await social().likeSnapshot(photoId: "p1", signedIn: true, restricted: true)
        XCTAssertEqual(snapshot, SocialService.LikeSnapshot(liked: true, count: 4))
        XCTAssertEqual(StubProtocol.requests, ["GET /user/likes/p1"], "数を別の口へ取りに行っている（二重に呼んでいる）")
    }

    /// 公開の写真でも `count` があればそれを使う（未認証の口へは行かない）
    func testCountIsUsedForPublicPhotosToo() async {
        prepare()
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":false,"count":0}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":9}"#)
        let snapshot = await social().likeSnapshot(photoId: "p1", signedIn: true, restricted: false)
        XCTAssertEqual(snapshot, SocialService.LikeSnapshot(liked: false, count: 0))
        XCTAssertEqual(StubProtocol.requests, ["GET /user/likes/p1"])
    }

    /// `count` が無い（見せない相手）絞った写真は「数を出さない」。0 と読まず、未認証の口にも戻らない
    func testMissingCountOnARestrictedPhotoIsUnknown() async {
        prepare()
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":true}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":9}"#)
        let snapshot = await social().likeSnapshot(photoId: "p1", signedIn: true, restricted: true)
        XCTAssertEqual(snapshot, SocialService.LikeSnapshot(liked: true, count: nil), "数が無いのに数を作っている")
        XCTAssertEqual(StubProtocol.requests, ["GET /user/likes/p1"], "絞った写真で未認証の口へ戻っている（404 になるだけ）")
    }

    /// 古いサーバー（`count` を付けない）で公開の写真なら、従来の未認証の口に戻る
    func testOldServerWithoutCountFallsBackForPublicPhotos() async {
        prepare()
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":false}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":9}"#)
        let snapshot = await social().likeSnapshot(photoId: "p1", signedIn: true, restricted: false)
        XCTAssertEqual(snapshot, SocialService.LikeSnapshot(liked: false, count: 9), "古いサーバーで数が出なくなった")
        XCTAssertEqual(StubProtocol.requests, ["GET /user/likes/p1", "GET /photos/p1/like"])
    }

    /// 未ログインは今までどおり未認証の数の口だけ（印は聞かない）
    func testSignedOutReadsThePublicCount() async {
        prepare()
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":3}"#)
        let snapshot = await social(token: nil).likeSnapshot(photoId: "p1", signedIn: false, restricted: false)
        XCTAssertEqual(snapshot, SocialService.LikeSnapshot(liked: nil, count: 3))
        XCTAssertEqual(StubProtocol.requests, ["GET /photos/p1/like"])
    }

    // MARK: - 写真の詳細（画面の頭）

    /// 🔴 絞った写真をフォロワーが開く: コメントが読め、数は `/user/likes/{id}` の数になる
    func testDetailOfARestrictedPhotoLoadsForAFollower() async {
        prepare()
        StubProtocol.respond(path: "/user/comments/p1", status: 200, body: page)
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":true,"count":12}"#)
        // 未認証の口はサーバーどおり 404（叩いたら数もコメントも取れない）
        StubProtocol.respond(path: "/photos/p1/comments", status: 404, body: refused)
        StubProtocol.respond(path: "/photos/p1/like", status: 404, body: refused)
        let model = PhotoDetailViewModel(photoId: "p1", social: social(), initialLikes: 5)
        model.setSignedIn(true)
        model.show(photoId: "p1", initialLikes: 5, liked: false, restricted: true)
        await model.load()
        XCTAssertFalse(model.commentsUnavailable, "絞った写真のコメントが「読み込めませんでした」になる")
        XCTAssertEqual(model.comments.map(\.id), ["c1"])
        XCTAssertEqual(model.likes, 12, "絞った写真のいいね数が更新されない")
        XCTAssertTrue(model.liked)
        XCTAssertFalse(StubProtocol.requests.contains("GET /photos/p1/like"), "未認証の数の口を叩いている")
        XCTAssertFalse(StubProtocol.requests.contains("GET /photos/p1/comments"), "未認証のコメントの口を叩いている")
    }

    /// 数が来なかった絞った写真は、出ていた数を保つ（0 にしない）
    func testDetailKeepsTheShownCountWhenNoCountComes() async {
        prepare()
        StubProtocol.respond(path: "/user/comments/p1", status: 200, body: page)
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":false}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: social(), initialLikes: 7)
        model.setSignedIn(true)
        model.show(photoId: "p1", initialLikes: 7, liked: false, restricted: true)
        await model.load()
        XCTAssertEqual(model.likes, 7, "数が無いのに 0 にしている・出ていた数を捨てている")
    }

    /// 未ログインで開いた公開の写真は今までどおり未認証の口だけ
    func testDetailSignedOutUsesThePublicRoutes() async {
        prepare()
        StubProtocol.respond(path: "/photos/p1/comments", status: 200, body: page)
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":2}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: social(token: nil), initialLikes: nil)
        model.setSignedIn(false)
        await model.load()
        XCTAssertEqual(model.likes, 2)
        XCTAssertEqual(model.comments.map(\.id), ["c1"])
        XCTAssertEqual(Set(StubProtocol.requests), ["GET /photos/p1/comments", "GET /photos/p1/like"])
    }
}
