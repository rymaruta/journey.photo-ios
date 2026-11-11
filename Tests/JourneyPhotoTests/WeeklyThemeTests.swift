import XCTest
@testable import JourneyPhoto

/// 今週のお題（`WeeklyTheme`・札 #537 案2・2026-11-11。前は日替わりの「今日のテーマ」）。
///
/// 🔴 **日付と答えは Web の `lib/utils/__tests__/weeklyTheme.test.ts` と同じ。** 片方だけ一覧・順番・週の区切りを
/// 変えると、アプリと Web で今週のお題が割れる
final class WeeklyThemeTests: XCTestCase {

    private func calendar(_ id: Calendar.Identifier = .gregorian, zone: String = "Asia/Tokyo") -> Calendar {
        var calendar = Calendar(identifier: id)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ iso: String) -> Date {
        NotificationGroups.parse(iso)!
    }

    private func photo(_ id: String, tags: [String], createdAt: String?, user: String = "u1",
                       group: String? = nil) throws -> Photo {
        let tagsJSON = tags.map { "\"\($0)\"" }.joined(separator: ",")
        var extra = createdAt.map { ",\"createdAt\":\"\($0)\"" } ?? ""
        extra += ",\"userId\":\"\(user)\""
        if let group { extra += ",\"groupId\":\"\(group)\"" }
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\",\"tags\":[\(tagsJSON)]\(extra)}".utf8))
    }

    // MARK: - お題の決まり方

    /// **Web と同じ日付・同じ答え**（東京の端末）。週は月曜から。季節はその週の月曜の月で決まる
    func testKnownWeeksMatchTheWeb() {
        let tokyo = calendar()
        // 2026-11-11（水）→ 11/9 の週・秋 → 紅葉
        XCTAssertEqual(WeeklyTheme.current(date("2026-11-11T03:00:00.000Z"), calendar: tokyo).tag, "紅葉")
        // 2026-11-16（月）→ 次の週 → 神社
        XCTAssertEqual(WeeklyTheme.current(date("2026-11-16T03:00:00.000Z"), calendar: tokyo).tag, "神社")
        // 2026-12-03（木）は 11/30（月）の週＝月曜が 11 月なので秋のまま → 湖
        XCTAssertEqual(WeeklyTheme.current(date("2026-12-03T03:00:00.000Z"), calendar: tokyo).tag, "湖")
        // 2026-12-07（月）から冬 → 冬のあかり（夜）
        let winter = WeeklyTheme.current(date("2026-12-07T03:00:00.000Z"), calendar: tokyo)
        XCTAssertEqual(winter.tag, "夜")
        XCTAssertEqual(winter.title, L("冬のあかり", "Winter lights"))
        // 2027-04-05（月）→ 春 → 朝のはじまり
        XCTAssertEqual(WeeklyTheme.current(date("2027-04-05T03:00:00.000Z"), calendar: tokyo).tag, "朝")
        // 週の通し番号（Web の `weekIndex` と同じ値）
        XCTAssertEqual(WeeklyTheme.weekIndex(date("2026-11-11T03:00:00.000Z"), calendar: tokyo), 2966)
    }

    /// **同じ週なら何度開いても同じお題**（月曜の朝と日曜の夜）。月曜の0時（土地）で替わる
    func testSameWeekSameThemeAndTurnsOverOnMonday() {
        let tokyo = calendar()
        let monday = WeeklyTheme.current(date("2026-11-08T15:30:00.000Z"), calendar: tokyo)   // 東京 11/9（月）0:30
        let sunday = WeeklyTheme.current(date("2026-11-15T14:30:00.000Z"), calendar: tokyo)   // 東京 11/15（日）23:30
        let sundayBefore = WeeklyTheme.current(date("2026-11-08T14:30:00.000Z"), calendar: tokyo) // 東京 11/8（日）23:30
        XCTAssertEqual(monday, sunday)
        XCTAssertNotEqual(monday, sundayBefore, "月曜の0時（土地）で替わっていない")
        // 協定世界時ではまだ日曜なので、前の週のお題（土地の暦で数えている）
        XCTAssertEqual(WeeklyTheme.current(date("2026-11-08T15:30:00.000Z"), calendar: calendar(zone: "UTC")),
                       sundayBefore)
    }

    /// **3年分、続く週で同じタグにならない**（季節の変わり目も）
    func testConsecutiveWeeksNeverRepeat() {
        let start = WeeklyTheme.weekIndex(date("2026-01-05T03:00:00.000Z"), calendar: calendar())
        for week in start..<(start + 52 * 3) {
            XCTAssertNotEqual(WeeklyTheme.theme(ofWeek: week).tag, WeeklyTheme.theme(ofWeek: week + 1).tag,
                              "週 \(week) と次の週が同じお題")
        }
    }

    /// 季節のどれにもお題があり、タグは決まった選択肢の中。**隣り合う季節で同じタグを使わない**
    func testSeasonListsAreValid() {
        for season in WeeklyTheme.seasons {
            let themes = WeeklyTheme.themesBySeason[season] ?? []
            XCTAssertGreaterThanOrEqual(themes.count, 2, "\(season) のお題が少ない")
            XCTAssertEqual(Set(themes.map(\.tag)).count, themes.count, "\(season) に同じタグが2つ")
            for theme in themes { XCTAssertTrue(TagChoices.all.contains(theme.tag), "\(theme.tag) が選択肢に無い") }
        }
        let order = WeeklyTheme.seasons
        for (index, season) in order.enumerated() {
            let next = order[(index + 1) % order.count]
            let a = Set((WeeklyTheme.themesBySeason[season] ?? []).map(\.tag))
            let b = Set((WeeklyTheme.themesBySeason[next] ?? []).map(\.tag))
            XCTAssertTrue(a.isDisjoint(with: b), "\(season) と \(next) で同じタグ: \(a.intersection(b))")
        }
    }

    /// 画面の文に「撮りどき」を使わない（CLAUDE.md・2026-10-22 owner）
    func testWordingAvoidsTheSearchTerm() {
        for theme in WeeklyTheme.themesBySeason.values.flatMap({ $0 }) {
            XCTAssertFalse(theme.title.contains("撮りどき") || theme.prompt.contains("撮りどき"))
        }
    }

    /// **和暦・タイ仏暦の端末でも、西暦の端末と同じお題**
    func testThemeDoesNotDependOnTheDeviceCalendar() {
        let now = date("2026-09-27T03:00:00.000Z")
        let expected = WeeklyTheme.current(now, calendar: calendar(.gregorian))
        for id in [Calendar.Identifier.japanese, .buddhist, .islamicUmmAlQura, .hebrew] {
            XCTAssertEqual(WeeklyTheme.current(now, calendar: calendar(id)), expected, "\(id) の端末でお題が変わる")
        }
    }

    /// 西暦に替えても**タイムゾーンはその暦のまま**（土地の1日で数える）。
    /// 日付のステッカーで確かめる（Linux の Foundation の `ordinality` はタイムゾーンを見ない・2026-09-27 に手元で確認）
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

    // MARK: - 参加

    /// 参加済みは**今週**そのタグで上げたものがあるか（先週・別のタグ・投稿日の無いものは数えない）
    func testHasJoinedThisWeekOnly() throws {
        let tokyo = calendar()
        let now = date("2026-11-11T03:00:00.000Z")
        let theme = WeeklyTheme.current(now, calendar: tokyo)   // 紅葉
        // 東京 11/9（月）0:30 に上げた
        XCTAssertTrue(WeeklyTheme.hasJoined(theme, myPhotos: [
            try photo("a", tags: ["紅葉"], createdAt: "2026-11-08T15:30:00.000Z"),
        ], now: now, calendar: tokyo))
        // 表記ゆれ（英語のタグ）も同じ主題
        XCTAssertTrue(WeeklyTheme.hasJoined(theme, myPhotos: [
            try photo("b", tags: ["#autumn-leaves"], createdAt: "2026-11-10T00:00:00.000Z"),
        ], now: now, calendar: tokyo))
        // 東京 11/8（日）23:30＝先週
        XCTAssertFalse(WeeklyTheme.hasJoined(theme, myPhotos: [
            try photo("c", tags: ["紅葉"], createdAt: "2026-11-08T14:30:00.000Z"),
        ], now: now, calendar: tokyo))
        XCTAssertFalse(WeeklyTheme.hasJoined(theme, myPhotos: [
            try photo("d", tags: ["海"], createdAt: "2026-11-10T00:00:00.000Z"),
            try photo("e", tags: ["紅葉"], createdAt: nil),
        ], now: now, calendar: tokyo))
    }

    /// **みんなの参加**: 今週そのタグで載せた投稿を新しい順に。同じ投稿の写真は1つ（いちばん新しい1枚）
    func testParticipantsAreThisWeeksPostsNewestFirst() throws {
        let tokyo = calendar()
        let now = date("2026-11-11T03:00:00.000Z")
        let theme = WeeklyTheme.current(now, calendar: tokyo)
        let photos = [
            try photo("old", tags: ["紅葉"], createdAt: "2026-11-08T14:30:00.000Z", user: "u1"),   // 先週
            try photo("mon", tags: ["紅葉"], createdAt: "2026-11-08T15:30:00.000Z", user: "u2"),
            try photo("sea", tags: ["海"], createdAt: "2026-11-10T00:00:00.000Z", user: "u3"),      // 別のお題
            try photo("g1", tags: ["紅葉"], createdAt: "2026-11-10T01:00:00.000Z", user: "u4", group: "g"),
            try photo("g2", tags: ["紅葉"], createdAt: "2026-11-10T01:00:01.000Z", user: "u4", group: "g"),
            try photo("wed", tags: ["autumn-leaves"], createdAt: "2026-11-11T01:00:00.000Z", user: "u1"),
        ]
        XCTAssertEqual(WeeklyTheme.participants(theme, photos: photos, now: now, calendar: tokyo).map(\.id),
                       ["wed", "g2", "mon"])
    }

    /// 参加の行の文と読み上げ
    func testParticipantsWording() {
        XCTAssertEqual(WeeklyThemeText.participantsLine(3), L("今週 3件の投稿", "3 posts this week"))
        XCTAssertTrue(WeeklyThemeText.participantsSpoken(1).contains(WeeklyThemeText.participantsLine(1)))
    }
}
