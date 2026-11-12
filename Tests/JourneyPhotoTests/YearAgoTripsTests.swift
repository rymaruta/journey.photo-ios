import XCTest
@testable import JourneyPhoto

/// ②「去年の旅が届くみたいに」（2026-11-12・札 #543）の決まり（`YearAgoTrips`・`YearAgoRingStore`）。
final class YearAgoTripsTests: XCTestCase {

    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private let home = (lat: 35.68, lng: 139.76)
    private let taketomi = (lat: 24.33, lng: 124.09)

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyo
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    /// 竹富の3日の旅（`start` から3日・1日 `perDay` 枚）
    private func trip(_ y: Int, _ m: Int, _ d: Int, perDay: Int = 5, prefix: String = "t") -> LibraryTrip {
        var shots: [LibraryShot] = []
        for day in 0..<3 {
            for k in 0..<perDay {
                let at = date(y, m, d, 9).addingTimeInterval(Double(day) * 86_400 + Double(k) * 3600)
                shots.append(LibraryShot(id: "\(prefix)\(day)-\(k)", date: at, lat: taketomi.lat, lng: taketomi.lng))
            }
        }
        return LibraryTrips.find(shots, home: home, timeZone: tokyo)[0]
    }

    /// 1年前の今日が旅の2日目なら、その日の写真から最大4枚
    func testFindsOneYearAgoToday() throws {
        let t = trip(2025, 11, 10)
        let pick = try XCTUnwrap(YearAgoTrips.find(trips: [t], now: date(2026, 11, 11), timeZone: tokyo))
        XCTAssertEqual(pick.yearsAgo, 1)
        XCTAssertEqual(pick.day.key, "2025-11-11")
        XCTAssertEqual(pick.day.number, 2)
        XCTAssertEqual(pick.photoIds.count, 4, "最大4枚")
        XCTAssertTrue(pick.photoIds.allSatisfy { $0.hasPrefix("t1-") }, "その日でない写真が混ざった")
    }

    /// 1年前に無ければ2年前、3年前（端末の写真は直近3年）
    func testFallsBackToOlderYears() throws {
        let t = trip(2024, 11, 11)
        let pick = try XCTUnwrap(YearAgoTrips.find(trips: [t], now: date(2026, 11, 11), timeZone: tokyo))
        XCTAssertEqual(pick.yearsAgo, 2)
        // 1年前にもあれば1年前が先
        let recent = trip(2025, 11, 11, prefix: "r")
        XCTAssertEqual(YearAgoTrips.find(trips: [t, recent], now: date(2026, 11, 11), timeZone: tokyo)?.yearsAgo, 1)
    }

    /// どの年にも無ければ輪を出さない
    func testNoTripNoRing() {
        let t = trip(2025, 6, 1)
        XCTAssertNil(YearAgoTrips.find(trips: [t], now: date(2026, 11, 11), timeZone: tokyo))
        XCTAssertEqual(YearAgoTrips.ringState(pick: nil, todayKey: "2026-11-11", seenDay: nil, postedDay: nil), .hidden)
    }

    /// 少ない日は撮った分だけ（4枚に足りなくても出す）
    func testFewerPhotosThanLimit() throws {
        let t = trip(2025, 11, 11, perDay: 2)
        _ = t
        // 1日2枚では5枚に届かず旅にならないので、1日3枚×3日で、その日3枚
        let three = trip(2025, 11, 11, perDay: 3, prefix: "s")
        let pick = try XCTUnwrap(YearAgoTrips.find(trips: [three], now: date(2026, 11, 11), timeZone: tokyo))
        XCTAssertEqual(pick.photoIds.count, 3)
    }

    // MARK: - 見方

    /// 右 2/3 を叩くと次、左 1/3 は前
    func testTapZones() {
        XCTAssertTrue(YearAgoTrips.tapGoesNext(x: 200, width: 390))
        XCTAssertTrue(YearAgoTrips.tapGoesNext(x: 131, width: 390))
        XCTAssertFalse(YearAgoTrips.tapGoesNext(x: 129, width: 390))
    }

