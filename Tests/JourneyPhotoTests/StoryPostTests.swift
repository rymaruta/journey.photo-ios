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
        key: "uploads/me/abc.jpg", publicUrl: "https://bucket.example/uploads/me/abc.jpg")

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
}
