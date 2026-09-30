import XCTest
@testable import JourneyPhoto

/// 旅の一冊を1枚の画像にして配る（`TripBookCard`）。
///
/// 固定したいのは:
///  1. 載せる文字は一冊の画面と同じ値だけ。数えられない距離は載せない（「—」を1行の文に出さない）
///  2. 表紙は枠いっぱいに切り抜き、持ち主が選んだ中心を残す。写真の外（黒い隙間）は見せない
///  3. ファイルの名前は旅ごとに1つで、記号を含まない
final class TripBookCardTests: XCTestCase {

    private func photo(_ id: String, location: String? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\""]
        if let location { fields.append("\"location\":\"\(location)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func trip(id: String = "2026-09-12", photos: [Photo]) -> TripBook.Trip {
        let start = Date(timeIntervalSince1970: 1_789_171_200) // 2026-09-12 UTC
        return TripBook.Trip(id: id, place: "金沢", start: start, end: start.addingTimeInterval(2 * 86_400), photos: photos)
    }

    func testLinesMatchTheBookScreen() throws {
        let t = trip(photos: [try photo("a", location: "兼六園"), try photo("b", location: "兼六園"), try photo("c", location: "ひがし茶屋街")])
        let lines = TripBookCard.lines(of: t, distance: 12.4)
        XCTAssertEqual(lines.title, TripBook.title(of: t))
        XCTAssertEqual(lines.period, "\(TripBook.dateRange(from: t.start, to: t.end)) · \(TripBook.daysLabel(t.days))")
        XCTAssertEqual(lines.stats, L("3枚 · 撮影地 2 · 移動（直線）12 km", "3 photos · 2 places · 12 km (straight line)"))
        // 数えられない距離は載せない
        XCTAssertFalse(TripBookCard.lines(of: t, distance: nil).stats.contains("km"))
    }

    func testCoverFillsTheFrameAndKeepsTheChosenCenter() {
        let canvas = TripBookCard.size
        // 横長の写真（3:2）を縦長の枠へ: 高さに合わせて、横がはみ出す
        let wide = CGSize(width: 3000, height: 2000)
        let centered = TripBookCard.coverRect(image: wide, in: canvas, focal: nil)
        XCTAssertEqual(centered.height, canvas.height, accuracy: 0.5)
        XCTAssertEqual(centered.midX, canvas.width / 2, accuracy: 0.5)
        // 中心を左端に寄せても、写真の外は見せない（左端は 0 まで）
        let left = TripBookCard.coverRect(image: wide, in: canvas, focal: Photo.FocalPoint(x: 0, y: 0.5))
        XCTAssertEqual(left.minX, 0, accuracy: 0.5)
        let right = TripBookCard.coverRect(image: wide, in: canvas, focal: Photo.FocalPoint(x: 1, y: 0.5))
        XCTAssertEqual(right.maxX, canvas.width, accuracy: 0.5)
        // 範囲外の値も枠の中に収める
        let wild = TripBookCard.coverRect(image: wide, in: canvas, focal: Photo.FocalPoint(x: 5, y: -3))
        XCTAssertLessThanOrEqual(wild.minX, 0)
        XCTAssertGreaterThanOrEqual(wild.maxX, canvas.width - 0.5)
        // 大きさの無い写真は枠そのもの
        XCTAssertEqual(TripBookCard.coverRect(image: .zero, in: canvas, focal: nil), CGRect(origin: .zero, size: canvas))
    }

    func testFileNameIsSafeAndStablePerTrip() throws {
        let t = trip(id: "2026-09-12|金沢/../x", photos: [])
        let name = TripBookCard.fileName(for: t)
        XCTAssertEqual(name, "trip-book-20260912x.jpg")
        XCTAssertEqual(name, TripBookCard.fileName(for: t))
        XCTAssertEqual(TripBookCard.fileName(for: trip(id: "金沢", photos: [])), "trip-book-card.jpg")
    }
}
