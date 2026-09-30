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

    /// 夕方: マジックアワー（+6°→−4°）→ ブルーアワー（−4°→−6°）の順につながる（銀山温泉）
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
        XCTAssertEqual(SunTimes.countryTimeZones.count, 15)
    }

    private typealias Span = SunTimes.Span
}
