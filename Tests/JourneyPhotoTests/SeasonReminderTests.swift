import XCTest
@testable import JourneyPhoto
import UserNotifications

/// 見頃のお知らせ（`SeasonReminder`・`SeasonReminderScheduler`）。次の季節の始まりに1件だけ・端末の中だけ
final class SeasonReminderTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func spot(_ id: String, name: String, seasons: [String], stage: String = "published") throws -> OfficialSpot {
        let guide = seasons.map { #"{"season":"\#($0)","text":"\#($0)の案内"}"# }.joined(separator: ",")
        let json = #"{"spotId":"\#(id)","slug":"\#(id)","name":"\#(name)","stage":"\#(stage)","seasonalGuide":[\#(guide)]}"#
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(json.utf8))
    }

    func testNextSeasonStart() {
        XCTAssertTrue(SeasonReminder.nextSeasonStart(after: date(2026, 9, 30), calendar: calendar) == (2026, 12))
        XCTAssertTrue(SeasonReminder.nextSeasonStart(after: date(2026, 12, 1), calendar: calendar) == (2027, 3))
        XCTAssertTrue(SeasonReminder.nextSeasonStart(after: date(2026, 2, 28), calendar: calendar) == (2026, 3))
        XCTAssertTrue(SeasonReminder.nextSeasonStart(after: date(2026, 3, 1), calendar: calendar) == (2026, 6))
    }

    /// 季節の始まりの日の 9時前に開いたら、その日の朝の知らせのまま（次の季節へ入れ替えて消さない）
    func testSeasonStartDayBeforeNineKeepsToday() {
        let at = { (h: Int) in self.calendar.date(from: DateComponents(year: 2026, month: 12, day: 1, hour: h))! }
        XCTAssertTrue(SeasonReminder.nextSeasonStart(after: at(8), calendar: calendar) == (2026, 12))
        XCTAssertTrue(SeasonReminder.nextSeasonStart(after: at(9), calendar: calendar) == (2027, 3))
        XCTAssertTrue(SeasonReminder.nextSeasonStart(after: at(10), calendar: calendar) == (2027, 3))
    }

    func testPlansOnlyWishedPublishedSpotsWithNextSeasonsGuide() throws {
        let a = try spot("sp_a", name: "銀山温泉", seasons: ["winter", "summer"])
        let b = try spot("sp_b", name: "蔵王", seasons: ["winter"])
        let noWinter = try spot("sp_c", name: "夏だけ", seasons: ["summer"])
        let draft = try spot("sp_d", name: "下書き", seasons: ["winter"], stage: "review")
        let notWished = try spot("sp_e", name: "入れていない", seasons: ["winter"])
        let wish: Set<String> = Set([a, b, noWinter, draft].map { SavedSpotKey.official($0.slug) })
        let plan = try XCTUnwrap(SeasonReminder.plan(now: date(2026, 9, 30), spots: [notWished, draft, noWinter, b, a],
                                                     wishlist: wish, calendar: calendar))
        XCTAssertEqual(plan.season, "winter")
        XCTAssertEqual(plan.fireAt.year, 2026)
        XCTAssertEqual(plan.fireAt.month, 12)
        XCTAssertEqual(plan.fireAt.day, 1)
        XCTAssertEqual(plan.fireAt.hour, 9)
        // 暦を付ける（和暦・仏暦の端末で予約が読み違えられない）
        XCTAssertEqual(plan.fireAt.calendar?.identifier, .gregorian)
        XCTAssertNil(plan.fireAt.timeZone, "時刻帯は付けない（旅先ではその土地の 9時）")
        // 予約自身の暦（端末の時刻帯に追従）で読むと、12/1 の 9時
        let fireCalendar = try XCTUnwrap(plan.fireAt.calendar)
        XCTAssertEqual(fireCalendar.timeZone, TimeZone.autoupdatingCurrent)
        let fire = try XCTUnwrap(plan.fireAt.date)
        XCTAssertEqual(fireCalendar.dateComponents([.year, .month, .day, .hour], from: fire),
                       DateComponents(year: 2026, month: 12, day: 1, hour: 9))
        XCTAssertEqual(plan.title, "冬の撮影スポット")
        XCTAssertEqual(plan.body, "行きたい場所の「銀山温泉」ほか1か所に冬の撮影ガイドがあります。")
        XCTAssertFalse(plan.body.contains("見頃"), "見頃とは言わない")
    }

    func testNothingToSayMeansNoPlan() throws {
        let summer = try spot("sp_s", name: "夏だけ", seasons: ["summer"])
        XCTAssertNil(SeasonReminder.plan(now: date(2026, 9, 30), spots: [summer],
                                         wishlist: [SavedSpotKey.official("sp_s")], calendar: calendar))
        XCTAssertNil(SeasonReminder.plan(now: date(2026, 9, 30), spots: [summer], wishlist: [], calendar: calendar))
    }

    @MainActor
    func testSchedulerReplacesOneRequestAndClearsWhenNotAllowed() async throws {
        var added: [UNNotificationRequest] = []
        var removed: [[String]] = []
        let scheduler = SeasonReminderScheduler(add: { added.append($0) }, removePending: { removed.append($0) })
        let a = try spot("sp_a", name: "銀山温泉", seasons: ["winter"])
        let plan = SeasonReminder.plan(now: date(2026, 9, 30), spots: [a], wishlist: [SavedSpotKey.official("sp_a")], calendar: calendar)

        await scheduler.reschedule(plan, allowed: true)
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added.first?.identifier, SeasonReminder.identifier)
        XCTAssertEqual(removed, [[SeasonReminder.identifier]], "入れる前に前の予約を消す")
        // 同じ中身なら入れ直さない
        await scheduler.reschedule(plan, allowed: true)
        XCTAssertEqual(added.count, 1)
        // 受け取る設定を切った・許可が無い → 予約を消す
        await scheduler.reschedule(plan, allowed: false)
        XCTAssertEqual(removed.count, 2)
        XCTAssertNil(scheduler.scheduled)
        XCTAssertEqual(added.count, 1)
    }

    /// 🔴 起動し直したあと（覚えている中身が無い）でも、入れない回は予約を消す
    /// （ログアウト・通知オフの前に入れた予約が、次の人の端末で前の人の行きたい場所の名前で鳴らない）
    @MainActor
    func testNotAllowedAlwaysRemovesEvenAfterRelaunch() async throws {
        var removed: [[String]] = []
        let fresh = SeasonReminderScheduler(add: { _ in }, removePending: { removed.append($0) })
        await fresh.reschedule(nil, allowed: false)
        XCTAssertEqual(removed, [[SeasonReminder.identifier]])
        let a = try spot("sp_a", name: "銀山温泉", seasons: ["winter"])
        let plan = SeasonReminder.plan(now: date(2026, 9, 30), spots: [a], wishlist: [SavedSpotKey.official("sp_a")], calendar: calendar)
        await fresh.reschedule(plan, allowed: false)
        XCTAssertEqual(removed.count, 2)
    }

    /// 通知センターの偽物（予約が残っているかを持つ）。**本物と同じく、予約は要求が届いた時点で登録され、
    /// 返事（await の戻り）だけが後から来る**。`hold` の間は返事を止める
    @MainActor
    private final class FakeCenter {
        var pending = false
        var hold = false
        var waiting: [CheckedContinuation<Void, Never>] = []
        func add() async {
            pending = true
            if hold { await withCheckedContinuation { waiting.append($0) } }
        }
        func remove() { pending = false }
        func release() { let w = waiting; waiting = []; w.forEach { $0.resume() } }
    }

    /// 🔴 入れ替えが重なっても、覚えている中身と実際の予約が食い違わない（1本ずつ順に）
    @MainActor
    func testOverlappingReschedulesStayConsistent() async throws {
        let center = FakeCenter()
        let scheduler = SeasonReminderScheduler(add: { _ in await center.add() }, removePending: { _ in center.remove() })
        let a = try spot("sp_a", name: "銀山温泉", seasons: ["winter"])
        let plan = SeasonReminder.plan(now: date(2026, 9, 30), spots: [a], wishlist: [SavedSpotKey.official("sp_a")], calendar: calendar)

        // 入れる回が2本重なる
        center.hold = true
        let first = Task { @MainActor in await scheduler.reschedule(plan, allowed: true) }
        let second = Task { @MainActor in await scheduler.reschedule(plan, allowed: true) }
        for _ in 0..<1000 where center.waiting.isEmpty { await Task.yield() }
        XCTAssertFalse(center.waiting.isEmpty, "入れる回が止まっていない（試験の前提が崩れた）")
        center.hold = false
        center.release()
        await first.value
        await second.value
        XCTAssertTrue(center.pending, "予約が残っている")
        XCTAssertEqual(scheduler.scheduled, plan)

        // 入れる回の途中に取り消し（ログアウト）が来る
        center.hold = true
        // 別の中身（春の予約）を入れる回。**中身が無いと add が呼ばれず、下の待ちが終わらない**ので前提を確かめる
        let spring = try spot("sp_b", name: "蔵王", seasons: ["spring"])
        let springPlan = try XCTUnwrap(SeasonReminder.plan(now: date(2026, 12, 2), spots: [spring],
                                                           wishlist: [SavedSpotKey.official("sp_b")], calendar: calendar))
        let adding = Task { @MainActor in await scheduler.reschedule(springPlan, allowed: true) }
        // 入れる回が **止まったのを待ってから** 取り消しを積む（「途中」の場面を本当に通す）
        for _ in 0..<1000 where center.waiting.isEmpty { await Task.yield() }
        XCTAssertFalse(center.waiting.isEmpty, "入れる回が止まっていない（試験の前提が崩れた）")
        let cancel = Task { @MainActor in await scheduler.reschedule(nil, allowed: false) }
        for _ in 0..<5 { await Task.yield() }
        center.hold = false
        center.release()
        await adding.value
        await cancel.value
        XCTAssertFalse(center.pending, "取り消しが最後なら予約は無い")
        XCTAssertNil(scheduler.scheduled)
    }

    @MainActor
    func testFailedAddIsRetriedNextTime() async throws {
        struct Boom: Error {}
        var fail = true
        var added = 0
        let scheduler = SeasonReminderScheduler(add: { _ in if fail { throw Boom() }; added += 1 }, removePending: { _ in })
        let a = try spot("sp_a", name: "銀山温泉", seasons: ["winter"])
        let plan = SeasonReminder.plan(now: date(2026, 9, 30), spots: [a], wishlist: [SavedSpotKey.official("sp_a")], calendar: calendar)
        await scheduler.reschedule(plan, allowed: true)
        XCTAssertNil(scheduler.scheduled)
        fail = false
        await scheduler.reschedule(plan, allowed: true)
        XCTAssertEqual(added, 1)
    }
}
