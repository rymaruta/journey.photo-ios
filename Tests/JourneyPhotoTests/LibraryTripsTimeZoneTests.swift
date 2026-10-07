import XCTest
@testable import JourneyPhoto

/// 「旅の写真から」の日は**撮った土地の時間帯**で切る（2026-10-07）。
///
/// 投稿した写真の撮影日は EXIF の撮った土地の壁時計で、一冊はそれで日を数える。
/// 端末の時間帯で切ると、海外の旅で選ぶ画面の日と一冊の日がずれていた
final class LibraryTripsTimeZoneTests: XCTestCase {

    private let home = (lat: 35.68, lng: 139.76)       // 東京
    private let newYork = (lat: 40.71, lng: -74.01)
    private let paris = (lat: 48.86, lng: 2.35)

    private func at(_ text: String, _ zone: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: zone)
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: text)!
    }

    private func shots(_ times: [String], zone: String, at place: (lat: Double, lng: Double)) -> [LibraryShot] {
        times.enumerated().map { i, t in
            LibraryShot(id: "s\(i)", date: at(t, zone), lat: place.lat, lng: place.lng)
        }
    }

    /// ニューヨークの夜 21 時台（UTC・日本では翌日）も、撮った土地の日（EXIF の日）に入る
    func testDaysFollowTheLocalClockWhereTaken() throws {
        let trip = try XCTUnwrap(LibraryTrips.find(
            shots(["2026-09-12 10:00", "2026-09-12 21:00", "2026-09-12 21:30",
                   "2026-09-13 09:00", "2026-09-13 21:40"], zone: "America/New_York", at: newYork),
            home: home).first)
        XCTAssertEqual(trip.days.map(\.key), ["2026-09-12", "2026-09-13"],
                       "端末の時間帯で日を切った（夜の写真が翌日になる）")
        XCTAssertEqual(trip.days.map { $0.shots.count }, [3, 2])
        XCTAssertEqual(LibraryTrips.periodText(trip), "2026.09.12 — 09.13")
        // 一冊（EXIF の壁時計の日）と同じ鍵になる
        XCTAssertEqual(ImagePreparer.takenOn("2026:09:12 21:30:00"), trip.days.first?.key)
    }

    /// 経度の目安（15 度で1時間）
    func testEstimatedTimeZone() {
        XCTAssertEqual(LibraryTrips.estimatedTimeZone(longitude: 135.77).secondsFromGMT(), 9 * 3600)
        XCTAssertEqual(LibraryTrips.estimatedTimeZone(longitude: -74.01).secondsFromGMT(), -5 * 3600)
        XCTAssertEqual(LibraryTrips.estimatedTimeZone(longitude: 2.35).secondsFromGMT(), 0)
        XCTAssertEqual(LibraryTrips.estimatedTimeZone(longitude: 180).secondsFromGMT(), 12 * 3600)
    }

    /// 地名を引いて本当の時間帯が分かったら切り直す（目安は夏時間を知らない）。
    /// パリの夏の 0 時半は、目安（UTC）では前の日になる
    func testRecutWithTheRealTimeZone() throws {
        let found = LibraryTrips.find(
            shots(["2026-09-12 10:00", "2026-09-12 15:00", "2026-09-12 20:00",
                   "2026-09-13 00:30", "2026-09-13 11:00"], zone: "Europe/Paris", at: paris),
            home: home)
        let trip = try XCTUnwrap(found.first)
        XCTAssertEqual(trip.days.map { $0.shots.count }, [4, 1], "目安（UTC）では 0 時半は前の日")
        let center = try XCTUnwrap(trip.center)
        let zone = TimeZone(identifier: "Europe/Paris")!
        let cut = try XCTUnwrap(LibraryTrips.applyingZones(found, zones: [LibraryTrips.lookupKey(center): zone]).first)
        XCTAssertEqual(cut.days.map(\.key), ["2026-09-12", "2026-09-13"])
        XCTAssertEqual(cut.days.map { $0.shots.count }, [3, 2])
        XCTAssertEqual(cut.timeZone.identifier, "Europe/Paris")
        XCTAssertEqual(cut.id, trip.id, "切り直しで旅の印を変えない")
        // 時間帯の分からない旅はそのまま
        XCTAssertEqual(LibraryTrips.applyingZones(found, zones: [:]), found)
    }

    /// 投稿済みの日の突き合わせは前後1日のずれを許す（時間帯をまたぐ旅・目安の時間帯）
    func testPostedDaysAllowOneDayOff() throws {
        let trip = try XCTUnwrap(LibraryTrips.find(
            shots(["2026-09-12 10:00", "2026-09-12 11:00", "2026-09-12 12:00",
                   "2026-09-12 13:00", "2026-09-12 14:00"], zone: "America/New_York", at: newYork),
            home: home).first)
        XCTAssertEqual(LibraryTrips.postedDays(trip: trip, postedDayKeys: ["2026-09-13"]), 1)
        XCTAssertEqual(LibraryTrips.postedDays(trip: trip, postedDayKeys: ["2026-09-11"]), 1)
        XCTAssertEqual(LibraryTrips.neighborKeys(of: "2026-03-01"), ["2026-02-28", "2026-03-01", "2026-03-02"])
    }
}
