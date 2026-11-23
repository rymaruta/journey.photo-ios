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
}
