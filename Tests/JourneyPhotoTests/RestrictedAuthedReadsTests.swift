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

    /// `gates` を渡すと、その道の要求だけ手前で止める（`ViewModelTests.api(gates:)` と同じ）
    private func social(token: String? = "t", gates: PathGates? = nil) -> SocialService {
        SocialService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                     tokenProvider: StubTokenProvider(token: token),
                                     session: session,
                                     beforeRequest: gates.map { gates in { (request: URLRequest) async in await gates.wait(for: request) } }))
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
        XCTAssertEqual(StubProtocol.requests.filter { $0.contains("comments") }, ["GET /user/comments/p1"], "未認証の口で読んでいる（絞った写真で 404）")
        XCTAssertEqual(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer t")
    }

    /// 新しい口がまだデプロイされていない（道が無い 404）ときだけ、未認証の口に戻る
    func testMissingRouteFallsBackToThePublicComments() async throws {
        prepare()
        StubProtocol.respond(path: "/user/comments/p1", status: 404, body: missingRoute)
        StubProtocol.respond(path: "/photos/p1/comments", status: 200, body: page)
        let result = try await social().comments(photoId: "p1", signedIn: true)
        XCTAssertEqual(result.items.map(\.id), ["c1"], "道が無い回に未認証の口へ戻っていない")
        XCTAssertEqual(StubProtocol.requests.filter { $0.contains("comments") }, ["GET /user/comments/p1", "GET /photos/p1/comments"])
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
            XCTAssertEqual(StubProtocol.requests.filter { $0.contains("comments") }, ["GET /user/comments/p1"], "断られた 404 で未認証の口に戻っている")
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
            XCTAssertEqual(StubProtocol.requests.filter { $0.contains("comments") }, ["GET /user/comments/p1"])
        }
    }

    /// 未ログインは今までどおり未認証の口（鍵を求めない）
    func testSignedOutReadsThePublicComments() async throws {
        prepare()
        StubProtocol.respond(path: "/photos/p1/comments", status: 200, body: page)
        let result = try await social(token: nil).comments(photoId: "p1", signedIn: false)
        XCTAssertEqual(result.items.map(\.id), ["c1"])
        // コメントの口だけを見る。🔴 前の試験（`testSignedInTakesTheCountFromMyLike` ほか）が捨てた
        // 未認証のいいね数の要求（`async let` の取り消し）が、試験の終わった後に `StubProtocol` へ届き、
        // この試験の記録に混ざることがある（Mac の run 352 で `GET /photos/p1/like` が混ざって落ちた・2026-10-07）
        XCTAssertEqual(StubProtocol.requests.filter { $0.contains("comments") }, ["GET /photos/p1/comments"])
        XCTAssertNil(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: - いいね数

    /// 🔴 ログイン中は自分の印の口の `count` を数にする。同時に投げた未認証の答え（9）は捨てる
    func testSignedInTakesTheCountFromMyLike() async {
        prepare()
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":true,"count":4}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":9}"#)
        let snapshot = await social().likeSnapshot(photoId: "p1", signedIn: true)
        XCTAssertEqual(snapshot, SocialService.LikeSnapshot(liked: true, count: 4), "count があるのに未認証の数を使っている")
        XCTAssertEqual(StubProtocol.requests.filter { $0 == "GET /user/likes/p1" }.count, 1,
                       "印の口を二重に呼んでいる")
    }

    /// `count` が 0 のときも 0 を使う（無いのと取り違えない）
    func testZeroCountIsACount() async {
        prepare()
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":false,"count":0}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":9}"#)
        let snapshot = await social().likeSnapshot(photoId: "p1", signedIn: true)
        XCTAssertEqual(snapshot, SocialService.LikeSnapshot(liked: false, count: 0))
    }

    /// 🔴 2本は**同時に**投げる——印の口の答えを止めている間に、未認証の数の口が出ている。
    /// 順番に投げると、印の口が戻るまで未認証の口の Gate に誰も着かず落ちる
    func testBothReadsAreInFlightAtOnce() async {
        prepare()
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":false}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":9}"#)
        let mine = Gate()
        let anonymous = Gate()
        let service = social(gates: PathGates(["/user/likes/p1": mine, "/photos/p1/like": anonymous]))
        let read = Task { await service.likeSnapshot(photoId: "p1", signedIn: true) }
        await mine.untilWaiting()
        await anonymous.untilWaiting()
        await mine.open()
        await anonymous.open()
        let snapshot = await read.value
        XCTAssertEqual(snapshot, SocialService.LikeSnapshot(liked: false, count: 9))
    }

    /// 古いサーバー（`count` を付けない）は、**限定写真も**未認証の口で数を返す。そちらを使う
    /// （アプリが #269 より先に出ても、限定写真の数が消えない）
    func testOldServerWithoutCountUsesThePublicCount() async {
        prepare()
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":true}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":9}"#)
        let snapshot = await social().likeSnapshot(photoId: "p1", signedIn: true)
        XCTAssertEqual(snapshot, SocialService.LikeSnapshot(liked: true, count: 9), "古いサーバーで数が出なくなった")
    }

    /// 新しいサーバーの見せない相手: `count` 無し・未認証は 404 → 「数を出さない」（0 と読まない）
    func testNoCountAndPublic404IsUnknown() async {
        prepare()
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":true}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 404, body: refused)
        let snapshot = await social().likeSnapshot(photoId: "p1", signedIn: true)
        XCTAssertEqual(snapshot, SocialService.LikeSnapshot(liked: true, count: nil), "数が無いのに数を作っている")
    }

    /// 未認証の口の失敗は無視（印と count は使う）
    func testPublicFailureIsIgnoredWhenCountComes() async {
        prepare()
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":true,"count":3}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 500, body: #"{"error":"取得に失敗しました"}"#)
        let snapshot = await social().likeSnapshot(photoId: "p1", signedIn: true)
        XCTAssertEqual(snapshot, SocialService.LikeSnapshot(liked: true, count: 3))
    }

    /// 🔴 **未認証の答えを捨てる（`async let` の取り消し）と応答が重なっても固まらない。**
    /// Linux の URLSession の `data(for:)` は、取り消しと応答が重なると互いに待って止まり、
    /// 全試験が3回に1回返ってこなかった（`URLSession.cancellableData` の注記）。
    /// 重なりは1回では起きにくいので、何度も回す
    func testDiscardingThePublicAnswerNeverHangs() async {
        prepare()
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":true,"count":3}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":9}"#)
        let service = social()
        for _ in 0..<300 {
            let snapshot = await service.likeSnapshot(photoId: "p1", signedIn: true)
            XCTAssertEqual(snapshot, SocialService.LikeSnapshot(liked: true, count: 3))
        }
    }

    /// 取り消された読み込みは `URLError(.cancelled)`→`CancellationError` で返る（固まらず・
    /// 「通信できません」にもならない）。応答と取り消しのどちらが先でも1回だけ返る
    func testCancelledReadReturnsWithoutHanging() async {
        prepare()
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":9}"#)
        let service = social(token: nil)
        for _ in 0..<300 {
            let read = Task { try await service.likeCount(photoId: "p1") }
            read.cancel()
            let result = await read.result
            switch result {
            case .success(let count): XCTAssertEqual(count, 9)
            case .failure(let error): XCTAssertTrue(error is CancellationError, "取り消しを別の失敗にしている: \(error)")
            }
        }
    }

    /// 未ログインは今までどおり未認証の数の口だけ（印は聞かない）
    func testSignedOutReadsThePublicCount() async {
        prepare()
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":3}"#)
        let snapshot = await social(token: nil).likeSnapshot(photoId: "p1", signedIn: false)
        XCTAssertEqual(snapshot, SocialService.LikeSnapshot(liked: nil, count: 3))
        // 前の試験が捨てた未認証の要求が遅れて混ざることがある（`testSignedOutReadsThePublicComments` の注記）ので、
        // 「印の口（/user/…）を聞いていない」と「未認証の口を聞いた」で見る
        XCTAssertFalse(StubProtocol.requests.contains { $0.contains("/user/") }, "未ログインで印の口を聞いている")
        XCTAssertTrue(StubProtocol.requests.contains("GET /photos/p1/like"))
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
        model.show(photoId: "p1", initialLikes: 5, liked: false)
        await model.load()
        XCTAssertFalse(model.commentsUnavailable, "絞った写真のコメントが「読み込めませんでした」になる")
        XCTAssertEqual(model.comments.map(\.id), ["c1"])
        XCTAssertEqual(model.likes, 12, "絞った写真のいいね数が更新されない")
        XCTAssertTrue(model.liked)
        XCTAssertFalse(StubProtocol.requests.contains("GET /photos/p1/comments"), "未認証のコメントの口を叩いている")
    }

    /// 新しいサーバーで数が来なかった（`count` 無し・未認証は 404）写真は、出ていた数を保つ（0 にしない）
    func testDetailKeepsTheShownCountWhenNoCountComes() async {
        prepare()
        StubProtocol.respond(path: "/user/comments/p1", status: 200, body: page)
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":false}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 404, body: refused)
        let model = PhotoDetailViewModel(photoId: "p1", social: social(), initialLikes: 7)
        model.setSignedIn(true)
        model.show(photoId: "p1", initialLikes: 7, liked: false)
        await model.load()
        XCTAssertEqual(model.likes, 7, "数が無いのに 0 にしている・出ていた数を捨てている")
    }

    /// 🔴 **読んでいる間に束の隣へ送ったら、前の1枚の答えを書かない**（`load()` の `id == photoId`）。
    /// 印の口を止めている間に p2 へ送り、止めを外しても、p2 の数・ハート・コメントは p1 のものにならない
    func testLoadAnswerForThePreviousPhotoIsDroppedAfterSwiping() async {
        prepare()
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":true,"count":12}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":12}"#)
        StubProtocol.respond(path: "/user/comments/p1", status: 200, body: page)
        let gate = Gate()
        let model = PhotoDetailViewModel(photoId: "p1",
                                         social: social(gates: PathGates(["/user/likes/p1": gate])),
                                         initialLikes: 5)
        model.setSignedIn(true)
        let loading = Task { await model.load() }
        await gate.untilWaiting()
        model.show(photoId: "p2", initialLikes: 3, liked: false)
        await gate.open()
        await loading.value
        XCTAssertEqual(model.photoId, "p2")
        XCTAssertEqual(model.likes, 3, "前の1枚の数を今の1枚に出している")
        XCTAssertFalse(model.liked, "前の1枚のハートを今の1枚に出している")
        XCTAssertTrue(model.comments.isEmpty, "前の1枚のコメントを今の1枚に出している")
        XCTAssertNil(model.commentCount)
        XCTAssertFalse(model.commentsUnavailable)
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
