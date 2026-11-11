import XCTest
@testable import JourneyPhoto

/// ホームの上の札は最大3枚・人で中身を替える（2026-11-12・デザインの案 第10章「どこに何を置くか」）。
/// 並べ方は `HomeTopCard.arrange`。当たる札の計算（`HomeTopCard.cards`）は `HomeTopCardTests` が見る
final class HomeTopCardArrangeTests: XCTestCase {

    private func photo(_ id: String, published: Bool? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"", "\"userId\":\"me\""]
        if let published { fields.append("\"published\":\(published)") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func spot(_ id: String) throws -> OfficialSpot {
        try JSONDecoder().decode(OfficialSpot.self, from: Data(
            #"{"spotId":"\#(id)","slug":"\#(id)","name":"[\#(id)]","stage":"published","region":{"prefecture":"京都府"}}"#.utf8))
    }

    private let plan = TripPlan(planId: "p", title: "[p]", startDate: "2026-11-14", endDate: nil, createdAt: nil)

    /// 当たる日に全部が並んだときの札（今までは6〜8枚並んだ）
    private func everything() throws -> [HomeTopCard.Choice] {
        let quiz = try XCTUnwrap(DailyQuiz.parse(Data(DailyQuizTests.json(date: "2026-11-12").utf8), date: "2026-11-12"))
        return [
            .departure(plan: plan, daysUntil: 2),
            .bookReady(trip: TripBook.Trip(id: "t", place: "", start: Date(), end: Date(), photos: [])),
            .wishlistSeason(spot: try spot("w"), season: "autumn", guide: ""),
            .inSeason(spot: try spot("s"), season: "autumn", guide: ""),
            .theme,
            .quiz(quiz),
            .oneYearAgo(photo: try photo("y"), byUploadDate: false),
        ]
    }

    private func slots(_ choices: [HomeTopCard.Choice]) -> [String] { choices.map(\.slot) }

    // MARK: - 誰の画面か

    func testAudience() throws {
        XCTAssertEqual(HomeTopCard.Audience.of(signedIn: false, myPhotos: []), .guest)
        XCTAssertEqual(HomeTopCard.Audience.of(signedIn: true, myPhotos: []), .newcomer)
        XCTAssertEqual(HomeTopCard.Audience.of(signedIn: true, myPhotos: [try photo("a"), try photo("b")]), .newcomer)
        XCTAssertEqual(HomeTopCard.Audience.of(signedIn: true,
                                               myPhotos: [try photo("a"), try photo("b"), try photo("c")]), .regular)
        // 下書きは投稿に数えない
        XCTAssertEqual(HomeTopCard.Audience.of(signedIn: true,
                                               myPhotos: [try photo("a"), try photo("b"), try photo("c", published: false)]),
                       .newcomer)
        // 自分の写真を読めていない間は常連の並び（読めたときに割らない）
        XCTAssertEqual(HomeTopCard.Audience.of(signedIn: true, myPhotos: nil), .regular)
    }

    // MARK: - 最大3枚

    func testNeverMoreThanThreeCards() throws {
        for audience in [HomeTopCard.Audience.guest, .newcomer, .regular] {
            let arranged = HomeTopCard.arrange(try everything(), audience: audience)
            XCTAssertLessThanOrEqual(arranged.count, HomeTopCard.maxCards, "\(audience)")
            XCTAssertTrue(arranged.contains(.theme), "\(audience) に今週のお題が無い")
            XCTAssertFalse(slots(arranged).contains("quiz"), "今日の一問は探すへ移した（ホームに出さない）")
        }
        XCTAssertEqual(HomeTopCard.maxCards, 3)
    }

    /// 季節の札は1枚にまとめる（行きたい場所の方が先）・旅の札も1枚
    func testOneSeasonCardAndOneTripCard() throws {
        let arranged = HomeTopCard.arrange(try everything(), audience: .newcomer)
        XCTAssertEqual(slots(arranged).filter(HomeTopCard.seasonSlots.contains), ["wishlistSeason"])
        let regular = HomeTopCard.arrange([.inSeason(spot: try spot("s"), season: "autumn", guide: ""),
                                           .wishlistSeason(spot: try spot("w"), season: "autumn", guide: ""), .theme],
                                          audience: .regular)
        XCTAssertEqual(slots(regular), ["theme", "wishlistSeason"])
        XCTAssertLessThanOrEqual(slots(HomeTopCard.arrange(try everything(), audience: .regular))
            .filter(HomeTopCard.tripSlots.contains).count, 1)
    }

    // MARK: - 人ごとの並び（案の表）

    /// 常連: 旅の札 → 今週のお題 → 届いた日だけ1年前
    func testRegularLeadsWithTheTripCard() throws {
        XCTAssertEqual(slots(HomeTopCard.arrange(try everything(), audience: .regular)),
                       ["departure", "theme", "oneYearAgo"])
        // 旅も1年前も無い日: 今週のお題 → 見頃
        XCTAssertEqual(slots(HomeTopCard.arrange([.inSeason(spot: try spot("s"), season: "autumn", guide: ""), .theme],
                                                 audience: .regular)),
                       ["theme", "inSeason"])
    }

    /// 新しい人: 今週のお題（最初の1枚）が1枚目。見頃を先に選び、空きがあれば旅の札。並びは 旅の札 → 見頃
    func testNewcomerLeadsWithTheTheme() throws {
        XCTAssertEqual(slots(HomeTopCard.arrange(try everything(), audience: .newcomer)),
                       ["theme", "departure", "wishlistSeason"])
        // 旅の札が無い日: 今週のお題 → 見頃
        XCTAssertEqual(slots(HomeTopCard.arrange([.inSeason(spot: try spot("s"), season: "autumn", guide: ""), .theme],
                                                 audience: .newcomer)),
                       ["theme", "inSeason"])
    }

    /// 未ログイン: 今週のお題 → 見頃（旅・1年前は当たらない）
    func testGuestShowsThemeThenSeason() throws {
        XCTAssertEqual(slots(HomeTopCard.arrange([.inSeason(spot: try spot("s"), season: "autumn", guide: ""), .theme],
                                                 audience: .guest)),
                       ["theme", "inSeason"])
    }

    /// 表に無い種類（ほかの章が足した札）も消えず、空きがあれば最後に出る
    func testEveryAudienceListsTheSwipeSlotAndTheTheme() {
        for audience in [HomeTopCard.Audience.guest, .newcomer, .regular] {
            XCTAssertTrue(HomeTopCard.priority(for: audience).contains("spotSwipe"), "\(audience)")
            XCTAssertTrue(HomeTopCard.priority(for: audience).contains("theme"), "\(audience)")
            XCTAssertEqual(Set(HomeTopCard.priority(for: audience)), Set(HomeTopCard.order(for: audience)),
                           "\(audience) の選ぶ順と並べる順の種類がずれている")
        }
        // 未ログインの1枚目は「撮影スポットを払う」、新しい人は2枚目（案の表）
        XCTAssertEqual(HomeTopCard.order(for: .guest).first, "spotSwipe")
        XCTAssertEqual(Array(HomeTopCard.order(for: .newcomer).prefix(2)), ["theme", "spotSwipe"])
    }

    /// 札が1枚しか当たらない日も空にしない
    func testOnlyThemeStaysOne() {
        XCTAssertEqual(HomeTopCard.arrange([.theme], audience: .regular), [.theme])
        XCTAssertEqual(HomeTopCard.arrange([.theme], audience: .guest), [.theme])
    }

    // MARK: - 画面がこの並びを使う

    func testHomeViewUsesTheArrangement() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        let view = try String(contentsOf: root.appendingPathComponent("Features/Gallery/HomeTopCardView.swift"), encoding: .utf8)
        XCTAssertTrue(view.contains("return HomeTopCard.arrange(all, audience: audience)"), "ホームが最大3枚の並びを通していない")
        let gallery = try String(contentsOf: root.appendingPathComponent("Features/Gallery/GalleryView.swift"), encoding: .utf8)
        XCTAssertTrue(gallery.contains("myPhotosKnown: auth.userId != nil && model.myPhotosOwner == auth.userId"))
    }
}
