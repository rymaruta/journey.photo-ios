import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 撮影スポットの本文（`SpotBody`・Web の `lib/data/spotBody.ts`）。
/// 🔴 **印の無い本文は読まない**・Web と同じ言葉で出す
final class SpotBodyTests: XCTestCase {

    private func decode(_ json: String) throws -> SpotBody {
        try JSONDecoder.api.decode(SpotBody.self, from: Data(json.utf8))
    }

    static let aiBody = """
    {"spotId":"sp_1","slug":"kinkakuji","description":"  金閣。 ",
     "highlights":["鏡湖池",1,"  "],"seasonalGuide":[{"season":"autumn","text":"紅葉"},{"season":"x","text":"?"},{"bad":1}],
     "timeOfDayGuide":[{"time":"night","text":"夜"},{"time":"morning","text":"朝"}],
     "compositionTips":["広角で"],"officialWebsiteUrl":"https://www.shokoku-ji.jp/kinkakuji/",
     "check":{"kind":"ai","checkedAt":"2026-09-27","sources":[
        {"url":"https://ja.wikipedia.org/wiki/x","title":"Wikipedia「鹿苑寺」"},
        {"url":"http://insecure.example/","title":"平文"},{"url":"https://no-title.example/"}]}}
    """

    func testDecodesAIBodyAndDropsBrokenItems() throws {
        let body = try decode(Self.aiBody)
        XCTAssertEqual(body.slug, "kinkakuji")
        XCTAssertEqual(body.description, "金閣。")
        XCTAssertEqual(body.highlights, ["鏡湖池"], "壊れた要素・空白だけの要素は落とす")
        XCTAssertEqual(body.seasonalGuide.map(\.season), ["autumn"], "壊れた要素と知らない季節を落とす")
        XCTAssertEqual(body.officialWebsite?.host, "www.shokoku-ji.jp")
        guard case .ai(let day, let sources) = body.check else { return XCTFail("AI 照合の印") }
        XCTAssertEqual(day, "2026-09-27")
        XCTAssertEqual(sources.map(\.title), ["Wikipedia「鹿苑寺」"], "https で題のある出典だけ")
        XCTAssertTrue(body.hasContent)
    }

