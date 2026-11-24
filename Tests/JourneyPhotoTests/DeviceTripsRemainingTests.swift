import XCTest
@testable import JourneyPhoto

/// 旅の残りを、続けて載せる（札 #710 の案2）。1枚載せても「まだ載せていない旅」の札が消えない
final class DeviceTripsRemainingTests: XCTestCase {

    /// 2026-09-12 00:00 JST
    private let base = Date(timeIntervalSince1970: 1_789_138_800)
    private let home = (lat: 35.68, lng: 139.76)
    private let kyoto = (lat: 35.01, lng: 135.77)

    private func shot(_ id: String, hours: Double, _ place: (lat: Double, lng: Double)) -> LibraryShot {
        LibraryShot(id: id, date: base.addingTimeInterval(hours * 3600), lat: place.lat, lng: place.lng)
    }

    /// 家の日常20枚＋京都の旅6枚（`DeviceTripsTests` と同じ形）
    private func trip() throws -> LibraryTrip {
        let shots = (0..<20).map { shot("h\($0)", hours: -24 * 30 + Double($0) * 5, home) }
            + (0..<6).map { shot("k\($0)", hours: 10 + Double($0), kyoto) }
        return try XCTUnwrap(DeviceTrips.found(in: shots).first)
    }

    /// 投稿した写真（撮影日と撮影日時）。撮影日時はコマの時刻を旅の時間帯の壁時計にしたもの
    private func posted(_ shot: LibraryShot, in trip: LibraryTrip, stamp: Bool = true) -> LibraryTrips.PostedShot {
        let wall = LibraryTrips.wallStamp(shot.date, timeZone: trip.timeZone)
        return LibraryTrips.PostedShot(key: String(wall.prefix(10)), coords: nil, stamp: stamp ? wall : nil)
    }

    /// 1枚だけ載せた旅は、残りのコマだけで出る（前は投稿した日がある旅ごと消えていた）
    func testOnePostedShotKeepsTheRest() throws {
        let trip = try trip()
        let first = try XCTUnwrap(trip.shots.first)
        let books = DeviceTrips.books([trip], posted: [posted(first, in: trip)], zones: [:], isMine: true)
        let book = try XCTUnwrap(books.first, "1枚載せただけで旅の札が消えている")
        XCTAssertEqual(book.id, trip.id, "旅の印は変えない（閉じた旅・払った途中の控えと合わせる）")
        XCTAssertEqual(book.shots.count, trip.shots.count - 1)
        XCTAssertFalse(book.shots.contains { $0.id == first.id }, "載せたコマが残っている")
        XCTAssertEqual(book.postedCount, 1)
    }

    /// 撮影日時が1秒ずれていても同じコマ（端末の時刻と EXIF の丸め）
    func testOneSecondOffStillMatches() throws {
        let trip = try trip()
        let first = try XCTUnwrap(trip.shots.first)
        let wall = LibraryTrips.wallStamp(first.date.addingTimeInterval(1), timeZone: trip.timeZone)
        let shot = LibraryTrips.PostedShot(key: String(wall.prefix(10)), coords: nil, stamp: wall)
        XCTAssertEqual(DeviceTrips.books([trip], posted: [shot], zones: [:], isMine: true).first?.postedCount, 1)
    }

    /// 残りが1枚になった旅は出さない（押しつけにしない）
    func testOneLeftIsHidden() throws {
        let trip = try trip()
        let all = trip.shots.dropLast().map { posted($0, in: trip) }
        XCTAssertTrue(DeviceTrips.books([trip], posted: all, zones: [:], isMine: true).isEmpty)
    }

    /// どのコマを載せたか分からない投稿（撮影日時が無い）がある旅は、今までどおり出さない
    func testUnmatchedPostHidesTheTrip() throws {
        let trip = try trip()
        let first = try XCTUnwrap(trip.shots.first)
        XCTAssertTrue(DeviceTrips.books([trip], posted: [posted(first, in: trip, stamp: false)],
                                        zones: [:], isMine: true).isEmpty)
    }

    /// 投稿した写真の撮影日時は EXIF の値から読む（保存の形も EXIF の形も）
    func testPostedShotsReadTheStamp() throws {
        let json = #"{"id":"p","src":"https://example.com/p.jpg","date":"2026-09-12","exif":{"dateTimeOriginal":"2026-09-12T10:05:09"}}"#
        let photo = try JSONDecoder.api.decode(Photo.self, from: Data(json.utf8))
        XCTAssertEqual(LibraryTrips.postedShots(of: [photo]).first?.stamp, "2026-09-12T10:05:09")
        XCTAssertEqual(LibraryTrips.wallStamp("2026:09:12 10:05:09"), "2026-09-12T10:05:09")
        XCTAssertNil(LibraryTrips.wallStamp("2026-09-12"))
    }

