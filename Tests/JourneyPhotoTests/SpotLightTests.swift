import XCTest
@testable import JourneyPhoto

/// 撮影スポットの「光の時刻」（`SunTimes` の方角と `SpotLight`）。
///
/// **基準は国立天文台の暦**（暦計算室「日の出入り」2026年・各地。2026-10-03 に取得）。
/// 暦の地点の座標で計算し、時刻は ±2分・方角は ±2° に収まることを確かめる
/// （式は NOAA の簡略式。実測の差は時刻 1〜2分・方角 0.3° 以内）
final class SpotLightTests: XCTestCase {

    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    private struct Almanac {
        let place: String
        let ymd: String
        let lat: Double
        let lng: Double
        let sunrise: String
        let riseAzimuth: Double
        let sunset: String
        let setAzimuth: Double
    }

    /// 国立天文台の暦の値（時刻は日本時間・方位は北から時計回り）
    private let almanac: [Almanac] = [
        Almanac(place: "東京・夏至", ymd: "2026-06-21", lat: 35.6581, lng: 139.7414,
                sunrise: "04:25", riseAzimuth: 60.0, sunset: "19:00", setAzimuth: 300.0),
        Almanac(place: "東京・冬至", ymd: "2026-12-22", lat: 35.6581, lng: 139.7414,
                sunrise: "06:47", riseAzimuth: 118.6, sunset: "16:32", setAzimuth: 241.4),
        Almanac(place: "東京・春分", ymd: "2026-03-20", lat: 35.6581, lng: 139.7414,
                sunrise: "05:45", riseAzimuth: 89.8, sunset: "17:52", setAzimuth: 270.5),
        Almanac(place: "根室・夏至", ymd: "2026-06-21", lat: 43.3333, lng: 145.5833,
                sunrise: "03:37", riseAzimuth: 55.9, sunset: "19:02", setAzimuth: 304.1),
        Almanac(place: "鹿児島・冬至", ymd: "2026-12-21", lat: 31.6, lng: 130.55,
                sunrise: "07:13", riseAzimuth: 117.2, sunset: "17:18", setAzimuth: 242.8),
    ]

