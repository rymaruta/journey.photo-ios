import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 写真の詳細の**いいねの宛先**と、取り消された読み込み（2026-10-03 の品質点検）。
///
/// 束を払うと画面の1枚（`current`）はすぐ替わるが、`PhotoDetailViewModel.show(photoId:)` が
/// 走るのは `.task(id:)` が組み直された後。その間に下のハートを押すと、**見えていない前の1枚に**
/// いいね（や取り消し）が飛んでいた。
@MainActor
final class DetailLikeTargetTests: XCTestCase {

    private var session: URLSession!

    /// `setUp` はメインアクタではないので、用意は各テストの頭で行う（`ViewModelTests` と同じ）
    private func prepare() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset()
    }

    private func social(gates: PathGates? = nil) -> SocialService {
        SocialService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                     tokenProvider: StubTokenProvider(token: "t"),
                                     session: session,
                                     beforeRequest: gates.map { gates in { (request: URLRequest) async in await gates.wait(for: request) } }))
    }

    /// 🔴 画面の1枚（p2）と画面の持ち主（まだ p1）が食い違う間は、**何も送らない**
    func testLikeIsNotSentToThePreviousPhotoRightAfterSwiping() async {
        prepare()
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"liked":true,"likes":9}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: social())
        model.setSignedIn(true)
        model.show(photoId: "p1", initialLikes: 3, liked: false)

        let answer = await model.toggleLike(gate: LikeCountStore(), shownId: "p2")

        XCTAssertNil(answer, "見えていない前の1枚へ送った")
        XCTAssertEqual(StubProtocol.requests.filter { $0.hasPrefix("POST") || $0.hasPrefix("DELETE") }, [],
                       "前の1枚にいいねを送っている")
        XCTAssertFalse(model.liked)
        XCTAssertEqual(model.likes, 3)
        XCTAssertNil(model.errorMessage, "送らなかっただけの回に失敗を出した")
    }

    /// 画面の1枚と持ち主が揃っていれば、今までどおりその1枚へ送る
    func testLikeIsSentWhenTheShownPhotoMatches() async {
        prepare()
        StubProtocol.respond(path: "/photos/p2/like", status: 200, body: #"{"liked":true,"likes":4}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: social())
        model.setSignedIn(true)
        model.show(photoId: "p2", initialLikes: 3, liked: false)

        let answer = await model.toggleLike(gate: LikeCountStore(), shownId: "p2")

        XCTAssertEqual(answer, PhotoDetailViewModel.LikeAnswer(photoId: "p2", liked: true, likes: 4))
        XCTAssertEqual(StubProtocol.requests.filter { $0.hasPrefix("POST") }, ["POST /photos/p2/like"])
        XCTAssertTrue(model.liked)
        XCTAssertEqual(model.likes, 4)
    }

    /// 取り消しの合図が出たあとの払いも同じ（取り消しは送らない。いいね済みの p1 を外さない）
    func testUnlikeIsNotSentToThePreviousPhotoEither() async {
        prepare()
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"liked":false,"likes":2}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: social())
        model.setSignedIn(true)
        model.show(photoId: "p1", initialLikes: 3, liked: true)

        let answer = await model.toggleLike(gate: LikeCountStore(), shownId: "p2")

        XCTAssertNil(answer)
        XCTAssertTrue(StubProtocol.requests.isEmpty, "いいね済みの前の1枚を外しに行った: \(StubProtocol.requests)")
        XCTAssertTrue(model.liked)
    }

    /// 🔴 **取り消された読み込みは「読み込めませんでした」を立てない。** `try?` は取り消しも
    /// nil にするので、同じ1枚のまま `.task` が組み直された回（上に画面を積んだ・ログインの
    /// 状態が替わった）に、読めていたコメント欄が失敗の表示になっていた
    func testCancelledLoadDoesNotMarkCommentsUnavailable() async {
        prepare()
        // コメントは失敗で返す（取り消しの有無だけが結果を分けるように）
        StubProtocol.respond(path: "/user/comments/p1", status: 500, body: #"{"error":"x"}"#)
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":false,"count":1}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":1}"#)
        let gate = Gate()
        let model = PhotoDetailViewModel(photoId: "p1",
                                         social: social(gates: PathGates(["/user/comments/p1": gate])))
        model.setSignedIn(true)
        model.show(photoId: "p1", initialLikes: 1, liked: false)

        let load = Task { await model.load() }
        await gate.untilWaiting()
        load.cancel()
        await gate.open()
        await load.value

        XCTAssertFalse(model.commentsUnavailable, "取り消された読みで「読み込めませんでした」を立てた")
    }

    /// 取り消されていない失敗は、今までどおり「読み込めませんでした」を出す（直しの裏返し）
    func testFailedLoadStillMarksCommentsUnavailable() async {
        prepare()
        StubProtocol.respond(path: "/user/comments/p1", status: 500, body: #"{"error":"x"}"#)
        StubProtocol.respond(path: "/user/likes/p1", status: 200, body: #"{"liked":false,"count":1}"#)
        StubProtocol.respond(path: "/photos/p1/like", status: 200, body: #"{"likes":1}"#)
        let model = PhotoDetailViewModel(photoId: "p1", social: social())
        model.setSignedIn(true)
        model.show(photoId: "p1", initialLikes: 1, liked: false)

        await model.load()

        XCTAssertTrue(model.commentsUnavailable)
    }
}
