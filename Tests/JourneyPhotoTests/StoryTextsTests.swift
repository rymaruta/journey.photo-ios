import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Web のストーリーが**データで**置いた文字・スタンプ・投票（`texts`）を読む。
/// 読んでいなかったので、アプリでは写真だけに見え、投票もできなかった
final class StoryTextsTests: XCTestCase {

    private func story(_ extra: String) throws -> Story {
        let json = #"{"id":"s1","src":"https://cdn.example/a.jpg","userId":"u1""# + extra + "}"
        return try JSONDecoder().decode(Story.self, from: Data(json.utf8))
    }

    func testReadsTextStampAndVote() throws {
        let s = try story(#","texts":[{"text":"港","x":0.2,"y":0.3,"size":0.1,"font":"mincho","color":"yellow","bg":"soft","rotate":-15},{"kind":"stamp","stamp":"heart","x":0.5,"y":0.5,"size":0.14},{"kind":"vote","question":"この景色、好き？","options":["はい","いいえ"],"x":0.5,"y":0.7,"size":0.05}],"vote":{"myVote":"a","counts":{"a":3,"b":1}}"#)
        XCTAssertEqual(s.texts.count, 3)
        guard case .text(let label) = s.texts[0] else { return XCTFail("文字が読めていない") }
        XCTAssertEqual(label.text, "港")
        XCTAssertEqual(label.font, "mincho")
        XCTAssertEqual(label.color, "yellow")
        XCTAssertEqual(label.bg, "soft")
        XCTAssertEqual(label.place, .init(x: 0.2, y: 0.3, size: 0.1, rotate: -15))
        guard case .stamp(let stamp) = s.texts[1] else { return XCTFail("スタンプが読めていない") }
        XCTAssertEqual(stamp.glyph, "❤️")
        XCTAssertEqual(s.voteItem?.question, "この景色、好き？")
        XCTAssertEqual(s.voteItem?.options, ["はい", "いいえ"])
        XCTAssertEqual(s.vote?.myVote, "a")
        XCTAssertEqual(s.vote?.counts, .init(a: 3, b: 1))
    }

    /// 🔴 **壊れた1つで一覧ごと落とさない**（1本の形が崩れると全員のストーリーが消える）。
    /// 知らない種類・知らない絵柄・中身の無いもの・欠けた投票は落とし、残りは読む
    func testBrokenItemsAreDroppedNotTheStory() throws {
        let s = try story(#","texts":[{"text":"残る"},{"kind":"poll","text":"知らない種類"},{"kind":"stamp","stamp":"unicorn"},{"text":"   "},{"kind":"vote","question":"問い","options":["はい",""]},{"x":"壊れ","text":"位置が壊れても文字は残る"},42,"文字列"],"vote":"壊れ""#)
        XCTAssertEqual(s.texts.count, 2)
        guard case .text(let broken) = s.texts[1] else { return XCTFail() }
        XCTAssertEqual(broken.place.x, 0.5, "読めない位置は真ん中")
        XCTAssertNil(s.vote)
        XCTAssertNil(s.voteItem)
        // 形がまるごと違っても投稿は読める
        XCTAssertEqual(try story(#","texts":"壊れ""#).texts, [])
        XCTAssertEqual(try story("").texts, [])
    }

    /// 知らない字体・色・下地は Web と同じ既定（太ゴシック・白・無し）。位置・大きさ・傾きは挟む
    func testDefaultsAndClampsLikeTheWeb() throws {
        let s = try story(#","texts":[{"text":"a","font":"comic","color":"gold","bg":"glass","x":2,"y":-1,"size":9,"rotate":540}]"#)
        guard case .text(let label) = s.texts.first else { return XCTFail() }
        XCTAssertEqual(label.font, "bold")
        XCTAssertEqual(label.color, "white")
        XCTAssertEqual(label.bg, "none")
        XCTAssertEqual(label.place, .init(x: 0.94, y: 0.06, size: 0.16, rotate: 180))
        XCTAssertEqual(StoryTextItem.normalizeRotate(-190), 170)
        XCTAssertEqual(StoryTextItem.normalizeRotate(nil), 0)
    }

    /// 投票は1投稿に1つだけ（2つ目以降は落とす・Web と同じ）
    func testOnlyOneVote() throws {
        let s = try story(#","texts":[{"kind":"vote","question":"1","options":["a","b"]},{"kind":"vote","question":"2","options":["c","d"]}]"#)
        XCTAssertEqual(s.texts.count, 1)
        XCTAssertEqual(s.voteItem?.question, "1")
    }

    /// 割合は合わせて100。数が見えない・0票なら出さない
    func testVotePercents() {
        XCTAssertEqual(StoryVoteState(myVote: nil, counts: .init(a: 1, b: 2)).percents?.a, 33)
        XCTAssertEqual(StoryVoteState(myVote: nil, counts: .init(a: 1, b: 2)).percents?.b, 67)
        XCTAssertNil(StoryVoteState(myVote: "a", counts: .init(a: 0, b: 0)).percents)
        XCTAssertNil(StoryVoteState(myVote: nil, counts: nil).percents)
    }

    /// 置き場所: `(x, y)` の割合の点を要素の同じ割合の点に合わせる（中心ではない・Web の
    /// `translate(-x%)`）。要素の頭 = −(揃えの線)
    func testGuideFollowsTheWebAnchor() {
        // 真ん中: 幅100の要素を幅400の絵の真ん中に置くと、頭は150（中心が200）
        XCTAssertEqual(-StoryTextItem.guide(fraction: 0.5, element: 100, boxStart: 0, boxLength: 400), 150)
        // x=0.1: 頭は 40 − 10 = 30（中心ではなく、要素の1割の点が絵の1割の点に来る）
        XCTAssertEqual(-StoryTextItem.guide(fraction: 0.1, element: 100, boxStart: 0, boxLength: 400), 30, accuracy: 1e-9)
        // 絵が画面からはみ出している（埋めて敷いた）ときは絵の頭から数える
        XCTAssertEqual(-StoryTextItem.guide(fraction: 0.5, element: 100, boxStart: -120, boxLength: 640), 150)
    }
}

/// 票を送る（`POST /stories/{id}/vote`）
final class StoryVoteRequestTests: XCTestCase {

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

    func testVoteSendsTheChoiceAndReadsTheState() async throws {
        StubProtocol.respond(status: 200, body: #"{"success":true,"myVote":"b","counts":{"a":2,"b":5}}"#)
        let service = StoryService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                                  tokenProvider: StubTokenProvider(token: "t"), session: session))
        let state = try await service.vote(id: "story-1", choice: "b")
        XCTAssertEqual(state, StoryVoteState(myVote: "b", counts: .init(a: 2, b: 5)))
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/stories/story-1/vote")
        let body = try XCTUnwrap(StubProtocol.lastBody)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String], ["choice": "b"])
    }
}