    /// 下へ払うと閉じる（縦が横より大きく 110pt 以上）
    func testSwipeDownCloses() {
        XCTAssertTrue(YearAgoTrips.swipeCloses(dx: 10, dy: 120))
        XCTAssertFalse(YearAgoTrips.swipeCloses(dx: 10, dy: 100))
        XCTAssertFalse(YearAgoTrips.swipeCloses(dx: 200, dy: 150), "横の払いで閉じた")
        XCTAssertFalse(YearAgoTrips.swipeCloses(dx: 0, dy: -200), "上へ払って閉じた")
    }

    // MARK: - 輪の状態

    func testRingStates() throws {
        let pick = try XCTUnwrap(YearAgoTrips.find(trips: [trip(2025, 11, 10)], now: date(2026, 11, 11), timeZone: tokyo))
        XCTAssertEqual(YearAgoTrips.ringState(pick: pick, todayKey: "2026-11-11", seenDay: nil, postedDay: nil), .unseen)
        XCTAssertEqual(YearAgoTrips.ringState(pick: pick, todayKey: "2026-11-11", seenDay: "2026-11-11", postedDay: nil), .seen)
        // 昨日見た印は今日の輪を灰にしない（日が変わると次の日の旅）
        XCTAssertEqual(YearAgoTrips.ringState(pick: pick, todayKey: "2026-11-11", seenDay: "2026-11-10", postedDay: nil), .unseen)
        // 出したら消える（同じ日に二重に出さない）
        XCTAssertEqual(YearAgoTrips.ringState(pick: pick, todayKey: "2026-11-11", seenDay: "2026-11-11",
                                              postedDay: "2026-11-11"), .hidden)
    }

    // MARK: - 字

    func testTexts() throws {
        let t = trip(2025, 11, 10)
        let pick = try XCTUnwrap(YearAgoTrips.find(trips: [t], now: date(2026, 11, 11), timeZone: tokyo))
        XCTAssertEqual(YearAgoTrips.title(name: "竹富町", day: pick.day, year: YearAgoTrips.year(of: pick.day)),
                       "竹富町  2025.11.11")
        XCTAssertEqual(YearAgoTrips.title(name: nil, day: pick.day, year: 2025), "2025.11.11", "地名が無いときは日付だけ")
        XCTAssertEqual(YearAgoTrips.subtitle(trip: t, day: pick.day, count: 4), "3日の旅の2日目、端末の写真から4枚")
        XCTAssertEqual(YearAgoTrips.storyText(years: 1, name: "竹富町"), "1年前の今日、竹富町")
        XCTAssertEqual(YearAgoTrips.storyText(years: 2, name: nil), "2年前の今日")
        XCTAssertEqual(YearAgoTrips.ringName(1), "1年前")
    }

    func testRingStoreIsPerUser() {
        let suite = "yearAgo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = YearAgoRingStore(defaults: defaults)
        store.markSeen("2026-11-11", for: "u1")
        store.markPosted("2026-11-11", for: "u1")
        XCTAssertEqual(store.seenDay(for: "u1"), "2026-11-11")
        XCTAssertEqual(store.postedDay(for: "u1"), "2026-11-11")
        XCTAssertNil(store.seenDay(for: "u2"))
        store.markSeen("x", for: nil)
        XCTAssertNil(store.seenDay(for: nil))
    }

    /// 作る画面に置く文字は、動かせる・消せるふつうの文字の札（明朝）
    func testComposerSeedOverlay() {
        let overlay = StoryComposerSeed.overlay("1年前の今日、竹富町")
        XCTAssertEqual(overlay.text, "1年前の今日、竹富町")
        XCTAssertEqual(overlay.kind, .text)
        XCTAssertEqual(overlay.face, .mincho)
    }
}
