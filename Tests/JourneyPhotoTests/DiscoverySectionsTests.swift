import XCTest
@testable import JourneyPhoto

/// 「さがす」の塊（モック2 の「人気スポット」「季節のおすすめ」）。
final class DiscoverySectionsTests: XCTestCase {

    private func photo(_ id: String, place: String? = nil, tags: [String] = [],
                       likes: Int? = nil, date: String = "2026-01-01") throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"",
                      "\"createdAt\":\"\(date)\""]
        if let place { fields.append("\"location\":\"\(place)\"") }
        if let likes { fields.append("\"likes\":\(likes)") }
        if !tags.isEmpty {
            fields.append("\"tags\":[\(tags.map { "\"\($0)\"" }.joined(separator: ","))]")
        }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// 写真の多い撮影地が先（同数なら名前順＝毎回同じ並び）
    func testPopularSpotsAreSortedByCount() throws {
        let photos = [
            try photo("a", place: "京都"),
            try photo("b", place: "京都"),
            try photo("c", place: "金沢"),
        ]
        let spots = DiscoverySections.popularSpots(in: photos)
        XCTAssertEqual(spots.map(\.id), ["京都", "金沢"])
        XCTAssertEqual(spots.first?.count, 2)
    }

    /// **表紙はいいねの多い写真**（その場所でいちばん見られたもの）
    func testCoverIsTheMostLiked() throws {
        let photos = [
            try photo("quiet", place: "京都", likes: 1),
            try photo("loved", place: "京都", likes: 9),
        ]
        XCTAssertEqual(DiscoverySections.popularSpots(in: photos).first?.cover.id, "loved")
    }

    /// 撮影地の無い写真は数えない
    func testPhotosWithoutAPlaceAreSkipped() throws {
        XCTAssertTrue(DiscoverySections.popularSpots(in: [try photo("a")]).isEmpty)
    }

    /// 季節は月で決まる（3〜5月は春）
    func testSeasonalTagsFollowTheMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let april = DateComponents(calendar: calendar, year: 2026, month: 4, day: 10).date!
        let december = DateComponents(calendar: calendar, year: 2026, month: 12, day: 10).date!
        XCTAssertEqual(DiscoverySections.seasonalTags(now: april, calendar: calendar).first, "春")
        XCTAssertEqual(DiscoverySections.seasonalTags(now: december, calendar: calendar).first, "冬")
    }

    /// **季節の写真は新しい順。** 季節は「いま」の話なので、古い写真を
    /// 先に出しても嬉しくない
    func testSeasonalPhotosAreNewestFirst() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let december = DateComponents(calendar: calendar, year: 2026, month: 12, day: 10).date!
        let photos = [
            try photo("old", tags: ["冬"], date: "2024-01-01"),
            try photo("new", tags: ["雪"], date: "2026-01-01"),
            try photo("other", tags: ["海"], date: "2026-02-01"),
        ]
        let seasonal = DiscoverySections.seasonal(in: photos, now: december, calendar: calendar)
        XCTAssertEqual(seasonal.map(\.id), ["new", "old"], "夏のタグが混ざっている / 並びが古い順")
    }

    /// 🔴 **札の枚数と、開いた先の枚数を一致させる。**
    /// run 55 の実機の絵では札が「2枚の写真」・開いた先が「3枚」だった。
    /// Web は同じ食い違いを `collectEntries` で直してある
    func testCardCountMatchesWhatTheDestinationShows() throws {
        let photos = [
            try photo("p1", place: "パリ"),
            try photo("p2", place: "パリ, フランス"),
            try photo("t", place: "東京"),
        ]
        let spots = DiscoverySections.popularSpots(in: photos)
        for spot in spots {
            XCTAssertEqual(spot.count,
                           PhotoQuery.photos(photos, in: .location(spot.id)).count,
                           "「\(spot.id)」の札の枚数が、開いた先と違う")
        }
        // 「パリ」は自分＋「パリ, フランス」の2枚、「パリ, フランス」は自分だけ
        XCTAssertEqual(spots.first { $0.id == "パリ" }?.count, 2)
        XCTAssertEqual(spots.first { $0.id == "パリ, フランス" }?.count, 1)
    }
}
