import XCTest
@testable import JourneyPhoto

/// 行った県マップの画面の状態（札 #503）。タップ・確かめ・取り消し・祝いが記録に結ばれていること。
@MainActor
final class VisitedMapModelTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private func model(day: Int = 8, defaults: UserDefaults? = nil) -> VisitedMapModel {
        let calendar = cal
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 12))!
        let d = defaults ?? UserDefaults(suiteName: UUID().uuidString)!
        return VisitedMapModel(store: VisitedPrefectureStore(defaults: d), now: { date }, calendar: calendar)
    }

    private func photo(_ id: String, location: String) throws -> Photo {
        try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\",\"location\":\"\(location)\"}".utf8))
    }

    /// スイッチがオフ（既定）のときは、タップは札を開くだけで回数は増えない
    func testTapOpensCardWhenSwitchIsOff() async {
        let m = model()
        m.open(userId: "u")
        XCTAssertFalse(m.addsOnTap)
        m.tap("東京都")
        XCTAssertEqual(m.selected, "東京都")
        XCTAssertEqual(m.record.count("東京都"), 0)
    }

    func testTapAddsWhenSwitchIsOn() async {
        let m = model()
        m.open(userId: "u")
        m.addsOnTap = true
        m.tap("東京都")
        XCTAssertEqual(m.record.count("東京都"), 1)
        XCTAssertNil(m.selected)
        XCTAssertEqual(m.record.days("東京都"), ["2026-11-08"])
        XCTAssertNotNil(m.toast)
        XCTAssertEqual(m.lightTick, 1)
    }

    /// 同じ県を同じ日にもう一度足すときは、確かめてから
    func testSameDayAsksBeforeAdding() async {
        let m = model()
        m.open(userId: "u")
        m.add("京都府")
        m.add("京都府")
        XCTAssertEqual(m.pendingSameDay, "京都府")
        XCTAssertEqual(m.record.count("京都府"), 1, "確かめるまでは足さない")
        m.cancelSameDay()
        XCTAssertNil(m.pendingSameDay)
        XCTAssertEqual(m.record.count("京都府"), 1)
        m.add("京都府")
        m.confirmSameDay()
        XCTAssertEqual(m.record.count("京都府"), 2)
        XCTAssertNil(m.pendingSameDay)
    }

    func testUndoAndMinusAndPersistence() async {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        let m = model(defaults: d)
        m.open(userId: "u")
        m.add("北海道")
        m.add("北海道", confirmingSameDay: false)
        XCTAssertEqual(m.record.count("北海道"), 2)
        m.undo()
        XCTAssertEqual(m.record.count("北海道"), 1)
        XCTAssertNil(m.toast)
        m.remove("北海道")
        XCTAssertEqual(m.record.count("北海道"), 0)
        XCTAssertEqual(m.record.visitedCount, 0)
        m.undo()
        XCTAssertEqual(m.record.count("北海道"), 1)
        // 端末に残っている（別のモデルで開き直しても同じ）
        let again = model(defaults: d)
        again.open(userId: "u")
        XCTAssertEqual(again.record.count("北海道"), 1)
        XCTAssertEqual(model(defaults: d).record.visitedCount, 0, "開く前は空")
        let other = model(defaults: d)
        other.open(userId: "someone-else")
        XCTAssertEqual(other.record.visitedCount, 0, "別の人の記録は見えない")
    }

    /// 写真から導いた県は候補で、数にも色にも入らない。記録にするのは本人のタップ
    func testPhotoCandidatesAreNotRecorded() async throws {
        let m = model()
        m.open(userId: "u")
        m.applyPhotos([try photo("a", location: "長野県"), try photo("b", location: "京都市")], spots: [])
        XCTAssertEqual(m.found, ["長野県", "京都府"])
        XCTAssertEqual(m.candidates, ["長野県", "京都府"])
        XCTAssertEqual(m.record.visitedCount, 0)
        XCTAssertEqual(m.photosState, .loaded)
        m.dismissCandidate("長野県")
        XCTAssertEqual(m.candidates, ["京都府"])
        m.add("京都府")
        XCTAssertTrue(m.candidates.isEmpty, "記録にした県は候補から消える")
        XCTAssertEqual(m.breakdown.fromPhotos, 2)
        XCTAssertEqual(m.breakdown.byHand, 0)
    }

    func testPhotoFailureKeepsRecord() async {
        let m = model()
        m.open(userId: "u")
        m.add("沖縄県")
        m.failPhotos()
        XCTAssertEqual(m.photosState, .failed)
        XCTAssertEqual(m.record.count("沖縄県"), 1)
    }

    // MARK: - 祝い

    func testCelebrationOnlyWhenTheRoundCompletesNotOnFirstOpen() async {
        let m = model()
        m.open(userId: "u")
        for name in RegionList.prefectures.dropLast() { m.add(name) }
        XCTAssertNil(m.celebration)
        XCTAssertEqual(m.successTick, 0)
        m.add("沖縄県")
        XCTAssertEqual(m.celebration, .allVisited)
        XCTAssertEqual(m.successTick, 1)
        m.dismissCelebration()
        XCTAssertNil(m.celebration)
    }

    func testNoCelebrationForSomeoneWhoAlreadyHas47() async {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        var book = VisitedPrefectures()
        for name in RegionList.prefectures { book.add(name, day: "2026-01-01") }
        VisitedPrefectureStore(defaults: d).save(book, for: "u")
        let m = model(defaults: d)
        m.open(userId: "u")
        XCTAssertNil(m.celebration)
        m.addsOnTap = true
        m.tap("東京都")
        XCTAssertNil(m.celebration, "すでにそろっていた人には、足しても祝わない")
        XCTAssertEqual(m.successTick, 0)
    }

    func testBulkRecordDoesNotCelebrateAndCanBeUndone() async {
        let m = model()
        m.open(userId: "u")
        m.markAllVisited()
        XCTAssertEqual(m.record.visitedCount, 47)
        XCTAssertNil(m.celebration)
        m.undo()
        XCTAssertEqual(m.record.visitedCount, 0)
        m.markAllVisited()
        m.add("東京都", confirmingSameDay: false)
        XCTAssertNil(m.celebration, "一括のあとは、そろった周を見せたことになっている")
    }

    func testClearAllCanBeUndone() async {
        let m = model()
        m.open(userId: "u")
        m.markAllVisited()
        m.clearAll()
        XCTAssertEqual(m.record.visitedCount, 0)
        m.undo()
        XCTAssertEqual(m.record.visitedCount, 47)
    }

    func testAnnouncementAfterChange() async {
        let m = model()
        m.open(userId: "u")
        m.add("東京都")
        XCTAssertEqual(m.announcement, "東京都、1 回。行った県 1")
    }

    func testUnknownPrefectureIsIgnored() async {
        let m = model()
        m.open(userId: "u")
        m.addsOnTap = true
        m.tap("パリ")
        XCTAssertNil(m.selected)
        XCTAssertEqual(m.record.visitedCount, 0)
    }

    /// 99 回で足せないときは、黙らず一言と警告の触覚（「取り消す」は添えない）
    func testLimitReachedGivesNoticeAndWarning() async {
        let m = model()
        m.open(userId: "u")
        for _ in 0..<VisitedPrefectures.maxCount { m.add("沖縄県", confirmingSameDay: false) }
        XCTAssertEqual(m.warningTick, 0)
        m.add("沖縄県", confirmingSameDay: false)
        XCTAssertEqual(m.warningTick, 1)
        XCTAssertEqual(m.record.count("沖縄県"), VisitedPrefectures.maxCount)
        XCTAssertEqual(m.toast?.message, VisitedMapText.limitReached("沖縄県"))
        XCTAssertEqual(m.toast?.offersUndo, false)
    }

    /// 周がそろったときは成功の触覚だけ（軽い触覚と重ねない）・祝いを読み上げにも出す
    func testCelebrationHapticIsSuccessOnlyAndAnnounced() async {
        let m = model()
        m.open(userId: "u")
        for name in RegionList.prefectures.dropLast() { m.add(name) }
        let lightBefore = m.lightTick
        m.add("沖縄県")
        XCTAssertEqual(m.successTick, 1)
        XCTAssertEqual(m.lightTick, lightBefore, "祝いのときは軽い触覚を鳴らさない")
        XCTAssertTrue(m.announcement?.contains(VisitedMapText.celebrationTitle(.allVisited)) == true)
    }

    func testNormalChangeOffersUndoAndLightHaptic() async {
        let m = model()
        m.open(userId: "u")
        m.add("東京都")
        XCTAssertEqual(m.toast?.offersUndo, true)
        XCTAssertEqual(m.lightTick, 1)
        XCTAssertEqual(m.successTick, 0)
    }

    func testChangeDayRejectsDuplicates() async {
        let m = model()
        m.open(userId: "u")
        m.add("京都府")
        m.add("京都府", confirmingSameDay: false)
        m.changeDay("京都府", at: 0, to: "2026-11-08")
        XCTAssertEqual(m.record.days("京都府"), ["2026-11-08", "2026-11-08"], "同じ日の2回目は足すで記録済み。直して重ねない")
        m.changeDay("京都府", at: 0, to: "2026-10-01")
        XCTAssertEqual(m.record.days("京都府"), ["2026-10-01", "2026-11-08"])
        m.changeDay("京都府", at: 0, to: "2026-11-08")
        XCTAssertEqual(m.record.days("京都府"), ["2026-10-01", "2026-11-08"], "ほかの記録と同じ日には直せない")
    }
}