    /// 時刻帯（2026-10-07）。書いた行だけ載る。文字でなければ nil で、本文ごとは落とさない
    func testTimeZoneIsOptionalAndLenient() throws {
        let check = #""check":{"kind":"human","verifiedAt":"2026-09-25"}"#
        XCTAssertEqual(try decode(#"{"slug":"a","timeZone":" Australia/Sydney ",\#(check)}"#).timeZone, "Australia/Sydney")
        XCTAssertNil(try decode(#"{"slug":"a",\#(check)}"#).timeZone)
        XCTAssertNil(try decode(#"{"slug":"a","timeZone":9,\#(check)}"#).timeZone)
    }

    func testHumanCheck() throws {
        let body = try decode(#"{"slug":"a","highlights":["x"],"check":{"kind":"human","verifiedAt":"2026-09-25"}}"#)
        XCTAssertEqual(body.check, .human(verifiedAt: "2026-09-25"))
    }

    /// 🔴 **印の無い・読めない本文は捨てる**（出典の無い事実を出さない）
    func testBodyWithoutAValidMarkIsRejected() {
        XCTAssertThrowsError(try decode(#"{"slug":"a","highlights":["x"]}"#), "印が無い")
        XCTAssertThrowsError(try decode(#"{"slug":"a","check":{"kind":"robot","checkedAt":"2026-09-27"}}"#), "知らない印")
        XCTAssertThrowsError(try decode(#"{"slug":"a","check":{"kind":"ai","checkedAt":"2026-09-27","sources":[]}}"#), "出典0本")
        XCTAssertThrowsError(try decode(#"{"slug":"a","check":{"kind":"ai","checkedAt":"2026-09-27","sources":[{"url":"http://x","title":"t"}]}}"#),
                             "https の出典が無い")
        XCTAssertThrowsError(try decode(#"{"slug":"a","check":{"kind":"human","verifiedAt":"いつか"}}"#), "日付が読めない")
    }

    /// 日付は日付の10文字だけ出す・実在しない日は通さない
    func testCheckDatesAreDaysOnly() throws {
        let timed = try decode(#"{"slug":"a","check":{"kind":"human","verifiedAt":"2026-09-25T10:00:00Z"}}"#)
        XCTAssertEqual(timed.check, .human(verifiedAt: "2026-09-25"))
        XCTAssertThrowsError(try decode(#"{"slug":"a","check":{"kind":"human","verifiedAt":"2026-02-31"}}"#))
        XCTAssertThrowsError(try decode(#"{"slug":"a","check":{"kind":"ai","checkedAt":"2026-13-01","sources":[{"url":"https://x","title":"t"}]}}"#))
    }

    func testNonHTTPSOfficialSiteIsDropped() throws {
        let body = try decode(#"{"slug":"a","officialWebsiteUrl":"http://x.example/","check":{"kind":"human","verifiedAt":"2026-09-25"}}"#)
        XCTAssertNil(body.officialWebsite)
        XCTAssertFalse(body.hasContent, "本文の節が無ければ節ごと出さない")
    }

    // MARK: - 言い方（Web の SpotGuideClient と同じ）

    /// 日本語の呼び名は Web の `TIME_LABEL`・`SEASON_LABEL` と同じ（6つ・4つ全部）
    func testLabelsMatchTheWeb() {
        let web = ["dawn": "夜明け", "morning": "朝", "day": "日中", "goldenHour": "夕方の斜光", "dusk": "日没後", "night": "夜"]
        let english = ["dawn": "Dawn", "morning": "Morning", "day": "Daytime", "goldenHour": "Golden hour", "dusk": "Blue hour", "night": "Night"]
        for key in SpotBodyText.timeOrder {
            XCTAssertEqual(SpotBodyText.timeLabel(key), L(web[key]!, english[key]!), key)
        }
        let seasons = ["spring": "春", "summer": "夏", "autumn": "秋", "winter": "冬"]
        for key in SpotBodyText.seasonOrder {
            XCTAssertEqual(SpotBodyText.seasonLabel(key).map { L(seasons[key]!, $0) }, SpotBodyText.seasonLabel(key), key)
        }
        XCTAssertNil(SpotBodyText.seasonLabel("rainy"))
        XCTAssertNil(SpotBodyText.timeLabel("noon"))
    }

    func testSeasonOfMonth() {
        XCTAssertEqual((1...12).map { SpotBodyText.season(ofMonth: $0) },
                       ["winter", "winter", "spring", "spring", "spring", "summer",
                        "summer", "summer", "autumn", "autumn", "autumn", "winter"])
    }

    /// 今の季節を先頭に、そこから巡る順（次に来る季節が2番目）。知らない季節は落とす
    func testCurrentSeasonComesFirst() {
        let list = ["winter", "spring", "x", "autumn", "summer"].map { SpotBody.Seasonal(season: $0, text: $0) }
        XCTAssertEqual(SpotBodyText.orderedSeasons(list, current: "autumn").map(\.season),
                       ["autumn", "winter", "spring", "summer"])
        XCTAssertEqual(SpotBodyText.orderedSeasons(list, current: "winter").map(\.season),
                       ["winter", "spring", "summer", "autumn"])
        XCTAssertEqual(SpotBodyText.orderedSeasons(list, current: "spring").map(\.season),
                       ["spring", "summer", "autumn", "winter"])
    }

    /// 🔴 知らない季節・時間帯だけの本文は「本文あり」にしない（描けない値で節を開かない）
    func testUnknownSeasonsAndTimesAreNotContent() throws {
        let body = try decode(#"{"slug":"a","seasonalGuide":[{"season":"rainy","text":"梅雨"},{"season":"autumn","text":"紅葉"}],"timeOfDayGuide":[{"time":"noon","text":"昼"}],"check":{"kind":"human","verifiedAt":"2026-09-25"}}"#)
        XCTAssertEqual(body.seasonalGuide.map(\.season), ["autumn"])
        XCTAssertTrue(body.timeOfDayGuide.isEmpty)
        let only = try decode(#"{"slug":"a","seasonalGuide":[{"season":"rainy","text":"梅雨"}],"check":{"kind":"human","verifiedAt":"2026-09-25"}}"#)
        XCTAssertFalse(only.hasContent)
    }

    /// 出典の配列の中の壊れた1本（文字列・題なし・http）だけ落とし、残りは読む
    func testBrokenSourcesAreDroppedOneByOne() throws {
        let body = try decode(#"{"slug":"a","check":{"kind":"ai","checkedAt":"2026-09-27","sources":["x",{"url":"https://a.example/","title":""},{"url":"http://b.example/","title":"B"},{"url":"https://c.example/","title":" C "}]}}"#)
        XCTAssertEqual(body.check, .ai(checkedAt: "2026-09-27", sources: [SpotBody.Source(url: URL(string: "https://c.example/")!, title: "C")]))
    }

    func testTimesInFixedOrder() {
        let list = ["night", "x", "dawn", "goldenHour"].map { SpotBody.TimeOfDay(time: $0, text: $0) }
        XCTAssertEqual(SpotBodyText.orderedTimes(list).map(\.time), ["dawn", "goldenHour", "night"])
    }

    /// 🔴 **「運営」と名乗るのは人の確認だけ**。AI 照合は出典を書く
    func testCheckLine() {
        let human = SpotBodyText.checkLine(.human(verifiedAt: "2026-09-25"))
        let ai = SpotBodyText.checkLine(.ai(checkedAt: "2026-09-27", sources: [
            SpotBody.Source(url: URL(string: "https://a")!, title: "A"),
            SpotBody.Source(url: URL(string: "https://b")!, title: "B")]))
        XCTAssertEqual(human, L("情報の最終確認: 2026-09-25（運営）", "Last checked: 2026-09-25 (by our team)"))
        XCTAssertEqual(ai, L("出典: A、B（AI 照合 2026-09-27）", "Source: A, B (checked by AI against the source, 2026-09-27)"))
        XCTAssertFalse(ai.contains(L("運営", "our team")))
    }

    /// 出典の題は押せる（Web は題ごとにリンク）。文字は `checkLine` と同じ
    func testLinkedCheckLineLinksEachSource() {
        let check = SpotBody.Check.ai(checkedAt: "2026-09-27", sources: [
            SpotBody.Source(url: URL(string: "https://a.example/")!, title: "A"),
            SpotBody.Source(url: URL(string: "https://b.example/")!, title: "B")])
        let line = SpotBodyText.linkedCheckLine(check)
        XCTAssertEqual(String(line.characters), SpotBodyText.checkLine(check))
        let links = line.runs.compactMap(\.link)
        XCTAssertEqual(links.map(\.absoluteString), ["https://a.example/", "https://b.example/"])
        XCTAssertTrue(SpotBodyText.linkedCheckLine(.human(verifiedAt: "2026-09-25")).runs.allSatisfy { $0.link == nil })
    }
}

/// 本文を取りに行く口（`OfficialSpotService.fetchBody`）。**取れなければ nil で、投げない**
final class SpotBodyServiceTests: XCTestCase {

    private var session: URLSession!
    private let url = URL(string: "https://site.example.test/app/data/spots.json")!

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

    private func service(bodyLifetime: TimeInterval = OfficialSpotService.cacheLifetime) -> OfficialSpotService {
        OfficialSpotService(url: url, session: session, snapshot: SpotSnapshotStore(fileName: UUID().uuidString),
                            bodyLifetime: bodyLifetime)
    }

    func testFetchesTheBodyNextToTheIndex() async {
        StubProtocol.respond(status: 200, body: SpotBodyTests.aiBody)
        let body = await service().fetchBody(slug: "kinkakuji")
        XCTAssertEqual(body?.slug, "kinkakuji")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.absoluteString,
                       "https://site.example.test/app/data/spots/kinkakuji.json")
    }

    /// まだ本番に無い（404）・HTML（キャプティブポータル）は nil。404 は覚えて叩き直さない
    func testMissingOrHTMLGivesNil() async {
        let s = service()
        StubProtocol.respond(status: 404, body: "")
        let missing = await s.fetchBody(slug: "kinkakuji")
        XCTAssertNil(missing)
        let again = await s.fetchBody(slug: "kinkakuji")
        XCTAssertNil(again)
        XCTAssertEqual(StubProtocol.requestCount, 1, "無いことを覚えて叩き直さない")

        // 種別が HTML なら、中身が本文として読めても使わない（キャプティブポータル）
        StubProtocol.respond(status: 200, body: SpotBodyTests.aiBody, contentType: "text/html; charset=utf-8")
        let html = await service().fetchBody(slug: "kinkakuji")
        XCTAssertNil(html)
    }

    /// 🔴 **下書きに戻した（404 になった）場所の古い本文を出さない**
    func testUnpublishedBodyIsNotServedFromTheMemo() async {
        let s = service(bodyLifetime: 0)
        StubProtocol.respond(status: 200, body: SpotBodyTests.aiBody)
        let first = await s.fetchBody(slug: "kinkakuji")
        XCTAssertNotNil(first)
        StubProtocol.respond(status: 404, body: "")
        let after = await s.fetchBody(slug: "kinkakuji")
        XCTAssertNil(after, "消えた本文を控えから出している")
    }

    /// 既定の控えは短い（索引と同じ60秒）。長く覚えるのは「無い」だけ（10分）
    func testBodyMemoIsShort() async {
        let s = OfficialSpotService(url: url, session: session, snapshot: SpotSnapshotStore(fileName: UUID().uuidString))
        let (body, missing) = await (s.bodyLifetime, s.missingBodyLifetime)
        XCTAssertEqual(body, 60)
        XCTAssertEqual(missing, 600)
    }

    /// 読めない本文（知らない印の種類など）も「無い」と同じく覚え、開くたびに取り直さない
    func testUnreadableBodyIsRemembered() async {
        let s = service()
        StubProtocol.respond(status: 200, body: #"{"slug":"kinkakuji","check":{"kind":"both"}}"#)
        let first = await s.fetchBody(slug: "kinkakuji")
        XCTAssertNil(first)
        let again = await s.fetchBody(slug: "kinkakuji")
        XCTAssertNil(again)
        XCTAssertEqual(StubProtocol.requestCount, 1, "読めない本文を開くたびに取り直している")
    }

    /// 読めない中身（`text/html` を名乗らないログイン画面など）は「無い」ほど長く覚えない。
    /// 本文の寿命が過ぎたら取り直し、正しい本文を出す
    func testUnreadableBodyIsRetriedAfterTheShortMemo() async {
        let s = OfficialSpotService(url: url, session: session, snapshot: SpotSnapshotStore(fileName: UUID().uuidString),
                                    bodyLifetime: 0, missingBodyLifetime: 600)
        StubProtocol.respond(status: 200, body: "<html>login</html>", contentType: "text/plain")
        let portal = await s.fetchBody(slug: "kinkakuji")
        XCTAssertNil(portal)
        StubProtocol.respond(status: 200, body: SpotBodyTests.aiBody)
        let body = await s.fetchBody(slug: "kinkakuji")
        XCTAssertEqual(body?.slug, "kinkakuji", "読めなかった回を10分引きずっている")
    }

    /// 綴りが `[a-z0-9-]` でない slug は叩かない。中身の slug が違えば捨てる
    func testRejectsOddSlugsAndMismatchedBodies() async {
        StubProtocol.respond(status: 200, body: SpotBodyTests.aiBody)
        let s = service()
        let odd = await s.fetchBody(slug: "../photos")
        XCTAssertNil(odd)
        let upper = await s.fetchBody(slug: "Kinkakuji")
        XCTAssertNil(upper)
        XCTAssertEqual(StubProtocol.requestCount, 0)
        let mismatched = await s.fetchBody(slug: "ginkakuji")
        XCTAssertNil(mismatched, "別の場所の本文を出さない")
    }
}
