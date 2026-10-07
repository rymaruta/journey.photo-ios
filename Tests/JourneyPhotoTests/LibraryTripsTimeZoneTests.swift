import XCTest
@testable import JourneyPhoto

/// 「旅の写真から」の日は**撮った土地の時間帯**で切る（2026-10-07）。
///
/// 投稿した写真の撮影日は EXIF の撮った土地の壁時計で、一冊はそれで日を数える。
/// 端末の時間帯で切ると、海外の旅で選ぶ画面の日と一冊の日がずれていた
final class LibraryTripsTimeZoneTests: XCTestCase {

    private let home = (lat: 35.68, lng: 139.76)       // 東京
    private let newYork = (lat: 40.71, lng: -74.01)
    private let chicago = (lat: 41.88, lng: -87.63)
    private let paris = (lat: 48.86, lng: 2.35)
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

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

    /// ニューヨークの夜 21 時台（日本の端末では翌日）も、撮った土地の日（EXIF の日）に入る
    func testDaysFollowTheLocalClockWhereTaken() throws {
        let trip = try XCTUnwrap(LibraryTrips.find(
            shots(["2026-09-12 10:00", "2026-09-12 21:00", "2026-09-12 21:30",
                   "2026-09-13 09:00", "2026-09-13 21:40"], zone: "America/New_York", at: newYork),
            home: home, deviceTimeZone: tokyo).first)
        XCTAssertEqual(trip.days.map(\.key), ["2026-09-12", "2026-09-13"],
                       "端末の時間帯で日を切った（夜の写真が翌日になる）")
        XCTAssertEqual(trip.days.map { $0.shots.count }, [3, 2])
        XCTAssertEqual(LibraryTrips.periodText(trip), "2026.09.12 — 09.13")
        XCTAssertFalse(trip.zoneIsKnown, "目安の時間帯を本当の時間帯と扱った")
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

    /// 国内・近くの旅は端末の時間帯（目安は夏時間も国の境も知らない）。はっきり外国の旅だけ目安
    func testGuessPrefersTheDeviceZoneWhenClose() {
        let summer = at("2026-07-10 12:00", "UTC")
        let ny = TimeZone(identifier: "America/New_York")!
        // シカゴ（目安 -6）とニューヨークの標準時（-5）は1時間差 → 端末の時間帯
        XCTAssertEqual(LibraryTrips.guessedTimeZone(longitude: chicago.lng, at: summer, device: ny), ny)
        // マドリード（目安 0）とパリの端末（標準時 +1）→ 端末
        let parisZone = TimeZone(identifier: "Europe/Paris")!
        XCTAssertEqual(LibraryTrips.guessedTimeZone(longitude: -3.70, at: summer, device: parisZone), parisZone)
        // 日本の端末で京都 → 端末、パリ → 目安
        XCTAssertEqual(LibraryTrips.guessedTimeZone(longitude: 135.77, at: summer, device: tokyo), tokyo)
        XCTAssertEqual(LibraryTrips.guessedTimeZone(longitude: paris.lng, at: summer, device: tokyo).secondsFromGMT(), 0)
    }

    /// ニューヨークの端末で夏のシカゴ。0 時半の写真を前の日に回さない（目安の -6 では 23:30 になる）
    func testDomesticTripInSummerUsesTheDeviceZone() throws {
        let ny = TimeZone(identifier: "America/New_York")!
        let trip = try XCTUnwrap(LibraryTrips.find(
            shots(["2026-07-12 10:00", "2026-07-12 15:00", "2026-07-12 20:00",
                   "2026-07-13 00:30", "2026-07-13 11:00"], zone: "America/Chicago", at: chicago),
            home: (lat: newYork.lat, lng: newYork.lng), deviceTimeZone: ny).first)
        XCTAssertEqual(trip.timeZone, ny)
        XCTAssertEqual(trip.days.map(\.key), ["2026-07-12", "2026-07-13"])
        XCTAssertEqual(trip.days.map { $0.shots.count }, [3, 2], "0 時半の写真が前の日に回った")
    }

    /// 地名を引いて本当の時間帯が分かったら切り直す（目安は夏時間を知らない）。
    /// パリの夏の 0 時半は、目安（UTC）では前の日になる
    func testRecutWithTheRealTimeZone() throws {
        let found = LibraryTrips.find(
            shots(["2026-09-12 10:00", "2026-09-12 15:00", "2026-09-12 20:00",
                   "2026-09-13 00:30", "2026-09-13 11:00"], zone: "Europe/Paris", at: paris),
            home: home, deviceTimeZone: tokyo)
        let trip = try XCTUnwrap(found.first)
        XCTAssertEqual(trip.days.map { $0.shots.count }, [4, 1], "目安（UTC）では 0 時半は前の日")
        let center = try XCTUnwrap(trip.center)
        let zone = TimeZone(identifier: "Europe/Paris")!
        let cut = try XCTUnwrap(LibraryTrips.applyingZones(found, zones: [LibraryTrips.lookupKey(center): zone]).first)
        XCTAssertEqual(cut.days.map(\.key), ["2026-09-12", "2026-09-13"])
        XCTAssertEqual(cut.days.map { $0.shots.count }, [3, 2])
        XCTAssertEqual(cut.timeZone.identifier, "Europe/Paris")
        XCTAssertTrue(cut.zoneIsKnown)
        XCTAssertEqual(cut.id, trip.id, "切り直しで旅の印を変えない")
        // 時間帯の分からない旅はそのまま
        XCTAssertEqual(LibraryTrips.applyingZones(found, zones: [:]), found)
    }

    /// 日の代表点の鍵（選ぶ画面が引く地名）で分かった時間帯でも切り直す。
    /// 旅の代表点の鍵があればそちらが先
    func testZoneFoundUnderADayCenterRecutsTheTrip() throws {
        // 2日目だけ少し離れた所で撮る（日の代表点が旅の代表点と別の鍵になる）
        let away = (lat: 48.80, lng: 2.13)  // ヴェルサイユ
        let found = LibraryTrips.find(
            shots(["2026-09-12 10:00", "2026-09-12 15:00", "2026-09-12 20:00"], zone: "Europe/Paris", at: paris)
            + shots(["2026-09-13 00:30", "2026-09-13 11:00"], zone: "Europe/Paris", at: away)
                .map { LibraryShot(id: "v" + $0.id, date: $0.date, lat: $0.lat, lng: $0.lng) },
            home: home, deviceTimeZone: tokyo)
        let trip = try XCTUnwrap(found.first)
        let center = try XCTUnwrap(trip.center)
        let dayKey = try XCTUnwrap(trip.days.compactMap(\.center).map(LibraryTrips.lookupKey)
            .first { $0 != LibraryTrips.lookupKey(center) })
        let paris = TimeZone(identifier: "Europe/Paris")!
        let cut = try XCTUnwrap(LibraryTrips.applyingZones(found, zones: [dayKey: paris]).first)
        XCTAssertEqual(cut.timeZone, paris, "日の代表点の鍵で分かった時間帯で切り直さない")
        XCTAssertEqual(cut.days.map { $0.shots.count }, [3, 2])
        // 代表点の鍵があればそちらを使う
        let london = TimeZone(identifier: "Europe/London")!
        let both = try XCTUnwrap(LibraryTrips.applyingZones(
            found, zones: [dayKey: paris, LibraryTrips.lookupKey(center): london]).first)
        XCTAssertEqual(both.timeZone, london)
        // 選ぶ画面はモデルの今の旅を読む（同じ id）
        XCTAssertEqual(LibraryTrips.current(trip, in: [cut]).timeZone, paris)
        XCTAssertEqual(LibraryTrips.current(trip, in: []).timeZone, trip.timeZone)
    }

    /// 前後1日のずれを許すのは、目安の時間帯の旅で、撮影地が旅の近くの写真だけ
    func testPostedDaysAllowOneDayOffOnlyNearbyWhileEstimated() throws {
        let estimated = try XCTUnwrap(LibraryTrips.find(
            shots(["2026-09-12 10:00", "2026-09-12 11:00", "2026-09-12 12:00",
                   "2026-09-12 13:00", "2026-09-12 14:00"], zone: "America/New_York", at: newYork),
            home: home, deviceTimeZone: tokyo).first)
        let near = Photo.Coords(lat: 40.75, lng: -73.99)
        XCTAssertEqual(LibraryTrips.postedDays(trip: estimated, posted: [.init(key: "2026-09-13", coords: near)]), 1)
        XCTAssertEqual(LibraryTrips.postedDays(trip: estimated, posted: [.init(key: "2026-09-11", coords: near)]), 1)
        XCTAssertEqual(LibraryTrips.postedDays(trip: estimated, posted: [.init(key: "2026-09-12", coords: nil)]), 1,
                       "同じ日は撮影地が無くても数える")
        XCTAssertEqual(LibraryTrips.postedDays(trip: estimated, posted: [.init(key: "2026-09-13", coords: nil)]), 0,
                       "撮影地の無い写真に1日のずれを許した")
        // 本当の時間帯が分かったら、同じ日だけ
        let known = LibraryTrips.recut(estimated, timeZone: TimeZone(identifier: "America/New_York")!)
        XCTAssertEqual(LibraryTrips.postedDays(trip: known, posted: [.init(key: "2026-09-13", coords: near)]), 0)
        XCTAssertEqual(LibraryTrips.neighborKeys(of: "2026-03-01"), ["2026-02-28", "2026-03-01", "2026-03-02"])
    }

    /// 旅の翌日に家で撮って投稿した1枚で、まだ何も上げていない旅を「投稿済み」にしない
    func testHomePhotoTheNextDayIsNotAPostedTripDay() throws {
        let trip = try XCTUnwrap(LibraryTrips.find(
            shots(["2026-09-12 10:00", "2026-09-13 10:00", "2026-09-13 15:00",
                   "2026-09-14 10:00", "2026-09-14 18:00"], zone: "Europe/Paris", at: paris),
            home: home, deviceTimeZone: tokyo).first)
        XCTAssertFalse(trip.zoneIsKnown)
        let homePhoto = LibraryTrips.PostedShot(key: "2026-09-15", coords: Photo.Coords(lat: 35.68, lng: 139.76))
        XCTAssertEqual(LibraryTrips.postedDays(trip: trip, posted: [homePhoto]), 0,
                       "家で撮った翌日の投稿で、旅が投稿済みの側に回った")
        XCTAssertEqual(LibraryTrips.postedDays(trip: trip, posted: [.init(key: "2026-09-15", coords: nil)]), 0)
    }

    /// 投稿の撮影日と撮影地を拾う（撮影日の無い写真は入れない）
    func testPostedShotsOfPhotos() throws {
        func photo(_ id: String, date: String?, coords: String?) throws -> Photo {
            var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\""]
            if let date { fields.append("\"date\":\"\(date)\"") }
            if let coords { fields.append("\"coords\":\(coords)") }
            return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
        }
        let shots = LibraryTrips.postedShots(of: [
            try photo("a", date: "2026-09-13T08:00:00", coords: "{\"lat\":48.86,\"lng\":2.35}"),
            try photo("b", date: nil, coords: nil),
            try photo("c", date: "2026-09-14", coords: nil),
        ])
        XCTAssertEqual(shots, [.init(key: "2026-09-13", coords: Photo.Coords(lat: 48.86, lng: 2.35)),
                               .init(key: "2026-09-14", coords: nil)])
    }
}
