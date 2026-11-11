import XCTest
@testable import JourneyPhoto

/// 撮影スポットを払う（2026-11-11・`SpotSwipe`・`SpotSwipeProgress`・`SpotSwipeView`）。
///
/// 固定したいのは:
///  1. 挟む札は「行きたい」が1つ以上で、5枚目から。払って続けたら次は10枚あと
///  2. ホームの札の**1枚目**が入口（新しい段は足さない・ほかの札の並びは変えない）
///  3. 入口の一行は2回目から「行きたい n か所 · 続きから」
///  4. 払った札は端末に残り、次は出さない。全部見たら最初から
///  5. 未ログインでも開ける（払う画面はログインの画面で止めない）・ログインはシートで払う画面に戻る
final class SpotSwipeTests: XCTestCase {

    private func spot(_ id: String, image: Bool = true) throws -> OfficialSpot {
        var fields = ["\"spotId\":\"\(id)\"", "\"slug\":\"\(id)\"", "\"name\":\"[\(id)]\"", "\"stage\":\"published\""]
        if image {
            fields.append("\"image\":{\"url\":\"https://journey-photo.com/images/spots/\(id).jpg\",\"author\":\"A\",\"license\":\"CC BY 4.0\"}")
        }
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/\(path)"), encoding: .utf8)
    }

