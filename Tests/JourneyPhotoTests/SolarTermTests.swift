import XCTest
@testable import JourneyPhoto

/// 二十四節気の計算（`SolarTerm`・共有の絵「暦（差し色）」・2026-11-18）。
///
/// 公表値: 国立天文台 暦計算室「暦要項」の「二十四節気および雑節」（日本時間・分まで）
/// - 2025 年: https://eco.mtk.nao.ac.jp/koyomi/yoko/2025/rekiyou252.html（令和6年2月1日 国立天文台発表）
/// - 2026 年: https://eco.mtk.nao.ac.jp/koyomi/yoko/2026/rekiyou262.html（令和7年2月3日 国立天文台発表）
/// - 2027 年: https://eco.mtk.nao.ac.jp/koyomi/yoko/2027/rekiyou272.html（令和8年2月2日 国立天文台発表）
/// 2026-11-18 にこの3頁から写した（計算で作った値ではない）
final class SolarTermTests: XCTestCase {

    static let published: [(String, String)] = [
        ("小寒", "2025-01-05 11:33"), ("大寒", "2025-01-20 05:00"), ("立春", "2025-02-03 23:10"), ("雨水", "2025-02-18 19:07"),
        ("啓蟄", "2025-03-05 17:07"), ("春分", "2025-03-20 18:01"), ("清明", "2025-04-04 21:49"), ("穀雨", "2025-04-20 04:56"),
        ("立夏", "2025-05-05 14:57"), ("小満", "2025-05-21 03:55"), ("芒種", "2025-06-05 18:57"), ("夏至", "2025-06-21 11:42"),
        ("小暑", "2025-07-07 05:05"), ("大暑", "2025-07-22 22:29"), ("立秋", "2025-08-07 14:52"), ("処暑", "2025-08-23 05:34"),
        ("白露", "2025-09-07 17:52"), ("秋分", "2025-09-23 03:19"), ("寒露", "2025-10-08 09:41"), ("霜降", "2025-10-23 12:51"),
        ("立冬", "2025-11-07 13:04"), ("小雪", "2025-11-22 10:36"), ("大雪", "2025-12-07 06:05"), ("冬至", "2025-12-22 00:03"),
        ("小寒", "2026-01-05 17:23"), ("大寒", "2026-01-20 10:45"), ("立春", "2026-02-04 05:02"), ("雨水", "2026-02-19 00:52"),
        ("啓蟄", "2026-03-05 22:59"), ("春分", "2026-03-20 23:46"), ("清明", "2026-04-05 03:40"), ("穀雨", "2026-04-20 10:39"),
        ("立夏", "2026-05-05 20:49"), ("小満", "2026-05-21 09:37"), ("芒種", "2026-06-06 00:48"), ("夏至", "2026-06-21 17:25"),
        ("小暑", "2026-07-07 10:57"), ("大暑", "2026-07-23 04:13"), ("立秋", "2026-08-07 20:43"), ("処暑", "2026-08-23 11:19"),
        ("白露", "2026-09-07 23:41"), ("秋分", "2026-09-23 09:05"), ("寒露", "2026-10-08 15:29"), ("霜降", "2026-10-23 18:38"),
        ("立冬", "2026-11-07 18:52"), ("小雪", "2026-11-22 16:23"), ("大雪", "2026-12-07 11:53"), ("冬至", "2026-12-22 05:50"),
        ("小寒", "2027-01-05 23:10"), ("大寒", "2027-01-20 16:30"), ("立春", "2027-02-04 10:46"), ("雨水", "2027-02-19 06:33"),
        ("啓蟄", "2027-03-06 04:40"), ("春分", "2027-03-21 05:25"), ("清明", "2027-04-05 09:17"), ("穀雨", "2027-04-20 16:18"),
        ("立夏", "2027-05-06 02:25"), ("小満", "2027-05-21 15:18"), ("芒種", "2027-06-06 06:26"), ("夏至", "2027-06-21 23:11"),
        ("小暑", "2027-07-07 16:37"), ("大暑", "2027-07-23 10:05"), ("立秋", "2027-08-08 02:27"), ("処暑", "2027-08-23 17:14"),
        ("白露", "2027-09-08 05:28"), ("秋分", "2027-09-23 15:02"), ("寒露", "2027-10-08 21:17"), ("霜降", "2027-10-24 00:33"),
        ("立冬", "2027-11-08 00:39"), ("小雪", "2027-11-22 22:16"), ("大雪", "2027-12-07 17:38"), ("冬至", "2027-12-22 11:42"),
    ]

