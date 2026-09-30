import XCTest
@testable import JourneyPhoto

/// 旅行プランの当日モード（`TripLight`）。前日から最終日まで、今日か明日の撮影スポットの光の時刻
final class TripLightTests: XCTestCase {

    private func spot(_ id: String, name: String = "銀山温泉", lat: Double = 38.58, lng: Double = 140.53,
                      country: String? = nil, stage: String = "published",
                      seasons: String = #"[{"season":"autumn","text":"温泉街の奥の白銀の滝のまわりが紅葉し、大正ロマンの木造旅館とガス灯の夜景に秋の色が重なる。"}]"#) throws -> OfficialSpot {
        let region = country.map { #"{"country":"\#($0)"}"# } ?? #"{"prefecture":"山形県"}"#
        let json = #"{"spotId":"\#(id)","slug":"\#(id)","name":"\#(name)","stage":"\#(stage)","region":\#(region),"coords":{"lat":\#(lat),"lng":\#(lng)},"seasonalGuide":\#(seasons)}"#
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
        XCTAssertEqual(TripLight.line(e).components(separatedBy: "\n").first,
                       "明日 · 銀山温泉 · マジックアワー 16:34–17:26 · 日の入り 17:09")
        XCTAssertTrue(TripLight.line(e).contains("\n秋: 温泉街の奥"))
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
        XCTAssertFalse(TripLight.line(e).contains("\n"), "案内が無ければ1行")
    }
}
