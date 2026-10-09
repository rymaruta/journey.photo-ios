import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 光と天気の知らせ（Pro・板 LightAlert・2026-10-09）。
///
/// 固定したいのは:
///  1. 応答（`api-user/src/lightForecast.ts`）の読み取り。壊れた1か所で全体を落とさない・出典は必ず出る
///  2. 場所ごとの札: いちばん良い時間帯（高い → 早い → 朝夕夜）・過ぎた時間帯は選ばない・並びは「いつ」の順・
///     真鍮の縁は「高」のいちばん早い1枚だけ
///  3. 文面（板の書き方）・空のとき・読めなかったとき（403 / 503 / 圏外）
///  4. プッシュの `type: "light"` は一覧へ。知らない種類の扱いは変えない
///  5. 受け取る設定（`lightAlert`）の読み書き
@MainActor
final class LightForecastTests: XCTestCase {

    /// 2026-10-09 12:00 JST
    private let noon = Date(timeIntervalSince1970: 1_791_514_800)

    private func decode(_ json: String) throws -> LightForecast {
        try JSONDecoder.api.decode(LightForecast.self, from: Data(json.utf8))
    }

    private func clock(_ hhmm: String, on ymd: String) -> LightForecast.Clock {
        .init(at: "\(ymd)T\(hhmm):00+09:00", clock: hhmm)
    }

    private func day(_ ymd: String,
                     morning: LightForecast.Outlook? = nil,
                     evening: LightForecast.Outlook? = nil,
                     night: LightForecast.Outlook? = nil) -> LightForecast.Day {
        .init(date: ymd, sunrise: clock("05:42", on: ymd), sunset: clock("17:21", on: ymd),
              morningBlue: .init(start: clock("05:10", on: ymd), end: clock("05:20", on: ymd)),
              eveningBlue: .init(start: clock("17:40", on: ymd), end: clock("17:55", on: ymd)),
              morning: morning, evening: evening, night: night)
    }

    private func place(_ n: Int, forecast: Bool = true, _ days: [LightForecast.Day]) -> LightForecast.Place {
        .init(key: "SPOT-p\(n)", slug: "p\(n)", name: "場所\(n)", timeZone: "Asia/Tokyo", forecast: forecast, days: days)
    }

    private let high = LightForecast.Outlook(weather: .clear, chance: .high)
    private let mid = LightForecast.Outlook(weather: .partlyCloudy, chance: .mid)
    private let low = LightForecast.Outlook(weather: .rain, chance: .low)

    // MARK: - 1. 読み取り

