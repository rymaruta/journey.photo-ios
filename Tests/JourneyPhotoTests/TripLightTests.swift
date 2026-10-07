import XCTest
@testable import JourneyPhoto

/// 旅行プランの当日モード（`TripLight`）。前日から最終日まで、今日か明日の撮影スポットの光の時刻
final class TripLightTests: XCTestCase {

    private func spot(_ id: String, name: String = "銀山温泉", lat: Double = 38.58, lng: Double = 140.53,
                      country: String? = nil, timeZone: String? = nil, stage: String = "published",
                      seasons: String = #"[{"season":"autumn","text":"温泉街の奥の白銀の滝のまわりが紅葉し、大正ロマンの木造旅館とガス灯の夜景に秋の色が重なる。"}]"#) throws -> OfficialSpot {
        let region = country.map { #"{"country":"\#($0)"}"# } ?? #"{"prefecture":"山形県"}"#
        let zone = timeZone.map { #","timeZone":"\#($0)""# } ?? ""
        let json = #"{"spotId":"\#(id)","slug":"\#(id)","name":"\#(name)","stage":"\#(stage)"\#(zone),"region":\#(region),"coords":{"lat":\#(lat),"lng":\#(lng)},"seasonalGuide":\#(seasons)}"#
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(json.utf8))
    }

    private func plan(start: String, end: String, days: [[String]]) -> TripPlan {
        TripPlan(planId: "p", title: "山形", startDate: start, endDate: end,
                 days: days.map { TripDay(items: $0.map { .spot(spotId: $0, note: nil) }) })
    }

    private func day(_ ymd: String) -> Date { TripPlanText.date(fromYMD: ymd)! }

    func testDayBeforeStartShowsTomorrowsFirstSpot() throws {
        let g = try spot("sp_g")
        let p = plan(start: "2026-10-10", end: "2026-10-11", days: [["sp_g"], []])
        let e = try XCTUnwrap(TripLight.entry(plan: p, today: day("2026-10-09"), spots: [g]))
        XCTAssertTrue(e.isTomorrow)
        XCTAssertEqual(e.dayNumber, 1)
        // Web の sunTimes.test.ts と同じ値（銀山温泉 2026-10-10）
        XCTAssertEqual(e.eveningGolden, "16:34–17:26")
        XCTAssertEqual(e.sunset, "17:09")
        XCTAssertEqual(e.season, "autumn")
        // 札はほかの札と同じ2行まで（季節の案内は札に出さない＝並びの背を揃えても写真を押し下げない）
        XCTAssertEqual(TripLight.line(e), "明日 · 銀山温泉 · ゴールデンアワー 16:34–17:26 · 日の入り 17:09")
        XCTAssertTrue(e.seasonGuide!.hasSuffix("…"), "長い案内は切る")
    }

    func testTodaysSpotWinsOverTomorrows() throws {
        let a = try spot("sp_a", name: "A")
        let b = try spot("sp_b", name: "B")
        let p = plan(start: "2026-10-10", end: "2026-10-11", days: [["sp_a"], ["sp_b"]])
        XCTAssertEqual(TripLight.entry(plan: p, today: day("2026-10-10"), spots: [a, b])?.spot.name, "A")
        XCTAssertEqual(TripLight.entry(plan: p, today: day("2026-10-10"), spots: [a, b])?.isTomorrow, false)
        // 今日の日にスポットが無ければ明日
        let q = plan(start: "2026-10-10", end: "2026-10-11", days: [[], ["sp_b"]])
        XCTAssertEqual(TripLight.entry(plan: q, today: day("2026-10-10"), spots: [a, b])?.spot.name, "B")
    }

    func testOutsideTheWindowIsNil() throws {
        let g = try spot("sp_g")
        let p = plan(start: "2026-10-10", end: "2026-10-11", days: [["sp_g"], ["sp_g"]])
        XCTAssertNil(TripLight.entry(plan: p, today: day("2026-10-08"), spots: [g]), "2日前")
        XCTAssertNil(TripLight.entry(plan: p, today: day("2026-10-12"), spots: [g]), "帰ったあと")
    }

    func testSkipsDraftsAndUnknownTimeZones() throws {
        let draft = try spot("sp_d", stage: "review")
        let us = try spot("sp_us", country: "アメリカ")
        let ok = try spot("sp_ok", name: "OK")
        let p = plan(start: "2026-10-10", end: "2026-10-10", days: [["sp_d", "sp_us", "sp_ok"]])
        XCTAssertEqual(TripLight.entry(plan: p, today: day("2026-10-10"), spots: [draft, us, ok])?.spot.name, "OK")
        let none = plan(start: "2026-10-10", end: "2026-10-10", days: [["sp_d", "sp_us"]])
        XCTAssertNil(TripLight.entry(plan: none, today: day("2026-10-10"), spots: [draft, us]))
    }

    /// 海外は現地の時計（パリの夏至・夏時間）
    func testAbroadUsesLocalClock() throws {
        let paris = try spot("sp_p", name: "パリ", lat: 48.8566, lng: 2.3522, country: "フランス", seasons: "[]")
        let p = plan(start: "2024-06-21", end: "2024-06-21", days: [["sp_p"]])
        let e = try XCTUnwrap(TripLight.entry(plan: p, today: day("2024-06-21"), spots: [paris]))
        XCTAssertEqual(e.sunset, "21:58")
        XCTAssertNil(e.seasonGuide)
    }

    /// 2026-10-07: 索引の行の timeZone があれば国より先（アメリカのように時刻帯が複数ある国でも出る）
    func testRowTimeZoneLetsMultiZoneCountriesShow() throws {
        let ny = try spot("sp_ny", name: "NY", lat: 40.7128, lng: -74.006, country: "アメリカ",
                          timeZone: "America/New_York", seasons: "[]")
        XCTAssertEqual(ny.timeZone, "America/New_York")
        let p = plan(start: "2026-07-15", end: "2026-07-15", days: [["sp_ny"]])
        let e = try XCTUnwrap(TripLight.entry(plan: p, today: day("2026-07-15"), spots: [ny]))
        XCTAssertEqual(e.sunset, "20:27", "夏時間（EDT）の時計")
    }

    /// 最終日より後の日（日程が日付より長い）は拾わない
    func testDaysBeyondTheEndAreNotPicked() throws {
        let g = try spot("sp_g")
        let p = plan(start: "2026-10-10", end: "2026-10-11", days: [[], [], ["sp_g"]])
        XCTAssertNil(TripLight.entry(plan: p, today: day("2026-10-11"), spots: [g]), "3日目は帰着日を越える")
        XCTAssertNil(TripLight.entry(plan: p, today: day("2026-10-12"), spots: [g]))
    }

    /// 極夜（北緯69度の12月）は Web と同じく「極夜」（何も出さないと理由が分からない）
    func testPolarNightSaysSo() throws {
        let north = try spot("sp_n", name: "北", lat: 69.05, lng: 20.8, country: "フィンランド", seasons: "[]")
        let p = plan(start: "2026-12-15", end: "2026-12-15", days: [["sp_n"]])
        let e = try XCTUnwrap(TripLight.entry(plan: p, today: day("2026-12-15"), spots: [north]))
        XCTAssertEqual(e.sunset, "極夜")
        XCTAssertEqual(e.eveningGolden, "極夜")
    }

    /// 🔴 北極圏（公開中のサンタクロース村・北緯66.5度）。Web の撮影の光の表と同じ言い分け
    /// ——「日の入り 00:10」を朝のことに読ませない・一日中ゴールデンアワーを「無い」と読ませない
    func testArcticWordsMatchTheWeb() throws {
        let santa = try spot("sp_s", name: "サンタクロース村", lat: 66.5436, lng: 25.8473, country: "フィンランド", seasons: "[]")
        func entry(_ ymd: String) throws -> TripLight.Entry {
            let p = plan(start: ymd, end: ymd, days: [["sp_s"]])
            return try XCTUnwrap(TripLight.entry(plan: p, today: day(ymd), spots: [santa]))
        }
        let jan = try entry("2026-01-15")
        XCTAssertEqual(jan.eveningGolden, "終日")
        XCTAssertEqual(jan.sunset, "14:32")
        let jun = try entry("2026-06-15")
        XCTAssertEqual(jun.sunset, "白夜")
        XCTAssertEqual(jun.eveningGolden, "22:18–（沈まない）")
        XCTAssertEqual(try entry("2026-07-15").sunset, "翌00:10")
        // 7月は沈むので「沈まない」とは言わない（明け方までつながる）
        XCTAssertEqual(try entry("2026-07-15").eveningGolden, "21:59–（明け方まで）")
        XCTAssertEqual(try entry("2026-05-15").eveningGolden, "21:16–翌00:18")
    }
}
