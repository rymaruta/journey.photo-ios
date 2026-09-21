import XCTest
@testable import JourneyPhoto

final class TimelineTests: XCTestCase {

    private func photo(id: String, date: String? = nil, createdAt: String? = nil,
                       exifDate: String? = nil) throws -> Photo {
        var fields: [String] = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\""]
        if let date { fields.append("\"date\":\"\(date)\"") }
        if let createdAt { fields.append("\"createdAt\":\"\(createdAt)\"") }
        if let exifDate { fields.append("\"exif\":{\"dateTimeOriginal\":\"\(exifDate)\"}") }
        let json = "{\(fields.joined(separator: ","))}"
        return try JSONDecoder.api.decode(Photo.self, from: Data(json.utf8))
    }

    /// **`Date` に変換しない。** "2024-10-12" を UTC 0時として読んで端末の
    /// ゾーンに直すと、UTC より西の利用者には1日（＝月をまたぐと1か月）
    /// 前に見える。Web 側が実際に踏んだ穴。
    func testUsesStoredStringWithoutTimezoneConversion() throws {
        let p = try photo(id: "a", date: "2024-10-01")
        let ym = try XCTUnwrap(PhotoTimeline.yearMonth(of: p))
        XCTAssertEqual(ym.year, 2024)
        XCTAssertEqual(ym.month, 10)
    }

    /// EXIF の日付は ":" 区切り。両方受ける。
    func testAcceptsExifColonFormat() throws {
        let p = try photo(id: "a", exifDate: "2026:09:13 08:21:05")
        let ym = try XCTUnwrap(PhotoTimeline.yearMonth(of: p))
        XCTAssertEqual(ym.year, 2026)
        XCTAssertEqual(ym.month, 9)
    }

    /// 撮影日 → EXIF → 登録日 の順。
    func testPrefersShootingDateOverCreatedAt() throws {
        let p = try photo(id: "a", date: "2020-01-05", createdAt: "2026-09-13T00:00:00Z")
        let ym = try XCTUnwrap(PhotoTimeline.yearMonth(of: p))
        XCTAssertEqual(ym.year, 2020)
    }

    /// **年月が読めない写真を落とさない。** 落とすと「一覧には在るのに
    /// 年表に出ない」写真ができる。
    func testUndatedPhotosGoToTheirOwnSection() throws {
        let sections = PhotoTimeline.group([
            try photo(id: "a", date: "2024-10-01"),
            try photo(id: "b"),
        ])
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections.last?.id, "unknown")
        XCTAssertEqual(sections.last?.photos.map(\.id), ["b"])
    }

    func testNewestMonthFirst() throws {
        let sections = PhotoTimeline.group([
            try photo(id: "old", date: "2023-01-01"),
            try photo(id: "new", date: "2026-05-01"),
        ])
        XCTAssertEqual(sections.map(\.id), ["2026-05", "2023-01"])
    }
}