    /// サーバーの形そのもの（`getLightForecast` の注記の例）
    func testReadsTheServerShape() async throws {
        let f = try decode(#"""
        {"places":[{"key":"SPOT-fuji","slug":"fuji","name":"富士山","nameEn":"Mt. Fuji","timeZone":"Asia/Tokyo","forecast":true,
          "days":[{"date":"2026-10-10","sunrise":{"at":"2026-10-09T20:42:00.000Z","clock":"05:42"},
                   "sunset":{"at":"2026-10-10T08:21:00.000Z","clock":"17:21"},
                   "morningBlue":{"start":{"at":"2026-10-09T20:10:00.000Z","clock":"05:10"},"end":null},
                   "eveningBlue":{"start":null,"end":null},
                   "morning":{"weather":"clear","chance":"high"},"evening":{"weather":"partlyCloudy","chance":"mid"},"night":null}]}],
         "note":"天気は外部の予報から。光の時刻はアプリで計算。見込みは目安で、外れることがあります。",
         "attribution":{"serviceName":"Apple Weather","legalUrl":"https://weatherkit.apple.com/legal-attribution.html"}}
        """#)
        XCTAssertEqual(f.places.count, 1)
        let p = try XCTUnwrap(f.places.first)
        XCTAssertEqual(p.key, "SPOT-fuji")
        XCTAssertEqual(p.name, "富士山")
        XCTAssertTrue(p.forecast)
        XCTAssertEqual(p.days.first?.sunrise?.clock, "05:42")
        XCTAssertEqual(p.days.first?.morning, high)
        XCTAssertEqual(p.days.first?.evening, mid)
        XCTAssertNil(p.days.first?.night)
        XCTAssertEqual(p.days.first?.morningBlue?.start?.clock, "05:10")
        XCTAssertEqual(f.attribution.serviceName, "Apple Weather")
        XCTAssertEqual(f.attribution.legalURL.absoluteString, "https://weatherkit.apple.com/legal-attribution.html")
        XCTAssertEqual(LightForecastText.note(f), "天気は外部の予報から。光の時刻はアプリで計算。見込みは目安で、外れることがあります。")
    }

    /// 知らない天気・見込みの言葉はその時間帯だけ落とす。名前の無い場所・日付の無い日はそれだけ落とす
    func testBrokenPartsDropOnlyThemselves() async throws {
        let f = try decode(#"""
        {"places":[
          {"key":"SPOT-a","slug":"a","name":"A","timeZone":"Asia/Tokyo","forecast":true,
           "days":[{"date":"2026-10-10","morning":{"weather":"snowstorm","chance":"high"},"evening":{"weather":"clear","chance":"maybe"},
                    "night":{"weather":"clear","chance":"low"}},
                   {"sunrise":null}]},
          {"key":"SPOT-b","slug":"b","timeZone":"Asia/Tokyo","forecast":true,"days":[]}
        ]}
        """#)
        XCTAssertEqual(f.places.map(\.key), ["SPOT-a"])
        XCTAssertEqual(f.places[0].days.count, 1)
        XCTAssertNil(f.places[0].days[0].morning)
        XCTAssertNil(f.places[0].days[0].evening)
        XCTAssertEqual(f.places[0].days[0].night?.chance, .low)
    }

    /// `places` の無い応答は投げる（「行きたい場所が無い」と混ぜない）
    func testMissingPlacesThrows() async {
        XCTAssertThrowsError(try decode(#"{"error":"x"}"#))
    }

    /// 出典は**必ず出す**（Apple の求め）。無い・https でない・壊れていれば手元の値
    func testAttributionAlwaysPresent() async throws {
        XCTAssertEqual(try decode(#"{"places":[]}"#).attribution, .appleWeather)
        XCTAssertEqual(try decode(#"{"places":[],"attribution":{"serviceName":"X","legalUrl":"http://evil.test"}}"#).attribution,
                       .appleWeather)
        XCTAssertEqual(try decode(#"{"places":[],"attribution":"Apple"}"#).attribution, .appleWeather)
        // 注記が無ければ板の文言
        XCTAssertEqual(LightForecastText.note(try decode(#"{"places":[]}"#)),
                       "天気は外部の予報から。光の時刻はアプリで計算。見込みは目安で、外れることがあります。")
    }

    // MARK: - 2. 札

    /// その場所でいちばん良いもの: 高い → 早い → 朝夕夜
    func testBestPicksHighestThenEarliest() async {
        let p = place(1, [day("2026-10-10", morning: mid, evening: high),
                          day("2026-10-11", morning: high)])
        let best = LightForecastText.best(for: p, now: noon)
        XCTAssertEqual(best?.day.date, "2026-10-10")
        XCTAssertEqual(best?.moment, .evening)
        XCTAssertEqual(best?.offset, 1)
    }

    /// 過ぎた時間帯は選ばない（今日の朝焼けを昼に勧めない）
    func testSkipsMomentsAlreadyPassed() async {
        let p = place(1, [day("2026-10-09", morning: high, evening: mid),
                          day("2026-10-10", morning: low)])
        let best = LightForecastText.best(for: p, now: noon)
        XCTAssertEqual(best?.day.date, "2026-10-09")
        XCTAssertEqual(best?.moment, .evening, "12:00 に今日の日の出（5:42）を選んでいる")
    }

    /// 予報の無い場所は、次の日の出（光の時刻だけ）
    func testNoForecastFallsBackToNextSunTime() async {
        let p = place(1, forecast: false, [day("2026-10-09"), day("2026-10-10")])
        let card = LightForecastText.card(for: p, now: noon)
        XCTAssertEqual(card.when, "今日 · 日の入り 17:21")
        XCTAssertEqual(card.weather, "予報なし")
        XCTAssertEqual(card.kind, "光の時刻だけ")
        XCTAssertEqual(card.tone, .none)
        XCTAssertNil(card.chance)
    }

    /// 板の札の文面: 「明日 · 日の出 5:42」「晴れ」「朝焼け 見込み高」、低いときは「見込み低」だけ
    func testCardTextFollowsTheBoard() async {
        let a = LightForecastText.card(for: place(1, [day("2026-10-10", morning: high)]), now: noon)
        XCTAssertEqual(a.name, "場所1")
        XCTAssertEqual(a.when, "明日 · 日の出 5:42")
        XCTAssertEqual(a.weather, "晴れ")
        XCTAssertEqual(a.kind, "朝焼け 見込み高")
        XCTAssertEqual(a.tone, .morning)

        // 2026-10-12 は月曜
        let b = LightForecastText.card(for: place(2, [day("2026-10-12", morning: low)]), now: noon)
        XCTAssertEqual(b.when, "月曜 · 日の出 5:42")
        XCTAssertEqual(b.weather, "雨")
        XCTAssertEqual(b.kind, "見込み低")
        XCTAssertEqual(b.tone, .low)

        let c = LightForecastText.card(for: place(3, [day("2026-10-11", night: mid)]), now: noon)
        XCTAssertEqual(c.when, "日曜 · ブルーアワー 17:40")
        XCTAssertEqual(c.kind, "夜景 見込み中")
        XCTAssertEqual(c.weather, "くもり時々晴れ")
        XCTAssertEqual(c.tone, .night)
    }

    /// 並びは「いつ」の早い順（同じならサーバーの順）、予報の無い場所は後ろ。
    /// 真鍮の縁は「高」のうちいちばん早い1枚だけ
    func testOrderAndBrassEdge() async {
        let f = LightForecast(places: [
            place(1, [day("2026-10-12", morning: high)]),
            place(2, forecast: false, [day("2026-10-10")]),
            place(3, [day("2026-10-10", evening: mid)]),
            place(4, [day("2026-10-11", morning: high)]),
            place(5, [day("2026-10-10", evening: low)]),
        ])
        let cards = LightForecastText.cards(f, now: noon)
        XCTAssertEqual(cards.map(\.id), ["SPOT-p3", "SPOT-p5", "SPOT-p4", "SPOT-p1", "SPOT-p2"])
        XCTAssertEqual(cards.filter(\.isBest).map(\.id), ["SPOT-p4"])
        XCTAssertTrue(cards[2].accessibilityLabel.hasPrefix("今週いちばんの見込み、"))
    }

    /// 「高」が1つも無い週は縁を付けない（「中」を「いちばん良い」と飾らない）
    func testNoBrassEdgeWithoutHigh() async {
        let f = LightForecast(places: [place(1, [day("2026-10-10", morning: mid)]),
                                       place(2, [day("2026-10-11", morning: low)])])
        XCTAssertFalse(LightForecastText.cards(f, now: noon).contains(where: \.isBest))
    }

    /// 札を開いたときの7日: 過ぎた日は出さない・日ごとに朝夕夜
    func testWeekLines() async {
        let p = place(1, [day("2026-10-08", morning: high),
                          day("2026-10-09", morning: high, evening: mid),
                          day("2026-10-11", night: low)])
        let week = LightForecastText.week(p, now: noon)
        XCTAssertEqual(week.map(\.id), ["2026-10-09", "2026-10-11"])
        XCTAssertEqual(week[0].title, "今日")
        XCTAssertEqual(week[0].items.first?.event, "日の出 5:42")
        XCTAssertEqual(week[0].items.first?.outlook, "朝焼け 見込み高 · 晴れ")
        XCTAssertEqual(week[0].items[2].outlook, "夜景 予報なし")
        XCTAssertEqual(week[1].title, "10月11日（日）")
    }

    func testShortClockAndDayWords() async {
        XCTAssertEqual(LightForecastText.shortClock("05:42"), "5:42")
        XCTAssertEqual(LightForecastText.shortClock("17:21"), "17:21")
        XCTAssertEqual(LightForecastText.shortClock("x"), "x")
        XCTAssertEqual(LightForecastText.dayWord("2026-10-09", today: "2026-10-09"), "今日")
        XCTAssertEqual(LightForecastText.dayWord("2026-10-10", today: "2026-10-09"), "明日")
        XCTAssertEqual(LightForecastText.dayWord("2026-10-15", today: "2026-10-09"), "木曜")
        XCTAssertEqual(LightForecastText.dayWord("bad", today: "2026-10-09"), "bad")
    }

    /// 「今日」はその土地の暦（端末の時計ではない）。2026-10-09 23:30 JST は、ハワイではまだ 10-09 の朝
    func testTodayIsInThePlacesTimeZone() async {
        let late = Date(timeIntervalSince1970: 1_791_556_200) // 2026-10-09 23:30 JST = 04:30 HST
        let hawaii = LightForecast.Place(key: "SPOT-h", slug: "h", name: "H", timeZone: "Pacific/Honolulu",
                                         forecast: true, days: [])
        XCTAssertEqual(LightForecastText.today(for: hawaii, now: late), "2026-10-09")
        let tokyo = place(1, [])
        XCTAssertEqual(LightForecastText.today(for: tokyo, now: late), "2026-10-09")
        XCTAssertEqual(LightForecastText.today(for: tokyo, now: late.addingTimeInterval(3600)), "2026-10-10")
    }

    /// 見本（画面写真用）は板の4枚の姿になる
    func testSampleLooksLikeTheBoard() async {
        let cards = LightForecastText.cards(LightForecastText.sample(now: noon), now: noon)
        XCTAssertEqual(cards.count, 4)
        XCTAssertEqual(cards.map(\.isBest), [true, false, false, false])
        XCTAssertEqual(cards.map(\.tone), [.morning, .evening, .night, .low])
    }

    // MARK: - 3. 空・読めない

    func testEmptyKinds() async {
        XCTAssertEqual(LightForecastText.empty(wishlist: []), .noWishes)
        XCTAssertEqual(LightForecastText.empty(wishlist: ["kyoto"]), .noSpots)
        XCTAssertEqual(LightForecastText.emptyTitle(.noWishes), "行きたい場所がまだありません")
        XCTAssertEqual(LightForecastText.emptyTitle(.noSpots), "光を出せる撮影スポットがありません")
    }

    func testFailureKinds() async {
        XCTAssertEqual(LightForecastText.failure(for: APIError.server(status: 403, message: "Pro の機能です")), .notPro)
        XCTAssertEqual(LightForecastText.failure(for: APIError.server(status: 503, message: "x")), .unavailable)
        XCTAssertEqual(LightForecastText.failure(for: APIError.unreachable), .unreachable)
        XCTAssertEqual(LightForecastText.failure(for: APIError.notAuthenticated), .signedOut)
        XCTAssertEqual(LightForecastText.failure(for: APIError.server(status: 401, message: "x")), .signedOut)
        guard case .other = LightForecastText.failure(for: APIError.server(status: 500, message: "取得に失敗しました")) else {
            return XCTFail("500 を別の失敗に振っている")
        }
        XCTAssertEqual(LightForecastText.failureTitle(.notPro), "Pro の機能です")
        XCTAssertEqual(LightForecastText.failureTitle(.unavailable), "いまは天気の予報を読めません")
        XCTAssertEqual(LightForecastText.failureTitle(.unreachable), "圏外のため読み込めませんでした")
    }

    // MARK: - 4. プッシュ

    /// サーバーの知らせの中身（`alertOne` の `data`）→ 一覧「行きたい場所の光」
    func testLightPushOpensTheForecast() async throws {
        let target = try XCTUnwrap(AppNotification.fromPush([
            "aps": ["alert": ["title": "明日の朝、富士山 が晴れそうです", "body": "…"]],
            "type": "light", "spot": "fuji", "kind": "sunrise", "date": "2026-10-10",
        ]))
        XCTAssertEqual(target.kind, .light)
        XCTAssertEqual(NotificationsViewModel().route(for: target), .light)
    }

    /// 知らない種類は今までどおり行き先なし。光の知らせは一覧の行にならない
    func testUnknownKindsStayUnchanged() async throws {
        let unknown = try XCTUnwrap(AppNotification.fromPush(["type": "mystery"]))
        XCTAssertNil(unknown.kind)
        XCTAssertNil(NotificationsViewModel().route(for: unknown))
        let light = try JSONDecoder.api.decode(AppNotification.self, from: Data(#"{"type":"light","t":"2026-10-09T11:00:00Z"}"#.utf8))
        XCTAssertNil(NotificationText.line(for: NotificationText.Entry(lead: light, others: 0, unread: false)))
    }

    // MARK: - 5. 受け取る設定

    func testProfileReadsLightAlertWithDefaultOn() async throws {
        let off = try JSONDecoder.api.decode(UserProfile.self, from: Data(#"{"userId":"u","lightAlert":false}"#.utf8))
        XCTAssertFalse(off.wantsLightAlert)
        let on = try JSONDecoder.api.decode(UserProfile.self, from: Data(#"{"userId":"u","lightAlert":true}"#.utf8))
        XCTAssertTrue(on.wantsLightAlert)
        // 古いサーバー（無い）は受け取る（サーバーの既定）
        let none = try JSONDecoder.api.decode(UserProfile.self, from: Data(#"{"userId":"u"}"#.utf8))
        XCTAssertTrue(none.wantsLightAlert)
    }

    /// 部分更新は `lightAlert` だけを真偽で送る（文字の "false" はサーバーが 400 で断る）
    func testPatchSendsOnlyTheFlag() async throws {
        let data = try JSONEncoder().encode(ProfilePatch(lightAlert: false))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json.keys.sorted(), ["lightAlert"])
        XCTAssertEqual(json["lightAlert"] as? Bool, false)
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"lightAlert":false}"#)
    }

    func testSaveFailedText() async {
        XCTAssertTrue(LightAlertSettingsText.saveFailed(APIError.unreachable).hasPrefix("圏外"))
        XCTAssertEqual(LightAlertSettingsText.saveFailed(APIError.server(status: 500, message: "x")),
                       "切り替えられませんでした。もう一度お試しください。")
    }
}

/// 通信の形（`GET /user/light-forecast`・ログイン必須）と、403 / 503 / 圏外の振り分け
final class LightForecastServiceTests: XCTestCase {

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

    private func service() -> LightForecastService {
        LightForecastService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                            tokenProvider: StubTokenProvider(token: "ID"), session: session))
    }

    func testCallsTheEndpointWithAuth() async throws {
        StubProtocol.respond(status: 200, body: #"{"places":[],"note":"n"}"#)
        let f = try await service().fetch()
        XCTAssertEqual(f.places, [])
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/user/light-forecast")
        XCTAssertEqual(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer ID")
    }

    /// 🔴 **端末の HTTP 控えを使わない**（サーバーは `max-age=600`。控えのままだと「行きたい」を足しても
    /// 引っぱって読み直しても10分間 前の一覧のまま）
    func testBypassesLocalHTTPCache() async throws {
        StubProtocol.respond(status: 200, body: #"{"places":[]}"#)
        _ = try await service().fetch()
        XCTAssertEqual(StubProtocol.lastRequest?.cachePolicy, .reloadIgnoringLocalCacheData)
        // ほかの口は今までどおり（既定の決まり）
        _ = try await service().api.authorizedVoid(.get, "/user/profile")
        XCTAssertEqual(StubProtocol.lastRequest?.cachePolicy, .useProtocolCachePolicy)
    }

    func testNotProAndUnavailable() async {
        StubProtocol.respond(status: 403, body: #"{"error":"Pro の機能です"}"#)
        do { _ = try await service().fetch(); XCTFail("通った") } catch {
            XCTAssertEqual(LightForecastText.failure(for: error), .notPro)
        }
        StubProtocol.respond(status: 503, body: #"{"error":"いまは天気の予報を読めません"}"#)
        do { _ = try await service().fetch(); XCTFail("通った") } catch {
            XCTAssertEqual(LightForecastText.failure(for: error), .unavailable)
        }
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        do { _ = try await service().fetch(); XCTFail("通った") } catch {
            XCTAssertEqual(LightForecastText.failure(for: error), .unreachable)
        }
    }
}
