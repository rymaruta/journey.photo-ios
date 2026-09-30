import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 今日の一問（`DailyQuiz`・Web の `/q` と同じファイルを読む）。
///
/// 固定したいのは:
///  1. **日本時間の暦日**のファイルを読む（端末の時刻帯・協定世界時で読まない）
///  2. 読み取りは Web の `parseDailyQuiz` と同じ弾き方（その日は「まだありません」に倒す）
///  3. 共有する文に**答えの名前を書かない**
///  4. 404 は「無い」、圏外・5xx・HTML は「読めなかった」（混ぜない）
final class DailyQuizTests: XCTestCase {

    /// Web が書き出す形（`lib/utils/dailyQuiz.ts` の `DailyQuiz`）
    static func json(date: String = "2026-10-01", licenseUrl: String = "https://creativecommons.org/licenses/by-sa/4.0",
                     answer: String = "sp_000000000002", photoURL: String = "https://journey-photo.com/images/spots/ginzan-onsen.jpg",
                     choices: String? = nil) -> String {
        let defaultChoices = """
        [{"spotId":"sp_000000000001","slug":"yamadera","name":"山寺","region":{"prefecture":"山形県","city":"山形市"}},
         {"spotId":"sp_000000000002","slug":"ginzan-onsen","name":"銀山温泉","region":{"prefecture":"山形県","city":"尾花沢市"}},
         {"spotId":"sp_000000000003","slug":"zao","name":"蔵王","region":{"prefecture":"山形県"}},
         {"spotId":"sp_000000000004","slug":"paris-opera","name":"オペラ座","region":{"country":"フランス","city":"パリ"}}]
        """
        return """
        {"date":"\(date)","photo":{"url":"\(photoURL)","author":"撮影者A","license":"CC BY-SA 4.0",
          "licenseUrl":"\(licenseUrl)","pageUrl":"https://commons.wikimedia.org/wiki/File:Ginzan.jpg"},
         "choices":\(choices ?? defaultChoices),"answer":"\(answer)"}
        """
    }

    private func parse(_ s: String, date: String = "2026-10-01") -> DailyQuiz? {
        DailyQuiz.parse(Data(s.utf8), date: date)
    }

    // MARK: - 日付

    func testTodayIsTheJapaneseCalendarDay() {
        // 2026-09-30 15:30 UTC ＝ 日本時間 10/1 00:30
        XCTAssertEqual(DailyQuiz.today(Date(timeIntervalSince1970: 1_790_782_200)), "2026-10-01")
        // 2026-09-30 14:59 UTC ＝ 日本時間 9/30 23:59
        XCTAssertEqual(DailyQuiz.today(Date(timeIntervalSince1970: 1_790_780_340)), "2026-09-30")
    }

    func testDateFormats() {
        XCTAssertEqual(DailyQuiz.shortDate("2026-10-01"), "10/1")
        XCTAssertEqual(DailyQuiz.dottedDate("2026-10-01"), "2026.10.01")
    }

    // MARK: - 読み取り

    func testReadsTheFileWebWrites() throws {
        let quiz = try XCTUnwrap(parse(Self.json()))
        XCTAssertEqual(quiz.choices.map(\.name), ["山寺", "銀山温泉", "蔵王", "オペラ座"])
        XCTAssertEqual(quiz.answerChoice.slug, "ginzan-onsen")
        XCTAssertEqual(quiz.photo.author, "撮影者A")
        XCTAssertEqual(quiz.photo.licenseUrl?.absoluteString, "https://creativecommons.org/licenses/by-sa/4.0")
        XCTAssertEqual(quiz.choices[1].regionLine, "山形県 尾花沢市")
        XCTAssertEqual(quiz.choices[3].regionLine, "フランス パリ", "海外は国から")
    }

    /// 写真の台帳に `http://creativecommons.org/…` の行がある（Web で 61日中5日リンクが消えかけた）
    func testKeepsAnHTTPLicenseLink() throws {
        let quiz = try XCTUnwrap(parse(Self.json(licenseUrl: "http://creativecommons.org/licenses/by-sa/3.0")))
        XCTAssertEqual(quiz.photo.licenseUrl?.absoluteString, "http://creativecommons.org/licenses/by-sa/3.0")
        XCTAssertNil(parse(Self.json(licenseUrl: "javascript:alert(1)"))?.photo.licenseUrl)
    }

