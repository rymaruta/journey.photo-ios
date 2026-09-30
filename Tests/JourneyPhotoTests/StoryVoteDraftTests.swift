import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 作る画面の投票スタンプ（焼き込まずに `texts` の `kind: "vote"` で送る）
final class StoryVoteDraftTests: XCTestCase {

    /// 欠けた投票は送れない（サーバーの `isCompleteStoryVote` と同じ判断・空白だけも欠け）
    func testCompleteness() {
        var v = StoryVoteDraft.new()
        XCTAssertTrue(v.isComplete)
        v.optionB = "   "
        XCTAssertFalse(v.isComplete)
        v.optionB = "いいえ"
        v.question = ""
        XCTAssertFalse(v.isComplete)
    }

    /// 字数はサーバーと同じ（問い40・選択肢12）**を UTF-16 で数える**（絵文字は2つ以上）。改行は空白に
    func testLimits() {
        XCTAssertEqual(StoryVoteDraft.limited(old: "", new: String(repeating: "あ", count: 50), max: StoryVoteDraft.questionMax).count, 40)
        XCTAssertEqual(StoryVoteDraft.limited(old: "", new: "はい\nいいえ", max: 12), "はい いいえ")
        // 🇯🇵 は4単位。12単位に3つまで（字で数えると12個入って、サーバーで黙って切られた）
        let flags = StoryVoteDraft.limited(old: "", new: String(repeating: "🇯🇵", count: 12), max: StoryVoteDraft.optionMax)
        XCTAssertLessThanOrEqual(flags.utf16.count, 12)
    }

    /// 見えている範囲（絵を埋めて敷くと端が画面の外）。**その外へは動かさない**
    func testMoveStaysInTheVisiblePart() throws {
        // 絵は画面より横に広い（左右に 120pt ずつはみ出す）
        let photo = CGRect(x: -120, y: 0, width: 640, height: 800)
        let visible = try XCTUnwrap(StoryVoteDraft.visibleRange(photo: photo, canvas: CGSize(width: 400, height: 800)))
        XCTAssertGreaterThan(visible.x.lowerBound, 120.0 / 640)
        XCTAssertLessThan(visible.x.upperBound, 520.0 / 640)
        let far = StoryVoteDraft.new().moved(by: CGSize(width: 9999, height: 0), in: photo.size, visible: visible)
        XCTAssertEqual(far.x, visible.x.upperBound, accuracy: 1e-9)
    }

    /// 動かした量は絵の矩形に対する割合。幅はサーバーと同じ（0.06〜0.94）
    func testMoveIsRelativeAndClamped() {
        let v = StoryVoteDraft.new().moved(by: CGSize(width: 40, height: -80), in: CGSize(width: 400, height: 800))
        XCTAssertEqual(v.x, 0.6, accuracy: 1e-9)
        XCTAssertEqual(v.y, 0.6, accuracy: 1e-9)
        let far = StoryVoteDraft.new().moved(by: CGSize(width: 9999, height: 9999), in: CGSize(width: 400, height: 800))
        XCTAssertEqual(far.x, 0.94, accuracy: 1e-9)
        XCTAssertEqual(far.y, 0.94, accuracy: 1e-9)
    }

    /// 🔴 **投票を送る1本は、ひとことも文字として送る**——`texts` を送るとサーバーは `caption` を
    /// 文字の並びから作り直すので、投票だけだと打ったひとことが消える
    func testPostTextsKeepTheCaption() throws {
        let vote = StoryVoteDraft(question: " 好き？ ", optionA: "はい", optionB: "いいえ", x: 0.5, y: 0.7, size: 0.05)
        let list = try XCTUnwrap(StoryPostText.list(vote: vote, caption: "  夕方の港  "))
        XCTAssertEqual(list.map(\.kind), ["text", "vote"])
        XCTAssertEqual(list[0].text, "夕方の港")
        XCTAssertEqual(list[1].question, "好き？")
        XCTAssertEqual(list[1].options, ["はい", "いいえ"])
        // ひとことが無ければ投票だけ
        XCTAssertEqual(StoryPostText.list(vote: vote, caption: " ")?.map(\.kind), ["vote"])
        // 投票が無い・欠けていれば送らない（これまでと同じ `caption` だけ）
        XCTAssertNil(StoryPostText.list(vote: nil, caption: "港"))
        var broken = vote
        broken.optionA = ""
        XCTAssertNil(StoryPostText.list(vote: broken, caption: "港"))
    }

    /// 送る形の鍵はサーバーの `sanitizeStoryTexts` が読むもの。**無い項目は書かない**
    func testPostTextEncoding() throws {
        let vote = StoryPostText.vote(StoryVoteDraft(question: "Q", optionA: "A", optionB: "B", x: 2, y: 0.5, size: 1))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(vote)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["kind", "x", "y", "size", "question", "options"])
        XCTAssertEqual(json["x"] as? Double, 0.94, "位置は送る前に挟む")
        XCTAssertEqual(json["size"] as? Double, 0.16)
        let caption = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(StoryPostText.caption("港"))) as? [String: Any])
        XCTAssertEqual(Set(caption.keys), ["kind", "x", "y", "size", "text", "font", "color", "bg"])
        XCTAssertEqual(caption["font"] as? String, "mincho")
    }

    /// 閲覧画面と同じ札で描く形（読み戻しと同じ）
    func testAsItemMatchesWhatTheViewerReads() {
        let v = StoryVoteDraft(question: "好き？", optionA: "はい", optionB: "いいえ", x: 0.3, y: 0.6, size: 0.05)
        guard case .vote(let item) = v.asItem else { return XCTFail() }
        XCTAssertEqual(item.question, "好き？")
        XCTAssertEqual(item.options, ["はい", "いいえ"])
        XCTAssertEqual(item.place, .init(x: 0.3, y: 0.6, size: 0.05, rotate: 0))
    }
}

/// `POST /stories` の本文に `texts` が乗る
final class StoryPostTextsRequestTests: XCTestCase {

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
        key: "uploads/me/abc.jpg", publicUrl: "https://bucket.example/uploads/me/abc.jpg", uploadedAt: Date())

    func testTextsAreSentWhenGiven() async throws {
        StubProtocol.respond(status: 201, body: #"{"success":true}"#)
        let texts = StoryPostText.list(vote: .new(), caption: "港")
        _ = try await service().createRecord(media, caption: "港", location: nil, coords: nil, texts: texts)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(StubProtocol.lastBody)) as? [String: Any])
        let sent = try XCTUnwrap(body["texts"] as? [[String: Any]])
        XCTAssertEqual(sent.map { $0["kind"] as? String }, ["text", "vote"])
        XCTAssertEqual(body["caption"] as? String, "港")
    }

    /// 投票が無ければ `texts` を送らない（送ると `caption` がサーバーで作り直される）
    func testNoTextsKeyWithoutAVote() async throws {
        StubProtocol.respond(status: 201, body: #"{"success":true}"#)
        _ = try await service().createRecord(media, caption: "港", location: nil, coords: nil)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(StubProtocol.lastBody)) as? [String: Any])
        XCTAssertNil(body["texts"])
        XCTAssertEqual(body["caption"] as? String, "港")
    }
}
