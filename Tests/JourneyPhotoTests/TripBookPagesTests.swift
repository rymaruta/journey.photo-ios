import XCTest
@testable import JourneyPhoto

/// 旅の本のページを**平らな行**にする（`TripBook.pageRows`）。
///
/// 入れ子の `VStack` に戻すと、開いた瞬間に全ページの元画像を読む（2026-10-02 の調査）。
/// 行は `LazyVStack(spacing: 0)` に並べ、間は行ごとの上の余白で前（段の間 36・段の中 20）と同じに保つ
final class TripBookPagesTests: XCTestCase {

    private func photo(_ id: String, date: String, place: String? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"",
                      "\"userId\":\"owner\"", "\"date\":\"\(date)\""]
        if let place { fields.append("\"location\":\"\(place)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    func testRowsAreFlatWithTheSameGapsAsBefore() throws {
        let trip = try XCTUnwrap(TripBook.trips(from: [
            try photo("a", date: "2026-05-01", place: "金沢"),
            try photo("b", date: "2026-05-01", place: "金沢"),
            try photo("c", date: "2026-05-02", place: "福井"),
        ], timeZone: TimeZone(identifier: "Asia/Tokyo")!).first)
        let rows = TripBook.pageRows(of: TripBook.days(of: trip))
        XCTAssertEqual(rows.map(\.id), ["day-1", "photo-a", "photo-b", "day-2", "photo-c"])
        XCTAssertEqual(rows.map(\.topSpacing), [0, 20, 20, 36, 20],
                       "先頭は 0、段の間 36、段の中 20（前の VStack の spacing と同じ）")
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count, "ForEach の id は重ならない")
        if case .page(_, let dayPlace) = rows[4].kind {
            XCTAssertEqual(dayPlace, "福井")
        } else {
            XCTFail("5行目は写真")
        }
    }

    func testEmptyTripHasNoRows() {
        XCTAssertEqual(TripBook.pageRows(of: []), [])
    }

    /// 🔴 **ページは `LazyVStack` に並べる。** 画面は Linux で描けないので、配線だけは文で確かめる
    /// （`VStack` に戻すと、一冊ぶんの元画像を開いた瞬間に全部読む）
    func testPagesUseALazyStack() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Sources/JourneyPhoto/Features/Trips/TripBookView.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private var pages: some View {"))
        let body = source[start.upperBound...].prefix(400)
        XCTAssertTrue(body.contains("LazyVStack(alignment: .leading, spacing: 0)"), "ページは LazyVStack に並べる")
        XCTAssertTrue(body.contains("TripBook.pageRows("), "行は平らにしたものを使う")
    }
}
