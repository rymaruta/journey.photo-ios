import XCTest
@testable import JourneyPhoto

/// 光の時刻（`SunTimes`）。**Web の `lib/utils/__tests__/sunTimes.test.ts` と同じ値**
/// ——同じ場所・同じ日に、Web のスポットの画面とアプリの札が違う時刻を言わない
final class SunTimesTests: XCTestCase {

    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private let paris = TimeZone(identifier: "Europe/Paris")!

    func testTokyoMatchesTheAlmanac() throws {
        let s = try XCTUnwrap(SunTimes.compute("2024-09-27", lat: 35.6812, lng: 139.7671))
        XCTAssertEqual(SunTimes.clock(s.sunrise, in: tokyo), "05:33")
        XCTAssertEqual(SunTimes.clock(s.sunset, in: tokyo), "17:32")
    }

    /// 夕方: ゴールデンアワー（+6°→−4°）→ ブルーアワー（−4°→−6°）の順につながる（銀山温泉）
    func testEveningGoldenThenBlue() throws {
        let s = try XCTUnwrap(SunTimes.compute("2026-10-10", lat: 38.58, lng: 140.53))
        XCTAssertEqual(SunTimes.clock(s.eveningGolden.start, in: tokyo), "16:34")
        XCTAssertEqual(SunTimes.clock(s.sunset, in: tokyo), "17:09")
        XCTAssertEqual(SunTimes.clock(s.eveningGolden.end, in: tokyo), "17:26")
        XCTAssertEqual(s.eveningBlue.start, s.eveningGolden.end)
        XCTAssertEqual(SunTimes.clock(s.eveningBlue.end, in: tokyo), "17:36")
        XCTAssertEqual(SunTimes.clock(s.morningBlue.start, in: tokyo), "05:15")
        XCTAssertEqual(SunTimes.clock(s.sunrise, in: tokyo), "05:42")
        XCTAssertEqual(SunTimes.span(s.eveningGolden, in: tokyo), "16:34–17:26")
    }

    /// 西の経度でも、その暦日の時刻になる（パリの夏至・夏時間）
    func testParisSummerSolstice() throws {
        let s = try XCTUnwrap(SunTimes.compute("2024-06-21", lat: 48.8566, lng: 2.3522))
        XCTAssertEqual(SunTimes.clock(s.sunrise, in: paris), "05:48")
        XCTAssertEqual(SunTimes.clock(s.sunset, in: paris), "21:58")
    }

    /// 白夜で太陽がその高度を通らない日は nil（作り話の時刻を出さない）
    func testMidnightSunHasNoSunset() throws {
        let s = try XCTUnwrap(SunTimes.compute("2024-06-21", lat: 69.65, lng: 18.96))
        XCTAssertNil(s.sunrise)
        XCTAssertNil(s.sunset)
        XCTAssertGreaterThan(try XCTUnwrap(SunTimes.altitudeRange("2024-06-21", lat: 69.65, lng: 18.96)).min, -0.833,
                             "いちばん低くても沈まない＝白夜")
    }

    func testRejectsBadInput() {
        XCTAssertNil(SunTimes.compute("2024/09/27", lat: 35.68, lng: 139.77))
        XCTAssertNil(SunTimes.compute("2024-09-27", lat: 95, lng: 0))
    }

    /// Web の `COUNTRY_TIME_ZONES` と同じ表。国が無い行は日本・知らない国は nil
    func testCountryTimeZones() {
        XCTAssertEqual(SunTimes.timeZone(forCountry: nil)?.identifier, "Asia/Tokyo")
        XCTAssertEqual(SunTimes.timeZone(forCountry: "フランス")?.identifier, "Europe/Paris")
        XCTAssertNil(SunTimes.timeZone(forCountry: "アメリカ"))
        XCTAssertEqual(SunTimes.countryTimeZones.count, 87)
        // 2026-10-07: 時刻帯が1つの国を足した。複数ある国は表に入れない（行の timeZone で決める）
        XCTAssertEqual(SunTimes.timeZone(forCountry: "韓国")?.identifier, "Asia/Seoul")
        XCTAssertEqual(SunTimes.timeZone(forCountry: "ペルー")?.identifier, "America/Lima")
        for c in ["アメリカ", "カナダ", "オーストラリア", "ブラジル", "メキシコ", "ロシア", "インドネシア"] {
            XCTAssertNil(SunTimes.countryTimeZones[c], c)
        }
        for (c, z) in SunTimes.countryTimeZones {
            XCTAssertEqual(SunTimes.timeZone(named: z)?.identifier, z, "\(c) の時刻帯が読めない")
        }
    }

