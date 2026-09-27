import XCTest
@testable import JourneyPhoto

final class DailyThemeTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ iso: String) -> Date {
        NotificationGroups.parse(iso)!
    }

    private func photo(_ id: String, tags: [String], createdAt: String?) throws -> Photo {
        let tagsJSON = tags.map { "\"\($0)\"" }.joined(separator: ",")
        let created = createdAt.map { ",\"createdAt\":\"\($0)\"" } ?? ""
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\",\"tags\":[\(tagsJSON)]\(created)}".utf8))
    }

    /// **同じ日なら何度開いても同じテーマ**（通信もしない）
    func testSameDayGivesTheSameTheme() {
        let morning = date("2026-09-21T01:00:00.000Z")
        let night = date("2026-09-21T23:00:00.000Z")
        XCTAssertEqual(DailyTheme.today(morning, calendar: calendar),
                       DailyTheme.today(night, calendar: calendar))
    }

    func testThemeChangesTheNextDay() {
        let today = DailyTheme.today(date("2026-09-21T09:00:00.000Z"), calendar: calendar)
        let tomorrow = DailyTheme.today(date("2026-09-22T09:00:00.000Z"), calendar: calendar)
        XCTAssertNotEqual(today, tomorrow)
    }

    /// 一巡すると戻る（添字の計算が負や範囲外にならない）
    func testCyclesThroughEveryTheme() {
        var seen: Set<String> = []
        for offset in 0..<DailyTheme.themes.count {
            let day = date("2026-09-2\(1)T09:00:00.000Z").addingTimeInterval(Double(offset) * 86_400)
            seen.insert(DailyTheme.today(day, calendar: calendar).tag)
        }
        XCTAssertEqual(seen.count, DailyTheme.themes.count)
    }

    /// テーマのタグは**決まった選択肢の中から**（棚を散らかさない）
    func testEveryThemeUsesAChosenTag() {
        for theme in DailyTheme.themes {
            XCTAssertTrue(TagChoices.all.contains(theme.tag), "\(theme.tag) が選択肢に無い")
        }
    }

    func testJoinedWhenTodaysPhotoHasTheTag() throws {
        let theme = DailyTheme.Theme(tag: "海", title: "水", prompt: "")
        let now = date("2026-09-21T09:00:00.000Z")
        let mine = [try photo("p1", tags: ["海"], createdAt: "2026-09-21T02:00:00.000Z")]
        XCTAssertTrue(DailyTheme.hasJoined(theme, myPhotos: mine, now: now, calendar: calendar))
    }

    func testNotJoinedWhenThePhotoIsFromAnotherDay() throws {
        let theme = DailyTheme.Theme(tag: "海", title: "水", prompt: "")
        let now = date("2026-09-21T09:00:00.000Z")
        let mine = [try photo("p1", tags: ["海"], createdAt: "2026-09-20T02:00:00.000Z")]
        XCTAssertFalse(DailyTheme.hasJoined(theme, myPhotos: mine, now: now, calendar: calendar))
    }

    func testNotJoinedWhenTheTagIsDifferentOrTimeUnknown() throws {
        let theme = DailyTheme.Theme(tag: "海", title: "水", prompt: "")
        let now = date("2026-09-21T09:00:00.000Z")
        XCTAssertFalse(DailyTheme.hasJoined(theme, myPhotos: [
            try photo("p1", tags: ["山"], createdAt: "2026-09-21T02:00:00.000Z"),
            try photo("p2", tags: ["海"], createdAt: nil),
        ], now: now, calendar: calendar))
    }

    /// 日英の表記ゆれ（`sea` と `海`）でも同じタグとして見る
    func testMatchesTagAcrossSpellings() throws {
        let theme = DailyTheme.Theme(tag: "海", title: "水", prompt: "")
        let now = date("2026-09-21T09:00:00.000Z")
        let mine = [try photo("p1", tags: ["sea"], createdAt: "2026-09-21T02:00:00.000Z")]
        XCTAssertEqual(TagChoices.key("sea"), TagChoices.key("海"))
        XCTAssertTrue(DailyTheme.hasJoined(theme, myPhotos: mine, now: now, calendar: calendar))
    }

    // MARK: - 端末の暦（バグ探し 2026-09-27 #23）

    private func calendar(_ id: Calendar.Identifier, zone: String = "Asia/Tokyo") -> Calendar {
        var calendar = Calendar(identifier: id)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    /// **和暦・タイ仏暦の端末でも、西暦の端末と同じテーマ。** 紀元から数えていたので、
    /// 和暦では令和の初日から数えて別のテーマになっていた
    func testThemeDoesNotDependOnTheDeviceCalendar() {
        let now = date("2026-09-27T03:00:00.000Z")
        let expected = DailyTheme.today(now, calendar: calendar(.gregorian))
        for id in [Calendar.Identifier.japanese, .buddhist, .islamicUmmAlQura, .hebrew] {
            XCTAssertEqual(DailyTheme.today(now, calendar: calendar(id)), expected, "\(id) の端末でテーマが変わる")
        }
    }

    /// 西暦に替えても**タイムゾーンはその暦のまま**（土地の1日で数える）。
    ///
    /// ⚠️ テーマ（`ordinality(of: .day, in: .era)`）ではなく日付のステッカーで確かめる。
    /// Linux の Foundation の `ordinality` はタイムゾーンを見ない（東京で 28 日になっても
    /// 通し番号は 27 日のまま・2026-09-27 に手元で確認）。Apple の Foundation は確かめていない
    func testGregorianKeepsTheTimeZone() {
        // 東京では 9/28 1時、協定世界時ではまだ 9/27
        let now = date("2026-09-27T16:00:00.000Z")
        XCTAssertEqual(calendar(.japanese).gregorianKeepingZone.timeZone, TimeZone(identifier: "Asia/Tokyo"))
        XCTAssertEqual(TextOverlay.Kind.date.initialText(now: now, calendar: calendar(.japanese)),
                       L("9月28日", "9/28"), "タイムゾーンを落としている")
    }

    /// 季節と日付のステッカーも西暦の月日（イスラム暦の月は季節と合わない）
    func testSeasonAndDateStickerUseGregorianMonths() {
        let now = date("2026-09-27T03:00:00.000Z")
        let islamic = calendar(.islamicUmmAlQura)
        XCTAssertEqual(DiscoverySections.seasonalTags(now: now, calendar: islamic),
                       DiscoverySections.seasonalTags(now: now, calendar: calendar(.gregorian)))
        XCTAssertEqual(TextOverlay.Kind.date.initialText(now: now, calendar: islamic),
                       TextOverlay.Kind.date.initialText(now: now, calendar: calendar(.gregorian)))
    }

    /// **テーマは土地の0時で切り替わる**（協定世界時の0時ではない）。
    /// 東京の 9/28 1時は、協定世界時の 9/28 と同じテーマ
    func testThemeTurnsOverAtLocalMidnight() {
        let tokyoJustAfterMidnight = date("2026-09-27T16:00:00.000Z")
        let utcNextDay = date("2026-09-28T03:00:00.000Z")
        let utc = calendar(.gregorian, zone: "UTC")
        XCTAssertEqual(DailyTheme.today(tokyoJustAfterMidnight, calendar: calendar(.gregorian)),
                       DailyTheme.today(utcNextDay, calendar: utc), "土地の0時で切り替わっていない")
        XCTAssertNotEqual(DailyTheme.today(tokyoJustAfterMidnight, calendar: calendar(.gregorian)),
                          DailyTheme.today(tokyoJustAfterMidnight, calendar: utc))
    }
}
