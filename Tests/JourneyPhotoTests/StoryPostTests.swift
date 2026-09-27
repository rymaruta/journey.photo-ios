import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 🔴 **「もう一度送る」で2本にしない**（`StoryService.post`）。
///
/// サーバーは行の id を毎回新しく作る（`story-${randomUUID()}`）ので、行が出来たのに
/// 返事だけ落ちた回に送り直すと2本になっていた。上げ終えた画像を覚えておき、
/// 送り直しの前に一覧で同じ画像の自分の1本を探す
final class StoryPostTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset()
    }

    override func tearDown() {
        StubProtocol.reset()
        super.tearDown()
    }

    private func service() -> StoryService {
        StoryService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                    tokenProvider: StubTokenProvider(token: "t"), session: session))
    }

    private let media = StoryService.UploadedMedia(
        key: "uploads/me/abc.jpg", publicUrl: "https://bucket.example/uploads/me/abc.jpg",
        uploadedAt: Date())

    private func job(uploaded: StoryService.UploadedMedia?) -> StoryUploadCenter.Job {
        StoryUploadCenter.Job(imageData: Data([1]), caption: "", location: "", coords: nil,
                              song: nil, durationSec: 5, archive: false, uploaded: uploaded)
    }

    /// 前の回で行が出来ていたら、**もう作らない**（一覧を読むだけ）
    func testDoesNotPostAgainWhenTheStoryIsAlreadyThere() async throws {
        StubProtocol.respond(status: 200, body:
            #"[{"id":"story-1","src":"https://cdn.example/uploads/me/abc.jpg","userId":"me"}]"#)
        try await service().post(job(uploaded: media), ownerId: "me", record: { _ in
            XCTFail("目印を書き換えた")
        })
        XCTAssertEqual(StubProtocol.requestCount, 1, "一覧のほかに叩いた（行をもう1本作った）")
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "GET")
    }

    /// 出来ていなければ、**上げ直さずに**同じ画像で行を作る
    func testPostsWithTheSameImageWhenTheStoryIsMissing() async throws {
        StubProtocol.respondInOrder([(200, "[]"), (201, #"{"success":true}"#)])
        try await service().post(job(uploaded: media), ownerId: "me", record: { _ in })
        XCTAssertEqual(StubProtocol.requestCount, 2)
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/stories")
        let body = try XCTUnwrap(StubProtocol.lastBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["publicUrl"] as? String, media.publicUrl)
    }

    /// **断られた**（4xx）ときだけ目印を消す——次は上げ直す
    func testForgetsTheImageOnlyWhenTheServerRefuses() async {
        StubProtocol.respondInOrder([(200, "[]"), (429, #"{"error":"上限"}"#), (200, "{}")])
        var recorded: [StoryService.UploadedMedia?] = []
        do {
            try await service().post(job(uploaded: media), ownerId: "me", record: { recorded.append($0) })
            XCTFail("投げていない")
        } catch {}
        XCTAssertEqual(recorded.count, 1)
        XCTAssertNil(recorded.first ?? media)
        XCTAssertEqual(StubProtocol.requestCount, 3, "画像を片づけていない")
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/upload/discard")
    }

    /// 🔴 **古い目印は使わない。** 一覧は期限内の行しか返さず、画像の実体も
    /// 掃除で消えている——使うと壊れた画像の1本が出る
    func testOldMediaIsNotReused() {
        let now = Date()
        XCTAssertTrue(StoryService.UploadedMedia(key: "k", publicUrl: "u",
                                                 uploadedAt: now.addingTimeInterval(-60)).isFresh(now: now))
        XCTAssertFalse(StoryService.UploadedMedia(key: "k", publicUrl: "u",
                                                  uploadedAt: now.addingTimeInterval(-23 * 3600 - 1)).isFresh(now: now))
        XCTAssertFalse(StoryService.UploadedMedia(key: "k", publicUrl: "u", uploadedAt: nil).isFresh(now: now),
                       "時刻の無い目印を信じた")
    }

    /// **届いたか分からない**失敗（5xx・通信）では目印を残す（送り直しで一覧を照らす）
    func testKeepsTheImageWhenItIsUnclear() async {
        StubProtocol.respondInOrder([(200, "[]"), (504, #"{"error":"timeout"}"#)])
        var recorded: [StoryService.UploadedMedia?] = []
        do {
            try await service().post(job(uploaded: media), ownerId: "me", record: { recorded.append($0) })
            XCTFail("投げていない")
        } catch {}
        XCTAssertEqual(recorded.count, 0)
    }

    private var staleMedia: StoryService.UploadedMedia {
        StoryService.UploadedMedia(key: media.key, publicUrl: media.publicUrl,
                                   uploadedAt: Date().addingTimeInterval(-23.5 * 3600))
    }

    /// 🔴 **古い目印でも、まだ出ている1本があれば作らない**（23〜24時間の間は期限内）
    func testOldMediaStillChecksTheList() async throws {
        StubProtocol.respond(status: 200, body:
            #"[{"id":"story-1","src":"https://cdn.example/uploads/me/abc.jpg","userId":"me"}]"#)
        try await service().post(job(uploaded: staleMedia), ownerId: "me", record: { _ in
            XCTFail("目印を書き換えた")
        })
        XCTAssertEqual(StubProtocol.requestCount, 1)
    }

    /// 古い目印で出ていなければ、**前の画像を片づけてから上げ直す**（行は古い画像で作らない）
    func testOldMediaIsDiscardedAndUploadedAgain() async {
        // 一覧 → 片づけ → 置き場所（ここで断らせて、上げ直しに入ったことだけ見る）
        StubProtocol.respondInOrder([(200, "[]"), (200, "{}"), (500, #"{"error":"x"}"#)])
        var recorded: [StoryService.UploadedMedia?] = []
        do {
            try await service().post(job(uploaded: staleMedia), ownerId: "me", record: { recorded.append($0) })
            XCTFail("投げていない")
        } catch {}
        XCTAssertEqual(StubProtocol.requestCount, 3)
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/upload/presigned-url", "古い画像で行を作った")
        XCTAssertEqual(recorded.count, 1)
        XCTAssertNil(recorded.first ?? media, "古い目印を忘れていない")
    }

    /// 片づけるのは**古い目印の鍵**（別の鍵を消さない）
    func testDiscardsTheOldKey() async {
        StubProtocol.respondInOrder([(200, "[]"), (500, #"{"error":"x"}"#)])
        do {
            try await service().post(job(uploaded: staleMedia), ownerId: "me", record: { _ in })
        } catch {}
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/upload/discard")
        let body = StubProtocol.lastBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        XCTAssertEqual(body?["key"] as? String, media.key)
    }

    /// 🔴 **片づけを 409 で断られたら、期限切れで一覧に出ないだけの1本が在る。**
    /// 上げ直さずに送ったことにする（上げ直すと同じ投稿がもう1本出る）
    func testOldMediaInUseCountsAsPosted() async throws {
        StubProtocol.respondInOrder([(200, "[]"), (409, #"{"error":"使われています"}"#)])
        try await service().post(job(uploaded: staleMedia), ownerId: "me", record: { _ in
            XCTFail("目印を書き換えた")
        })
        XCTAssertEqual(StubProtocol.requestCount, 2, "上げ直した")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/upload/discard")
    }

    /// 片づけが 401・429 で返ったら、**使用中かを確かめていない**ので投げる（目印を残す）
    func testOldMediaThrottledDiscardKeepsTheMark() async {
        for status in [401, 429] {
            StubProtocol.reset()
            StubProtocol.respondInOrder([(200, "[]"), (status, #"{"error":"x"}"#)])
            do {
                try await service().post(job(uploaded: staleMedia), ownerId: "me", record: { _ in
                    XCTFail("\(status) で目印を書き換えた")
                })
                XCTFail("\(status) で投げていない")
            } catch {}
            XCTAssertEqual(StubProtocol.requestCount, 2, "\(status) で上げ直した")
        }
    }

    /// 片づけられたか分からない（503）ときは投げる（出ていたか分からないまま上げ直さない）
    func testOldMediaUnclearDiscardThrows() async {
        StubProtocol.respondInOrder([(200, "[]"), (503, #"{"error":"x"}"#)])
        do {
            try await service().post(job(uploaded: staleMedia), ownerId: "me", record: { _ in
                XCTFail("目印を書き換えた")
            })
            XCTFail("投げていない")
        } catch {}
        XCTAssertEqual(StubProtocol.requestCount, 2)
    }
}