    // MARK: - 台帳の行の timeZone（2026-10-07）。Web の `spotTimeZone.test.ts` と同じ値

    /// 行の timeZone があれば国より先。無ければ国の表。複数の時刻帯の国は決まらない
    func testRowTimeZoneWinsOverCountry() {
        XCTAssertEqual(SunTimes.timeZone(named: "America/New_York", country: "アメリカ")?.identifier, "America/New_York")
        XCTAssertEqual(SunTimes.timeZone(named: "Atlantic/Canary", country: "スペイン")?.identifier, "Atlantic/Canary",
                       "国の表に在る国でも行の時刻帯が勝つ")
        XCTAssertEqual(SunTimes.timeZone(named: " Australia/Sydney ", country: "オーストラリア")?.identifier, "Australia/Sydney")
        XCTAssertEqual(SunTimes.timeZone(named: nil, country: "スペイン")?.identifier, "Europe/Madrid")
        XCTAssertEqual(SunTimes.timeZone(named: nil, country: nil)?.identifier, "Asia/Tokyo")
        XCTAssertNil(SunTimes.timeZone(named: nil, country: "アメリカ"))
    }

    /// 読めない名前（略号・ずれ・綴り違い）は受けず、国の表に落とす
    func testUnreadableRowTimeZoneFallsBackToCountry() {
        for bad in ["EST", "+09:00", "Asia/Tokio", "", "  ", "UTC"] {
            XCTAssertNil(SunTimes.timeZone(named: bad), bad)
            XCTAssertEqual(SunTimes.timeZone(named: bad, country: "フランス")?.identifier, "Europe/Paris", bad)
            XCTAssertNil(SunTimes.timeZone(named: bad, country: "アメリカ"), bad)
        }
    }

    private func riseSet(_ ymd: String, _ lat: Double, _ lng: Double, _ zone: String) throws -> [String?] {
        let s = try XCTUnwrap(SunTimes.compute(ymd, lat: lat, lng: lng))
        let z = try XCTUnwrap(TimeZone(identifier: zone))
        return [SunTimes.clock(s.sunrise, in: z), SunTimes.clock(s.sunset, in: z)]
    }

    /// ニューヨーク: 冬（EST）・夏（EDT）、夏時間の始まり（2026-03-08）の前後で1時間ずれる
    func testNewYorkFollowsDaylightSaving() throws {
        XCTAssertEqual(try riseSet("2026-01-15", 40.7128, -74.006, "America/New_York"), ["07:19", "16:53"])
        XCTAssertEqual(try riseSet("2026-07-15", 40.7128, -74.006, "America/New_York"), ["05:38", "20:27"])
        XCTAssertEqual(try riseSet("2026-03-07", 40.7128, -74.006, "America/New_York"), ["06:22", "17:54"])
        XCTAssertEqual(try riseSet("2026-03-09", 40.7128, -74.006, "America/New_York"), ["07:18", "18:56"])
    }

    /// シドニー: 南半球の夏（AEDT）・冬（AEST）、夏時間の終わり（2026-04-05）の前後で1時間ずれる
    func testSydneyFollowsDaylightSaving() throws {
        XCTAssertEqual(try riseSet("2026-01-15", -33.8688, 151.2093, "Australia/Sydney"), ["06:00", "20:10"])
        XCTAssertEqual(try riseSet("2026-07-15", -33.8688, 151.2093, "Australia/Sydney"), ["06:59", "17:04"])
        XCTAssertEqual(try riseSet("2026-04-04", -33.8688, 151.2093, "Australia/Sydney"), ["07:10", "18:48"])
        XCTAssertEqual(try riseSet("2026-04-06", -33.8688, 151.2093, "Australia/Sydney"), ["06:11", "17:45"])
    }

    private typealias Span = SunTimes.Span
}