    /// 公表の時刻（日本時間）
    static func moment(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = SolarTerm.japan
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    /// 撮った日（UTC 0 時で持つ暦の日・`TripBook.day(of:)` と同じ形）
    static func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        TripBook.utcCalendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    static func day(of text: String) -> (Int, Int, Int) {
        let parts = text.prefix(10).split(separator: "-").map { Int($0)! }
        return (parts[0], parts[1], parts[2])
    }

    func testTableHas24TermsFromRisshun() {
        let all = SolarTerm.all
        XCTAssertEqual(all.count, 24)
        XCTAssertEqual(all.first?.name, "立春")
        XCTAssertEqual(all.first?.longitude, 315)
        XCTAssertEqual(all.first { $0.name == "春分" }?.longitude, 0)
        XCTAssertEqual(all.first { $0.name == "寒露" }?.number, 17)
        XCTAssertEqual(all.first { $0.name == "処暑" }?.number, 14)
        XCTAssertEqual(all.first { $0.name == "立冬" }?.number, 19)
        XCTAssertEqual(Set(all.map(\.name)).count, 24)
        for term in all {
            XCTAssertFalse(term.meaning.contains("・"), term.name)
            XCTAssertFalse(term.latin.isEmpty)
            XCTAssertEqual(term.latin, term.latin.uppercased())
        }
    }

    /// 計算した節気の時刻が、公表の時刻と ±1 分で合う（公表は分まで。72個すべて）
    func testMomentsMatchNAOJWithinAMinute() {
        XCTAssertEqual(Self.published.count, 72)
        var worst = 0.0
        for (name, text) in Self.published {
            let term = try! XCTUnwrap(SolarTerm.all.first { $0.name == name })
            let published = Self.moment(text)
            let computed = SolarTerm.moment(of: term, near: published)
            let minutes = computed.timeIntervalSince(published) / 60
            worst = max(worst, abs(minutes))
            // 公表は分の切り捨てか丸め。計算は 0〜1 分の後ろに来るはず（余裕を見て −1〜+1.5）
            XCTAssertGreaterThan(minutes, -1, "\(text) \(name)")
            XCTAssertLessThan(minutes, 1.5, "\(text) \(name)")
        }
        print("measured [solarterm] worst=\(String(format: "%.2f", worst))min")
    }

    /// 節気の日（公表の日）はその節気、前の日は前の節気（72個すべて。年の変わり目・日付の変わる直前直後を含む）
    func testDayOfEachTermMatchesNAOJ() {
        for (name, text) in Self.published {
            let (y, m, d) = Self.day(of: text)
            let day = Self.day(y, m, d)
            XCTAssertEqual(SolarTerm.term(onDay: day).name, name, "\(text)")
            let before = day.addingTimeInterval(-86_400)
            let previous = SolarTerm.all.first { $0.name == name }!.number
            let expected = SolarTerm.all[(previous - 2 + 24) % 24].name
            XCTAssertEqual(SolarTerm.term(onDay: before).name, expected, "\(text) の前の日")
        }
    }

    /// 模型の見本の日（2026.10.10 寒露 17、2025.08.30 処暑 14、2026.11.07 立冬 19）
    func testMockupExamples() {
        XCTAssertEqual(SolarTerm.term(onDay: Self.day(2026, 10, 10)).number, 17)
        XCTAssertEqual(SolarTerm.term(onDay: Self.day(2025, 8, 30)).number, 14)
        XCTAssertEqual(SolarTerm.term(onDay: Self.day(2026, 11, 7)).number, 19)
        XCTAssertEqual(SolarTerm.term(onDay: Self.day(2026, 11, 7)).name, "立冬")
    }

    /// 黄経から節気（境目ちょうどはその節気・360 をまたぐ）
    func testTermAtLongitude() {
        XCTAssertEqual(SolarTerm.term(atLongitude: 315).name, "立春")
        XCTAssertEqual(SolarTerm.term(atLongitude: 314.999).name, "大寒")
        XCTAssertEqual(SolarTerm.term(atLongitude: 0).name, "春分")
        XCTAssertEqual(SolarTerm.term(atLongitude: 359.99).name, "啓蟄")
        XCTAssertEqual(SolarTerm.term(atLongitude: 285).name, "小寒")
    }
}
