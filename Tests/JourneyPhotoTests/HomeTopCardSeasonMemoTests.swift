import XCTest
@testable import JourneyPhoto

/// ホームの上の札で、撮影スポットの索引から決まる2枚（行きたい場所のこの季節・今日の観光スポット）と、
/// 払う入口の写真を、材料が変わったときだけ計算する直し（2026-11-26・Mac run 1804 の `home.topCard.choices`）の試験。
///
/// 1. 控えから出した並びが、控えなしの並び（前の計算）と同じ
/// 2. 控え（`HomeTopCardMemo.seasonCards`・`swipeCover`）は、材料が同じなら計算し直さない・変われば計算し直す
/// 3. 札の画面が控えを使っている
final class HomeTopCardSeasonMemoTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!

    private func spot(_ id: String, image: Bool = true, seasons: [String] = ["autumn"]) throws -> OfficialSpot {
        var fields = ["\"spotId\":\"\(id)\"", "\"slug\":\"\(id)\"", "\"name\":\"[\(id)]\"", "\"stage\":\"published\""]
        if image {
            fields.append("\"image\":{\"url\":\"https://journey-photo.com/images/spots/\(id).jpg\",\"author\":\"A\",\"license\":\"CC BY 4.0\"}")
        }
        if !seasons.isEmpty {
            let list = seasons.map { "{\"season\":\"\($0)\",\"text\":\"\($0) の \(id)\"}" }.joined(separator: ",")
            fields.append("\"seasonalGuide\":[\(list)]")
        }
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func index() throws -> [OfficialSpot] {
        var spots: [OfficialSpot] = []
        for i in 0..<60 {
            let seasons = i % 5 == 0 ? ["spring"] : (i % 3 == 0 ? ["autumn", "winter"] : ["autumn"])
            spots.append(try spot(String(format: "sp_%02d", (i * 23) % 60), image: i % 7 != 2, seasons: seasons))
        }
        return spots
    }

    private func quiz(_ spots: [OfficialSpot]) throws -> DailyQuiz {
        let picked = Array(spots.prefix(4))
        let photo = try XCTUnwrap(picked.compactMap(\.photo).first)
        return DailyQuiz(date: "2026-11-26", photo: photo,
                         choices: picked.map { DailyQuiz.Choice(spotId: $0.spotId, slug: $0.slug, name: $0.name, region: nil) },
                         answer: picked[1].spotId)
    }

    // MARK: - 1. 控えから出しても、並びは前と同じ

    func testMemoizedCardsMatchTheUnmemoizedCards() throws {
        let spots = try index()
        let quiz = try quiz(spots)
        let memo = HomeTopCardMemo()
        let wishlists: [Set<String>] = [[], [SavedSpotKey.official("sp_01"), SavedSpotKey.official("sp_44")],
                                        Set(spots.map { SavedSpotKey.official($0.slug) })]
        for offset in [0, 1, 2, 3, 40, 200] {
            let now = Date(timeIntervalSince1970: 1_795_000_000 + Double(offset) * 86_400)
            guard let today = HomeTopCard.today(now, in: utc) else { return XCTFail("今日が作れない") }
            for wishlist in wishlists {
                for q in [nil, quiz] {
                    let before = HomeTopCard.withSwipe(
                        HomeTopCard.cards(now: now, plans: [], myPhotos: [], openedBookDays: [], spots: spots,
                                          wishlist: wishlist, quiz: q, timeZone: utc),
                        spots: spots, today: today, pool: SpotSwipe.CoverPool(spots: spots))
                    let season = memo.seasonCards(.init(today: today, spotsRevision: 1, wishlist: wishlist, quiz: q), spots: spots)
                    let cards = HomeTopCard.cards(now: now, plans: [], myPhotos: [], openedBookDays: [], spots: spots,
                                                  wishlist: wishlist, quiz: q, seasonCards: season, timeZone: utc)
                    let cover = memo.swipeCover(.init(spotsRevision: 1, shown: HomeTopCard.swipeShown(cards),
                                                      day: HomeTopCard.swipeDay(today)), spots: spots)
                    XCTAssertEqual(HomeTopCard.withSwipe(cards, cover: cover), before,
                                   "日 +\(offset)・行きたい \(wishlist.count) 件・一問 \(q != nil)")
                }
            }
        }
        // 確かめの前提: 季節の札・行きたい場所の札・入口の写真のどれも、空ではない並びを比べている
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        let all = HomeTopCard.withSwipe(
            HomeTopCard.cards(now: now, plans: [], myPhotos: [], openedBookDays: [], spots: spots,
                              wishlist: [SavedSpotKey.official("sp_01")], timeZone: utc),
            spots: spots, today: HomeTopCard.today(now, in: utc))
        XCTAssertTrue(all.contains { $0.slot == "inSeason" }, "季節の札が出ていない（比べる意味が無い）")
        XCTAssertTrue(all.contains { if case .wishlistSeason = $0 { return true } else { return false } })
        XCTAssertTrue(all.contains { if case .swipe(let cover) = $0 { return cover != nil } else { return false } })
    }

    // MARK: - 2. 材料が同じなら計算し直さない

    func testSeasonCardsAreComputedOnlyWhenTheKeyChanges() throws {
        let spots = try index()
        let quiz = try quiz(spots)
        let memo = HomeTopCardMemo()
        let day = Date(timeIntervalSince1970: 1_795_000_000)
        let key = HomeTopCardMemo.SeasonKey(today: day, spotsRevision: 3, wishlist: ["SPOT-sp_01"], quiz: nil)
        for _ in 0..<5 { _ = memo.seasonCards(key, spots: spots) }
        XCTAssertEqual(memo.seasonComputes, 1, "同じ材料なのに計算し直した（body のたびに索引の全件を走査する）")
        for changed in [
            HomeTopCardMemo.SeasonKey(today: day.addingTimeInterval(86_400), spotsRevision: 3, wishlist: ["SPOT-sp_01"], quiz: nil),
            HomeTopCardMemo.SeasonKey(today: day, spotsRevision: 4, wishlist: ["SPOT-sp_01"], quiz: nil),
            HomeTopCardMemo.SeasonKey(today: day, spotsRevision: 3, wishlist: [], quiz: nil),
            HomeTopCardMemo.SeasonKey(today: day, spotsRevision: 3, wishlist: ["SPOT-sp_01"], quiz: quiz),
        ] {
            let before = memo.seasonComputes
            _ = memo.seasonCards(changed, spots: spots)
            XCTAssertEqual(memo.seasonComputes, before + 1, "材料が変わったら計算し直す: \(changed)")
        }
    }

    func testSwipeCoverIsPickedOnlyWhenTheKeyChanges() throws {
        let spots = try index()
        let memo = HomeTopCardMemo()
        let key = HomeTopCardMemo.SwipeKey(spotsRevision: 1, shown: ["sp_01"], day: 20_000)
        for _ in 0..<5 { _ = memo.swipeCover(key, spots: spots) }
        XCTAssertEqual(memo.swipeComputes, 1, "同じ材料なのに選び直した")
        XCTAssertEqual(memo.poolBuilds, 1)
        for changed in [
            HomeTopCardMemo.SwipeKey(spotsRevision: 2, shown: ["sp_01"], day: 20_000),
            HomeTopCardMemo.SwipeKey(spotsRevision: 1, shown: [], day: 20_000),
            HomeTopCardMemo.SwipeKey(spotsRevision: 1, shown: ["sp_01"], day: 20_001),
        ] {
            let before = memo.swipeComputes
            _ = memo.swipeCover(changed, spots: spots)
            XCTAssertEqual(memo.swipeComputes, before + 1, "材料が変わったら選び直す: \(changed)")
        }
        // 選ぶ 1 件は前の計算と同じ
        XCTAssertEqual(memo.swipeCover(key, spots: spots)?.spotId,
                       SpotSwipe.CoverPool(spots: spots).cover(spots: spots, excluding: ["sp_01"], day: 20_000)?.spotId)
    }

    // MARK: - 3. 配線

    /// 🔴 札の画面が控えを使う（外すと body のたびに索引の全件を走査する）
    func testHomeTopCardViewUsesTheSeasonMemo() throws {
        let view = try source("Sources/JourneyPhoto/Features/Gallery/HomeTopCardView.swift")
        XCTAssertTrue(view.contains("memo.seasonCards(.init(today: $0, spotsRevision: spotsRevision, wishlist: wishedKeys, quiz: quiz), spots: spots)"),
                      "索引から決まる2枚を控えから出していない")
        XCTAssertTrue(view.contains("seasonCards: seasonCards)"), "控えた2枚を札の並びに渡していない")
        XCTAssertTrue(view.contains("let cover = memo.swipeCover("), "入口の写真を控えから出していない")
        XCTAssertTrue(view.contains("HomeTopCard.withSwipe(cards, cover: cover)"), "控えた入口の写真で並べていない")
        XCTAssertFalse(view.contains("pool: memo.coverPool("), "入口の写真を body のたびに選び直している")
    }
}
