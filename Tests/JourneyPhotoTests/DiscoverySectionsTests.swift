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
        // 「パリ」と「パリ, フランス」は1枚の札「パリ」にまとめる（2026-10-21）。2枚
        XCTAssertEqual(spots.first { $0.id == "パリ" }?.count, 2)
        XCTAssertNil(spots.first { $0.id == "パリ, フランス" })
    }

    /// 🔴 全画面の点検（2026-10-21・11-探す）: 本番の写真の撮影地そのままで、
    /// 「フランス」（国名だけ）と「フランス ヴェルサイユ」の札が並び、**「フランス」が2枚**に見えた。
    /// 市・名所の名前でまとめ、国名だけの撮影地は出さない
    func testPopularSpotsGroupByCityAndSkipCountryOnly() throws {
        // 2026-10-21 の本番の `/photos` にあった撮影地（フランスの分）
        let photos = [
            try photo("stone", place: "フランス", likes: 9),
            try photo("v1", place: "フランス ヴェルサイユ"),
            try photo("v2", place: "フランス ヴェルサイユ"),
            try photo("v3", place: "ヴェルサイユ, Versailles, Yvelines, イル＝ド＝フランス地域圏, フランス・メトロポリテーヌ, 78000, フランス"),
            try photo("p1", place: "パリ"),
            try photo("p2", place: "パリ, フランス"),
            try photo("g", place: "オペラ・ガルニエ（パリ）"),
        ]
        let spots = DiscoverySections.popularSpots(in: photos)
        let names = spots.map { LocationMatch.display($0.id) }
        // 国名だけの札は無い・同じ名前の札は2枚にならない
        XCTAssertFalse(names.contains { DiscoverySections.spotName($0) == nil }, "\(names)")
        XCTAssertFalse(names.contains { $0.hasPrefix("フランス") }, "\(names)")
        XCTAssertEqual(Set(names).count, names.count, "\(names)")
        XCTAssertEqual(spots.first { $0.id == "ヴェルサイユ" }?.count, 3)
        // 「パリ」の行き先はオペラ・ガルニエ（パリ）も拾う（数は行き先と同じ）
        XCTAssertEqual(spots.first { $0.id == "パリ" }?.count, 3)
        // 国名だけの写真は、どの札の表紙にもならない（いいねが最多でも）
        XCTAssertFalse(spots.contains { $0.cover.id == "stone" })
        for spot in spots {
            XCTAssertEqual(spot.count, PhotoQuery.photos(photos, in: .location(spot.id)).count)
        }
    }

    /// 札の名前（市・名所の細かさ）。国名・郵便番号を落とし、元の撮影地に在る語だけを使う
    func testSpotNameKeepsCityOrLandmark() {
        XCTAssertEqual(DiscoverySections.spotName("パリ, フランス"), "パリ")
        XCTAssertEqual(DiscoverySections.spotName("フランス ヴェルサイユ"), "ヴェルサイユ")
        XCTAssertEqual(DiscoverySections.spotName("板橋区, 日本"), "板橋区")
        XCTAssertEqual(DiscoverySections.spotName("蔵王キツネ村, 南蔵王七ヶ宿線, 福岡八宮, 白石市, 宮城県, 989-0733, 日本"),
                       "蔵王キツネ村")
        XCTAssertEqual(DiscoverySections.spotName("宮城県, 白石市, 蔵王キツネ村"), "蔵王キツネ村")
        XCTAssertEqual(DiscoverySections.spotName("東京都, 渋谷区"), "渋谷区")
        XCTAssertEqual(DiscoverySections.spotName("白川村, 岐阜県"), "白川村")
        XCTAssertEqual(DiscoverySections.spotName("Louvre, Paris, France"), "Louvre")
        XCTAssertEqual(DiscoverySections.spotName("Kyoto Japan"), "Kyoto")
        XCTAssertEqual(DiscoverySections.spotName("Turkey Hill"), "Turkey Hill")
        XCTAssertEqual(DiscoverySections.spotName("オペラ・ガルニエ（パリ）"), "オペラ・ガルニエ（パリ）")
        XCTAssertEqual(DiscoverySections.spotName("山中湖"), "山中湖")
        XCTAssertNil(DiscoverySections.spotName("フランス"))
        XCTAssertNil(DiscoverySections.spotName("France"))
        XCTAssertNil(DiscoverySections.spotName("日本"))
        XCTAssertNil(DiscoverySections.spotName("  "))
        XCTAssertNil(DiscoverySections.spotName(nil))
    }
}