    private func freshDefaults() -> UserDefaults {
        let name = "SpotSwipeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - 1. 挟む札

    func testPauseNeedsAWantAndFiveSwipes() {
        XCTAssertFalse(SpotSwipe.showsPause(decisions: 4, wants: 1, continuedAt: nil))
        XCTAssertTrue(SpotSwipe.showsPause(decisions: 5, wants: 1, continuedAt: nil))
        XCTAssertFalse(SpotSwipe.showsPause(decisions: 5, wants: 0, continuedAt: nil),
                       "「行きたい」が無ければ挟まない（見せる結果が無い）")
        XCTAssertTrue(SpotSwipe.showsPause(decisions: 8, wants: 2, continuedAt: nil))
    }

    func testPauseReturnsTenSwipesAfterContinuing() {
        XCTAssertFalse(SpotSwipe.showsPause(decisions: 5, wants: 1, continuedAt: 5), "続けたらすぐには出さない")
        XCTAssertFalse(SpotSwipe.showsPause(decisions: 14, wants: 3, continuedAt: 5))
        XCTAssertTrue(SpotSwipe.showsPause(decisions: 15, wants: 3, continuedAt: 5))
        XCTAssertEqual(SpotSwipe.firstPause, 5)
        XCTAssertEqual(SpotSwipe.pauseEvery, 10)
    }

    // MARK: - 2. ホームの1枚目

    func testSwipeEntryIsFirstAndKeepsOtherCards() throws {
        let spots = [try spot("a"), try spot("b"), try spot("c")]
        let base: [HomeTopCard.Choice] = [.theme]
        let cards = HomeTopCard.withSwipe(base, spots: spots, today: nil)
        XCTAssertEqual(cards.map(\.slot), ["swipe", "theme"])
        // 2度かけても入口は1枚
        XCTAssertEqual(HomeTopCard.withSwipe(cards, spots: spots, today: nil).map(\.slot), ["swipe", "theme"])
    }

    func testSwipeCoverAvoidsCardsShownAndNeedsPhoto() throws {
        let a = try spot("a"), b = try spot("b"), noPhoto = try spot("c", image: false)
        let cards = HomeTopCard.withSwipe([.inSeason(spot: a, season: "autumn", guide: "秋"), .theme],
                                          spots: [a, b, noPhoto], today: nil)
        guard case .swipe(let cover)? = cards.first else { return XCTFail("1枚目が入口ではない") }
        XCTAssertEqual(cover?.spotId, "b", "ほかの札に出ている場所・写真の無い場所は使わない")
        XCTAssertNil(SpotSwipe.cover(spots: [noPhoto], excluding: [], day: 3), "写真を出せる場所が無ければ写真なしの札")
    }

    func testSwipeCoverIsStableWithinADay() throws {
        let spots = try ["a", "b", "c", "d"].map { try spot($0) }
        XCTAssertEqual(SpotSwipe.cover(spots: spots, excluding: [], day: 20_000)?.spotId,
                       SpotSwipe.cover(spots: spots.reversed(), excluding: [], day: 20_000)?.spotId,
                       "索引の並びが変わっても同じ日なら同じ写真")
        XCTAssertNotEqual(SpotSwipe.cover(spots: spots, excluding: [], day: 20_000)?.spotId,
                          SpotSwipe.cover(spots: spots, excluding: [], day: 20_001)?.spotId)
    }

    func testCoverSpotDetailsAreLoaded() throws {
        // 入口の札の写真は分けた置き場の詳細から（索引だけの行のままだと写真が出ない）
        var indexOnly = try JSONDecoder.api.decode(OfficialSpot.self, from: Data("""
        {"spotId":"x","slug":"x","name":"[x]","stage":"published","hasImage":true}
        """.utf8))
        indexOnly.isIndexOnly = true
        XCTAssertTrue(TripPicker.isEligible(indexOnly), "索引だけの行も写真ありなら入口の写真の候補")
        let needs = SpotDetailNeeds.home(choices: [.swipe(cover: indexOnly)], shelf: nil, spots: [indexOnly])
        XCTAssertEqual(needs.map(\.spotId), ["x"])
    }

    func testHomeViewPutsSwipeFirstAndOpensFullScreen() throws {
        let view = try source("Features/Gallery/HomeTopCardView.swift")
        XCTAssertTrue(view.contains("HomeTopCard.withSwipe("), "ホームの札の並びに入口を入れる")
        XCTAssertTrue(view.contains("SpotSwipeView()"), "押すと全画面の払う画面")
        XCTAssertTrue(view.contains(".fullScreenCover(isPresented: $showSwipe"))
    }

    // MARK: - 3. 入口の一行

    func testCardLineSaysContinueFromSecondTime() {
        XCTAssertEqual(SpotSwipe.cardLine(started: true, wishCount: 3, signedIn: false), "行きたい 3 か所 · 続きから")
        XCTAssertEqual(SpotSwipe.cardLine(started: false, wishCount: 0, signedIn: false), "ログインなしではじめる")
        XCTAssertEqual(SpotSwipe.cardLine(started: false, wishCount: 0, signedIn: true), "右へ払うと行きたい")
        // 札の題・一行は1行（#417 ③）。札の字の幅に収まる長さに抑える
        XCTAssertLessThanOrEqual(SpotSwipe.cardTitle.count, 10)
        XCTAssertLessThanOrEqual(SpotSwipe.cardLine(started: true, wishCount: 40, signedIn: false).count, 17)
    }

    func testPauseWordsSayWhatYouSee() {
        XCTAssertEqual(SpotSwipe.pauseTitle(wants: 3), "選んだ 3 か所を、地図と旅行プランで")
        XCTAssertEqual(SpotSwipe.actionTitle(signedIn: false), "ログインして見る")
        XCTAssertEqual(SpotSwipe.actionTitle(signedIn: true), "旅行プランにする")
        XCTAssertEqual(SpotSwipe.footerAction(signedIn: false), "地図で見る")
        XCTAssertEqual(SpotSwipe.footerCount(2), "行きたい 2 か所")
    }

    // MARK: - 4. 続き

    func testProgressRemembersStartedAndSeen() {
        let defaults = freshDefaults()
        let progress = SpotSwipeProgress(defaults: defaults)
        XCTAssertFalse(progress.started)
        progress.markStarted()
        XCTAssertTrue(SpotSwipeProgress(defaults: defaults).started)

        progress.addSeen(["SPOT-a", "SPOT-b"])
        progress.addSeen(["SPOT-a"])
        XCTAssertEqual(progress.seen, ["SPOT-a", "SPOT-b"])
        progress.removeSeen("SPOT-b")
        XCTAssertEqual(progress.seen, ["SPOT-a"])
        progress.resetSeen()
        XCTAssertTrue(progress.seen.isEmpty)
    }

    func testProgressKeepsOnlyTheNewest() {
        let progress = SpotSwipeProgress(defaults: freshDefaults())
        progress.addSeen((0..<(SpotSwipeProgress.limit + 5)).map { "SPOT-\($0)" })
        XCTAssertEqual(progress.seen.count, SpotSwipeProgress.limit)
        XCTAssertFalse(progress.seen.contains("SPOT-0"), "古いものから消える")
    }

    @MainActor
    func testDeckSkipsSeenAndRestartsWhenAllSeen() async throws {
        let spots = try ["a", "b"].map { try spot($0) }
        let model = TripPickerModel()
        await model.load(fetch: { spots }, excluding: [SavedSpotKey.official("a")], seed: 1,
                         fallbackExcluding: [])
        XCTAssertEqual(model.deck.map(\.slug), ["b"], "前に払った札は出さない")
        XCTAssertFalse(model.restarted)

        let all = TripPickerModel()
        await all.load(fetch: { spots }, excluding: Set(["a", "b"].map { SavedSpotKey.official($0) }), seed: 1,
                       fallbackExcluding: [SavedSpotKey.official("b")])
        XCTAssertEqual(all.deck.map(\.slug), ["a"], "全部見たら「行きたい」だけ除いて最初から")
        XCTAssertTrue(all.restarted)
    }

    // MARK: - 5. 未ログイン・ログイン

    func testSwipeScreenDoesNotGateOnSignIn() throws {
        let view = try source("Features/Trips/SpotSwipeView.swift")
        XCTAssertFalse(view.contains("SignInView("), "払う画面はログインの画面で止めない（未ログインでも払える）")
        XCTAssertTrue(view.contains("SignInSheet(reason:"), "ログインはシートで出し、閉じたら払う画面に戻る")
        XCTAssertTrue(view.contains("TripPickerView(model: model, alsoExclude: baseSeen, pause: pause,"),
                      "中身は旅行プランの作る流れと同じ札の山")
        XCTAssertTrue(view.contains("TripCreateView(plans: plans, initial: initial"),
                      "ログイン中は今の旅行プランにする流れ")
        // 旅行プランの一覧の作る口は残す（入口を移したのではなく足した）
        let plans = try source("Features/Trips/TripPlansView.swift")
        XCTAssertTrue(plans.contains("TripCreateView(plans: model)"))
    }
}