    /// 札の文: 載せた枚数と残りの枚数。急がせる言葉や中黒は使わない
    func testCardWordsForAPartlyPostedTrip() throws {
        let trip = try trip()
        let first = try XCTUnwrap(trip.shots.first)
        let book = try XCTUnwrap(DeviceTrips.books([trip], posted: [posted(first, in: trip)], zones: [:], isMine: true).first)
        XCTAssertEqual(DevelopTrips.cardLine(book, name: "京都市"),
                       L("京都市の旅", "Trip to 京都市") + "、" + L("残り5枚", "5 left"))
        XCTAssertEqual(DevelopTrips.cardDetail(limited: false, posted: 1),
                       L("1枚載せました。続きを選べます", "You posted 1. Pick the rest when you like."))
        XCTAssertEqual(DevelopTrips.cardDetail(limited: false), DevelopTrips.cardDetail(limited: false, posted: 0))
        for text in [DevelopTrips.cardLine(book, name: "京都市"), DevelopTrips.cardDetail(limited: false, posted: 3)] {
            XCTAssertFalse(text.contains("・") || text.contains("急") || text.contains("消えます"))
        }
    }

    /// 旅の日に当たる投稿の選り分けは、1枚ずつ `postedDays` を呼ぶのと同じ結果（前後の日のずれも含めて）
    func testPostedOnTripMatchesPostedDays() throws {
        let trip = try trip()
        let near = trip.center
        let keys = trip.days.map(\.key) + trip.days.flatMap { LibraryTrips.neighborKeys(of: $0.key) } + ["2026-01-01"]
        let shots = keys.flatMap { key in
            [LibraryTrips.PostedShot(key: key, coords: nil),
             LibraryTrips.PostedShot(key: key, coords: near),
             LibraryTrips.PostedShot(key: key, coords: Photo.Coords(lat: home.lat, lng: home.lng))]
        }
        for zoneKnown in [false, true] {
            var t = trip
            if zoneKnown { t = LibraryTrips.recut(trip, timeZone: trip.timeZone) }
            let expected = shots.filter { LibraryTrips.postedDays(trip: t, posted: [$0]) > 0 }
            XCTAssertEqual(LibraryTrips.postedOnTrip(t, posted: shots), expected)
        }
    }

    /// 多い件数（旅50、投稿1000、日数3）でも棚の計算はすぐ終わる。
    /// 前は旅×投稿×日数で Calendar を作り、この件数で数秒かかっていた（2026-11-23 確かめ役の指摘）
    func testBooksStayFastWithManyTripsAndPosts() throws {
        // 旅50冊（それぞれ3日・1日3コマ・10日おき）。形は京都の旅から作る（日は切り直す）
        let template = try trip()
        var trips: [LibraryTrip] = []
        for t in 0..<50 {
            var shots: [LibraryShot] = []
            for d in 0..<3 {
                for k in 0..<3 {
                    let hours: Double = Double(t * 240 + d * 24 + 10 + k)
                    shots.append(shot("t\(t)-\(d)-\(k)", hours: hours, kyoto))
                }
            }
            trips.append(LibraryTrips.keeping(template, shots: shots, postedCount: 0))
        }
        XCTAssertTrue(trips.allSatisfy { $0.days.count == 3 }, "旅が3日になっていない")
        // 投稿1000枚: 旅の日に当たらない日（撮影日時なし）が大半、旅ごとに1枚は載せたコマ
        var posts: [LibraryTrips.PostedShot] = trips.compactMap { trip in
            trip.shots.first.map { posted($0, in: trip) }
        }
        let utc = Calendar(identifier: .gregorian)
        while posts.count < 1000 {
            let date = base.addingTimeInterval(Double(posts.count) * -86_400 * 0.7)
            let c = utc.dateComponents(in: TimeZone(identifier: "Asia/Tokyo")!, from: date)
            let key = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            let coords: Photo.Coords? = posts.count.isMultiple(of: 2) ? nil : Photo.Coords(lat: home.lat, lng: home.lng)
            posts.append(LibraryTrips.PostedShot(key: key, coords: coords))
        }
        let start = Date()
        let books = DeviceTrips.books(trips, posted: posts, zones: [:], isMine: true)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(books.count, 50, "1枚ずつ載せた旅は残りで出る")
        XCTAssertLessThan(elapsed, 0.5, "棚の計算に \(elapsed) 秒かかっている")
    }
}
