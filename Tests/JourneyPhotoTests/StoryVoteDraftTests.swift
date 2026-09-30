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

    /// ひとことの文字は**サーバーと同じ UTF-16 で** 200 に収める（`STORY_TEXT_LEN_MAX` は `slice`）。
    /// 字で数えると絵文字の文が 200 字入り、サーバーで黙って切られた。字の途中では切らない
    func testCaptionTextIsClampedInUTF16() throws {
        let flags = String(repeating: "🇯🇵", count: 60)   // 60 字・240 単位
        let text = try XCTUnwrap(StoryPostText.caption(flags).text)
        XCTAssertLessThanOrEqual(text.utf16.count, 200)
        XCTAssertEqual(text, String(repeating: "🇯🇵", count: 50), "字の境目で切る（旗の途中で割らない）")
        // 収まる文はそのまま
        XCTAssertEqual(StoryPostText.caption("夕方の港").text, "夕方の港")
    }

    /// 🔴 **撮影地か曲があると、ひとことをその行より上に置く。** 0.86 のままだと、見る画面の
    /// 下に出る撮影地・曲の行に重なった（アプリ・Web とも）
    func testCaptionClearsThePlaceAndSongLine() throws {
        let vote = StoryVoteDraft.new()   // 既定は y=0.7（下半分）
        // 行が無ければこれまでどおり
        XCTAssertEqual(try XCTUnwrap(StoryPostText.list(vote: vote, caption: "港"))[0].y, 0.86)

        // 1行のひとこと（字は絵の幅の 5%・行の高さ 1.2 倍）の上端と下端。
        // 置き方は `StoryTextItem.guide`（y の割合の点を、要素の同じ割合の点に合わせる）
        func span(y: Double, boxTop: Double, boxHeight: Double, boxWidth: Double) -> (top: Double, bottom: Double) {
            let h = boxWidth * 0.05 * 1.2
            let top = boxTop + boxHeight * y - h * y
            return (top, top + h)
        }
        for voteY in [0.7, 0.94, 0.5, 0.3, 0.06] {
            var v = vote
            v.y = voteY
            let y = try XCTUnwrap(StoryPostText.list(vote: v, caption: "港", hasMetaLine: true))[0].y
            // アプリ（絵を埋めて敷く・幅 390）: 撮影地＋曲の行の上端は枠の下から 96+16+8+16 = 136pt
            for frameHeight in [560.0, 700.0, 780.0] {
                let s = span(y: y, boxTop: 0, boxHeight: frameHeight, boxWidth: 390)
                XCTAssertLessThan(s.bottom, frameHeight - 136, "アプリ: 投票 y=\(voteY)・枠 \(frameHeight)")
            }
            // Web（絵を収めて敷く・390×844・返信の帯あり）: 縦 9:16 の絵は上 75px から 693px。
            // 撮影地（28）＋曲（36）＋間（8×2）＋下（16）＋帯（120）＋端の余白（34）＝ 594px が行の上端
            let web = span(y: y, boxTop: 75, boxHeight: 693, boxWidth: 390)
            XCTAssertLessThan(web.bottom, 594, "Web: 投票 y=\(voteY)")
            // 投票の札の真ん中とは離す（札の上か下へ逃がす）
            XCTAssertGreaterThan(abs(y - voteY), 0.2, "投票 y=\(voteY) の札に重ねない")
        }
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