    func testRejectsFilesThatBreakTheRules() {
        XCTAssertNil(parse(Self.json(date: "2026-10-02")), "頼んだ日付と違う")
        XCTAssertNil(parse(Self.json(answer: "sp_ffffffffffff")), "正解が選択肢に無い")
        XCTAssertNil(parse(Self.json(photoURL: "http://example.com/x.jpg")), "写真が https でない")
        XCTAssertNil(parse(Self.json(choices: """
        [{"spotId":"sp_000000000001","slug":"a","name":"A"},{"spotId":"sp_000000000002","slug":"b","name":"B"},
         {"spotId":"sp_000000000003","slug":"c","name":"C"}]
        """)), "選択肢が4つでない")
        XCTAssertNil(parse(Self.json(choices: """
        [{"spotId":"sp_000000000001","slug":"a","name":"A"},{"spotId":"sp_000000000002","slug":"b","name":"B"},
         {"spotId":"sp_000000000002","slug":"c","name":"C"},{"spotId":"sp_000000000003","slug":"d","name":"D"}]
        """)), "同じ選択肢がある")
        XCTAssertNil(parse(Self.json(choices: """
        [{"spotId":"sp_000000000001","slug":"../x","name":"A"},{"spotId":"sp_000000000002","slug":"b","name":"B"},
         {"spotId":"sp_000000000003","slug":"c","name":"C"},{"spotId":"sp_000000000004","slug":"d","name":"D"}]
        """)), "綴りの形が違う")
        XCTAssertNil(parse(Self.json().replacingOccurrences(of: "\"author\":\"撮影者A\"", with: "\"author\":\"\"")),
                     "作者が無い写真は出さない（CC の表示条件を満たせない）")
        XCTAssertNil(parse("null"))
        XCTAssertNil(parse("<html>"))
    }

    // MARK: - 共有

    func testShareTextCarriesNoAnswer() throws {
        let url = URL(string: "https://journey-photo.com/q")!
        let right = DailyQuiz.shareText(date: "2026-10-01", correct: true, url: url)
        let wrong = DailyQuiz.shareText(date: "2026-10-01", correct: false, url: url)
        XCTAssertTrue(right.contains("10/1") && right.contains("✓"))
        XCTAssertTrue(wrong.contains("✗"))
        XCTAssertTrue(right.hasSuffix("https://journey-photo.com/q"))
        let quiz = try XCTUnwrap(parse(Self.json()))
        for name in quiz.choices.map(\.name) {
            XCTAssertFalse(right.contains(name)); XCTAssertFalse(wrong.contains(name))
        }
    }

    // MARK: - 端末に残す答え

    func testAnswersAreKeptPerDateAndDroppedWhenTheQuestionChanged() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "quiz-\(UUID().uuidString)"))
        let answers = QuizAnswers(defaults: defaults)
        let quiz = try XCTUnwrap(parse(Self.json()))
        XCTAssertNil(answers.chosen(for: quiz))
        answers.save("sp_000000000003", date: "2026-10-01")
        XCTAssertEqual(answers.chosen(for: quiz), "sp_000000000003")
        XCTAssertEqual(QuizAnswers.key("2026-10-01"), "journey-photo:quiz:2026-10-01", "Web と同じ鍵の形")
        // 選んだものがその日の選択肢に無い（問題が差し替わった）→ 答えていない扱い
        answers.save("sp_999999999999", date: "2026-10-01")
        XCTAssertNil(answers.chosen(for: quiz))
        // 別の日には持ち越さない
        let tomorrow = try XCTUnwrap(parse(Self.json(date: "2026-10-02"), date: "2026-10-02"))
        answers.save("sp_000000000001", date: "2026-10-01")
        XCTAssertNil(answers.chosen(for: tomorrow))
    }
}

/// 今日の一問の読み込み（`DailyQuizService`）
final class DailyQuizServiceTests: XCTestCase {

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

    private func service() -> DailyQuizService {
        DailyQuizService(session: session) { URL(string: "https://site.example.test/app/data/quiz/\($0).json")! }
    }

    func testReadsTheDayFileAndRemembersIt() async throws {
        StubProtocol.respond(status: 200, body: DailyQuizTests.json(), contentType: "application/json")
        let s = service()
        guard case .ready(let quiz) = try await s.fetch(date: "2026-10-01") else { return XCTFail("読めていない") }
        XCTAssertEqual(quiz.answer, "sp_000000000002")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/app/data/quiz/2026-10-01.json")
        // 2回目は取りに行かない（ホームの札と画面で2回読まない）
        StubProtocol.respond(status: 500, body: "")
        guard case .ready = try await s.fetch(date: "2026-10-01") else { return XCTFail("覚えていない") }
    }

    func testMissingFileIsNone() async throws {
        StubProtocol.respond(status: 404, body: "Not Found")
        let result = try await service().fetch(date: "2026-10-01")
        XCTAssertEqual(result, .none)
    }

    func testWrongDayInsideTheFileIsNone() async throws {
        StubProtocol.respond(status: 200, body: DailyQuizTests.json(date: "2026-09-30"), contentType: "application/json")
        let result = try await service().fetch(date: "2026-10-01")
        XCTAssertEqual(result, .none)
    }

    /// 「読めなかった」を「まだありません」と言わない
    func testServerErrorAndHTMLThrow() async {
        StubProtocol.respond(status: 503, body: "")
        do { _ = try await service().fetch(date: "2026-10-01"); XCTFail("5xx で投げていない") } catch {}
        StubProtocol.respond(status: 200, body: "<html>login</html>", contentType: "text/html; charset=utf-8")
        do { _ = try await service().fetch(date: "2026-10-01"); XCTFail("HTML で投げていない") } catch {}
    }
}