    private func date(_ ymd: String, _ hm: String, in zone: TimeZone) throws -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        let (y, m, d) = try XCTUnwrap(TakenDay.ymd(ymd))
        let parts = hm.split(separator: ":").compactMap { Int($0) }
        return try XCTUnwrap(c.date(from: DateComponents(year: y, month: m, day: d, hour: parts[0], minute: parts[1])))
    }

    func testMatchesTheNationalAstronomicalObservatoryAlmanac() throws {
        for a in almanac {
            let s = try XCTUnwrap(SunTimes.compute(a.ymd, lat: a.lat, lng: a.lng), a.place)
            let rise = try XCTUnwrap(s.sunrise, a.place)
            let set = try XCTUnwrap(s.sunset, a.place)
            XCTAssertLessThanOrEqual(abs(rise.timeIntervalSince(try date(a.ymd, a.sunrise, in: tokyo))), 120,
                                     "\(a.place) 日の出 \(SunTimes.clock(rise, in: tokyo) ?? "-")")
            XCTAssertLessThanOrEqual(abs(set.timeIntervalSince(try date(a.ymd, a.sunset, in: tokyo))), 120,
                                     "\(a.place) 日の入り \(SunTimes.clock(set, in: tokyo) ?? "-")")
            XCTAssertEqual(try XCTUnwrap(s.sunriseAzimuth), a.riseAzimuth, accuracy: 2, "\(a.place) 日の出の方位")
            XCTAssertEqual(try XCTUnwrap(s.sunsetAzimuth), a.setAzimuth, accuracy: 2, "\(a.place) 日の入りの方位")
        }
    }

    /// 方角は ±2° より実際はずっと近い（0.5° 以内）。式を壊したら気づけるよう狭くも見ておく。
    /// 春分・秋分は赤緯が1日で 0.4° 動き、朝夕を南中の赤緯1つで出すぶん差が大きい（東京の春分の日の入りで 0.36°）
    func testAzimuthIsWellWithinTolerance() throws {
        for a in almanac {
            let s = try XCTUnwrap(SunTimes.compute(a.ymd, lat: a.lat, lng: a.lng))
            XCTAssertEqual(try XCTUnwrap(s.sunriseAzimuth), a.riseAzimuth, accuracy: 0.5, a.place)
            XCTAssertEqual(try XCTUnwrap(s.sunsetAzimuth), a.setAzimuth, accuracy: 0.5, a.place)
        }
    }

    func testCompassAndDirection() {
        XCTAssertEqual(SpotLight.compass(0), "北")
        XCTAssertEqual(SpotLight.compass(67), "東北東")
        XCTAssertEqual(SpotLight.compass(90), "東")
        XCTAssertEqual(SpotLight.compass(241.4), "西南西")
        XCTAssertEqual(SpotLight.compass(300), "西北西")
        XCTAssertEqual(SpotLight.compass(359), "北")
        XCTAssertEqual(SpotLight.direction(67.4), "東北東 67°")
        XCTAssertEqual(SpotLight.direction(359.7), "北 0°")
        XCTAssertNil(SpotLight.direction(nil))
    }

    /// 東京の夏至: 段の中は時刻の順（朝: ブルー → 日の出 → ゴールデン、夕: ゴールデン → 日の入り → ブルー）
    func testTokyoSolsticeBlocksAreInTimeOrder() throws {
        let blocks = SpotLight.blocks("2026-06-21", lat: 35.6581, lng: 139.7414, in: tokyo)
        XCTAssertEqual(blocks.map(\.title), ["朝", "夕"])
        let morning = blocks[0].rows
        XCTAssertEqual(morning.map(\.label), ["ブルーアワー", "日の出", "ゴールデンアワー"])
        XCTAssertEqual(morning[1].detail, "東北東 60°")
        XCTAssertTrue(morning[1].value.hasPrefix("04:2"), morning[1].value)
        let evening = blocks[1].rows
        XCTAssertEqual(evening.map(\.label), ["ゴールデンアワー", "日の入り", "ブルーアワー"])
        XCTAssertEqual(evening[1].detail, "西北西 300°")
        // 朝は帯の**終わり**の順（ブルーが明ける → 日の出 → ゴールデンが終わる）、夕は帯の**始まり**の順
        // （ゴールデンが始まる → 日の入り → ブルーが始まる）。朝のゴールデンは −4° から始まるので、日の出より前に
        // 始まる——始まりの順で並べるとブルー → ゴールデン → 日の出になるが、板どおり日の出を真ん中に置く
        // （"HH:MM" は文字の順＝時刻の順）
        let morningEnds = morning.map { String($0.value.suffix(5)) }
        XCTAssertEqual(morningEnds, morningEnds.sorted(), "朝")
        let eveningStarts = evening.map { String($0.value.prefix(5)) }
        XCTAssertEqual(eveningStarts, eveningStarts.sorted(), "夕")
        // 朝: ブルー → ゴールデンが −4° でつながる。夕: ゴールデン → ブルーが −4° でつながる
        XCTAssertEqual(morning[0].value.split(separator: "–").last.map(String.init), String(morning[2].value.prefix(5)))
        XCTAssertEqual(evening[0].value.split(separator: "–").last.map(String.init), String(evening[2].value.prefix(5)))
    }

    /// 白夜（トロムソの夏至）: 時刻を作らず「白夜（沈まない）」・方角は出さない
    func testMidnightSun() {
        let blocks = SpotLight.blocks("2024-06-21", lat: 69.65, lng: 18.96, in: TimeZone(identifier: "Europe/Oslo")!)
        let sunrise = blocks.first?.rows.first { $0.label == "日の出" }
        XCTAssertEqual(sunrise?.value, "白夜（沈まない）")
        XCTAssertNil(sunrise?.detail)
        XCTAssertEqual(blocks.last?.rows.first { $0.label == "日の入り" }?.value, "白夜（沈まない）")
        // −4° まで下がらないので、ゴールデンアワーは夜をまたぐ（時刻を作らず言葉で開く）
        XCTAssertEqual(blocks.last?.rows.first?.label, "ゴールデンアワー")
        XCTAssertTrue(blocks.last?.rows.first?.value.hasSuffix("–（翌朝まで）") ?? false)
        XCTAssertNil(SunTimes.compute("2024-06-21", lat: 69.65, lng: 18.96)?.sunriseAzimuth)
    }

    /// 極夜（トロムソの冬至）: 「極夜（昇らない）」。ゴールデンアワーも出さない
    func testPolarNight() {
        let blocks = SpotLight.blocks("2024-12-21", lat: 69.65, lng: 18.96, in: TimeZone(identifier: "Europe/Oslo")!)
        XCTAssertEqual(blocks.first?.rows.first { $0.label == "日の出" }?.value, "極夜（昇らない）")
        XCTAssertFalse(blocks.flatMap(\.rows).contains { $0.label == "ゴールデンアワー" })
        // 時刻の端を作らない（開いたままの「–」で終わる行が無い）
        XCTAssertFalse(blocks.flatMap(\.rows).contains { $0.value.hasSuffix("–") || $0.value.hasPrefix("–") })
    }

    /// 白夜の前後（日は沈むが −4° まで下がらない）: 時刻を作らず「翌朝まで」「前夜から」と言う
    func testOpenEndedSpanWords() {
        let zone = TimeZone(identifier: "UTC")!
        let start = Date(timeIntervalSince1970: 1_000_000_000)
        XCTAssertEqual(SpotLight.spanText(SunTimes.Span(start: start, end: nil), in: zone), "01:46–（翌朝まで）")
        XCTAssertEqual(SpotLight.spanText(SunTimes.Span(start: nil, end: start), in: zone), "（前夜から）–01:46")
        XCTAssertNil(SpotLight.spanText(SunTimes.Span(start: nil, end: nil), in: zone))
    }

    /// 昇るが 6° まで上がらない日（北緯63°の冬至）は、ゴールデンアワーが朝から夕まで1本（1行だけ）
    func testGoldenAllDay() throws {
        let blocks = SpotLight.blocks("2026-12-21", lat: 63.0, lng: 10.4, in: TimeZone(identifier: "Europe/Oslo")!)
        let golden = blocks.flatMap(\.rows).filter { $0.label == "ゴールデンアワー" }
        XCTAssertEqual(golden.count, 1)
        let value = try XCTUnwrap(golden.first?.value)
        XCTAssertTrue(value.hasSuffix("（一日中・太陽が 6° より上がらない）"), value)
        XCTAssertNotNil(value.range(of: #"^\d{2}:\d{2}–\d{2}:\d{2}"#, options: .regularExpression), value)
        XCTAssertNotNil(blocks.first?.rows.first { $0.label == "日の出" }?.detail, "日の出はあるので方角も出す")
    }

    func testDatesInTheSpotsZone() {
        // 2026-10-03 15:30 UTC は東京では 10/4 の 0:30
        let now = Date(timeIntervalSince1970: 1_791_041_400)
        XCTAssertEqual(SpotLight.ymd(offset: 0, from: now, in: tokyo), "2026-10-04")
        XCTAssertEqual(SpotLight.ymd(offset: 0, from: now, in: TimeZone(identifier: "Europe/Paris")!), "2026-10-03")
        XCTAssertEqual(SpotLight.ymd(offset: -1, from: now, in: tokyo), "2026-10-03")
        XCTAssertEqual(SpotLight.dateLabel("2026-10-03", offset: 0, todayYMD: "2026-10-03"), "10月3日（土） · 今日")
        XCTAssertEqual(SpotLight.dateLabel("2026-10-04", offset: 1, todayYMD: "2026-10-03"), "10月4日（日） · 明日")
        XCTAssertEqual(SpotLight.dateLabel("2027-01-05", offset: 94, todayYMD: "2026-10-03"), "2027年1月5日（火）")
    }

    /// 節の中身: 日本は Asia/Tokyo。**表に無い国は端末の時刻帯で出さず nil**（Web・ホームの札と同じ）。
    /// 座標が読めず段が作れないときも nil
    func testSheetOnlyWhenZoneAndBlocksExist() throws {
        let now = Date(timeIntervalSince1970: 1_791_041_400)  // 東京 2026-10-04 0:30
        let japan = try XCTUnwrap(SpotLight.sheet(country: "日本", lat: 35.68, lng: 139.77, offset: 0, now: now))
        XCTAssertEqual(japan.timeZone, tokyo)
        XCTAssertEqual(japan.todayYMD, "2026-10-04")
        XCTAssertEqual(japan.ymd, "2026-10-04")
        XCTAssertFalse(japan.blocks.isEmpty)
        XCTAssertEqual(SpotLight.sheet(country: nil, lat: 35.68, lng: 139.77, offset: 0, now: now)?.timeZone, tokyo,
                       "国の無い行は日本")
        XCTAssertNil(SpotLight.sheet(country: "アメリカ", lat: 40.7, lng: -74.0, offset: 0, now: now))
        XCTAssertNil(SpotLight.sheet(country: "日本", lat: 95, lng: 139.77, offset: 0, now: now))
        XCTAssertNil(SpotLight.sheet(country: "日本", lat: .nan, lng: 139.77, offset: 0, now: now))
        XCTAssertEqual(SpotLight.sheet(country: "日本", lat: 35.68, lng: 139.77, offset: 1, now: now)?.ymd, "2026-10-05")
        // 送れる幅の外は端で止める
        XCTAssertEqual(SpotLight.sheet(country: "日本", lat: 35.68, lng: 139.77, offset: 9999, now: now)?.ymd,
                       SpotLight.ymd(offset: SpotLight.maxOffset, from: now, in: tokyo))
    }

    func testNote() {
        XCTAssertTrue(SpotLight.note(tokyo).hasPrefix("時刻は日本時間。"))
        XCTAssertTrue(SpotLight.note(TimeZone(identifier: "Europe/Paris")!).hasPrefix("時刻は現地時間（Europe/Paris）。"))
        XCTAssertTrue(SpotLight.note(tokyo).contains("ゴールデンアワーは太陽の高さが 6° から −4°"))
    }

    /// 台帳の時間帯の文: 夜明け・朝は朝の段、夕方の斜光・日没後は夕の段、日中・夜は撮影ガイドに残す。
    /// 節を出さないときは全部を撮影ガイドに残す
    func testGuidesSplit() throws {
        let json = """
        [{"time":"night","text":"夜景"},{"time":"goldenHour","text":"夕日"},
         {"time":"dawn","text":"朝霧"},{"time":"day","text":"日中"},{"time":"dusk","text":"残照"}]
        """
        let list = try JSONDecoder().decode([SpotBody.TimeOfDay].self, from: Data(json.utf8))
        let split = SpotLight.guides(list)
        XCTAssertEqual(split.morning.map(\.time), ["dawn"])
        XCTAssertEqual(split.evening.map(\.time), ["goldenHour", "dusk"])
        XCTAssertEqual(SpotLight.guideTimes(list, lightShown: true).map(\.time), ["day", "night"])
        XCTAssertEqual(SpotLight.guideTimes(list, lightShown: false).map(\.time), ["dawn", "day", "goldenHour", "dusk", "night"])
    }
}
