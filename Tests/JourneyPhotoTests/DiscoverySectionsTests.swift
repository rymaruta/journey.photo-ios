import XCTest
@testable import JourneyPhoto

/// 「さがす」の塊（モック2 の「人気スポット」「季節のおすすめ」）。
final class DiscoverySectionsTests: XCTestCase {

    private func photo(_ id: String, place: String? = nil, tags: [String] = [],
                       likes: Int? = nil, date: String = "2026-01-01",
                       category: String? = "風景", taken: String? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"",
                      "\"createdAt\":\"\(date)\""]
        if let category { fields.append("\"category\":\"\(category)\"") }
        if let taken { fields.append("\"date\":\"\(taken)\"") }
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

    /// 🔴 2026-10-07: 秋の「いまの季節の写真」に、ご飯🍚（タグ「秋」・分類 食べ物）や
    /// 冬の雪景色（タグ forest →「森」）が並んでいた。
    /// 季節を言う語だけで当て、料理・分類の無い写真・ほかの季節の語を持つ写真・
    /// 撮影日が別の季節の写真は外す
    func testSeasonalUsesOnlySeasonWordsAndSkipsFoodAndOtherSeasons() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let october = DateComponents(calendar: calendar, year: 2026, month: 10, day: 7).date!
        let photos = [
            try photo("versailles", tags: ["秋"], category: "建築", taken: "2024-10-11"),
            try photo("momiji", tags: ["autumn-leaves"], category: "nature"),
            try photo("rice", tags: ["秋"], category: "食べ物", taken: "2026-09-17"),
            try photo("rice2", tags: ["autumn"], category: "ご飯"),
            try photo("nocategory", tags: ["秋"], category: nil),
            try photo("snowforest", tags: ["forest", "winter"], category: "landscape"),
            try photo("forest", tags: ["森"]),
            try photo("mixed", tags: ["秋", "winter"]),
            try photo("takenInJanuary", tags: ["秋"], taken: "2026-01-20"),
        ]
        let seasonal = DiscoverySections.seasonal(in: photos, now: october, calendar: calendar, limit: .max)
        XCTAssertEqual(Set(seasonal.map(\.id)), ["versailles", "momiji"])
        XCTAssertEqual(DiscoverySections.seasonalTags(now: october, calendar: calendar), ["秋", "紅葉"])
    }

    /// 「すべて」の先の注記。森は入れない。英語表示では英語の語で書く（以前は「#秋 #紅葉 #森」のまま）
    func testSeasonalNoteFollowsTheWordsAndLanguage() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let october = DateComponents(calendar: calendar, year: 2026, month: 10, day: 7).date!
        let note = DiscoverySections.seasonalNote(now: october, calendar: calendar)
        XCTAssertFalse(note.contains("森"))
        XCTAssertEqual(note, L("#秋 #紅葉（ほかの季節に撮った写真・料理・分類の無い写真は入れない）",
                               "Tagged autumn or autumn leaves (excluding photos taken in another season, food and uncategorized photos)"))
        // 南半球の写真は半年ずらすので、月の範囲は書かない
        XCTAssertFalse(note.contains("9〜11月") || note.contains("Sep–Nov"))
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
