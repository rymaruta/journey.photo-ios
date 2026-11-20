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

    // MARK: - 案 A（札 #510・2026-11-10）: 押すたびに 1 回足す

    /// 🔴 押す＝1 回足し、帯を出す（札は開かない・「取り消す」の帯は作らない）
    func testTapAddsOneAndShowsQuickBar() async {
        let m = model()
        m.open(userId: "u")
        m.tap("東京都")
        XCTAssertEqual(m.record.count("東京都"), 1)
        XCTAssertEqual(m.record.days("東京都"), ["2026-11-08"])
        XCTAssertNil(m.selected, "押しても札は開かない")
        XCTAssertEqual(m.quickBar?.prefecture, "東京都")
        XCTAssertNil(m.toast, "帯の［−］が取り消しを兼ねる（下に重ねない）")
        XCTAssertEqual(m.lightTick, 1)
        XCTAssertEqual(m.addPulse, 1)
        XCTAssertEqual(m.addPulsePrefecture, "東京都")
        XCTAssertEqual(m.announcement, "東京都、1 回、1 回足しました")
    }

    /// 🔴 owner 2026-11-10「2回押したら2回カウントされる」: 同じ県を同じ日に 2 回押したら 2 回。確かめは出さない。
    /// 続けて押しても取りこぼさず、二重にもならない（押した数だけ）
    func testTwoTapsOnTheSameDayCountTwice() async {
        let m = model()
        m.open(userId: "u")
        m.tap("京都府")
        m.tap("京都府")
        XCTAssertEqual(m.record.count("京都府"), 2)
        XCTAssertEqual(m.record.days("京都府"), ["2026-11-08", "2026-11-08"])
        for _ in 0..<5 { m.tap("京都府") }
        XCTAssertEqual(m.record.count("京都府"), 7, "続けて押した数だけ足す")
        XCTAssertEqual(m.quickBar?.prefecture, "京都府")
        XCTAssertEqual(m.announcement, "京都府、7 回、1 回足しました")
        // 札の ＋ も同じ日に確かめずに足す
        m.add("京都府")
        XCTAssertEqual(m.record.count("京都府"), 8)
    }

    /// 🔴 長押し＝足さずに帯だけ。帯の［−］で 1 回減らせる（帯が消えたあとでも、長押し → ［−］）
    func testLongPressShowsBarWithoutAddingAndMinusRemovesOne() async {
        let m = model()
        m.open(userId: "u")
        m.tap("長野県")
        m.tap("長野県")
        m.tap("長野県")
        m.dismissQuickBar()
        let ticks = m.lightTick
        m.peek("長野県")
        XCTAssertEqual(m.record.count("長野県"), 3, "長押しでは足さない")
        XCTAssertEqual(m.quickBar?.prefecture, "長野県")
        XCTAssertEqual(m.lightTick, ticks, "長押しは記録を変えない")
        XCTAssertEqual(m.announcement, "長野県、3 回")
        m.quickRemove()
        XCTAssertEqual(m.record.count("長野県"), 2, "［−］1 回で 1 回減る（確かめは出さない）")
        XCTAssertNil(m.toast)
        XCTAssertEqual(m.announcement, "長野県、2 回、1 回減らしました")
        m.quickRemove()
        m.quickRemove()
        XCTAssertEqual(m.record.count("長野県"), 0, "0 回で塗りが消える")
        XCTAssertEqual(m.record.visitedCount, 0)
        XCTAssertEqual(m.announcement, "長野県、未、1 回減らしました")
        // 0 からは減らない（［−］は押せない見た目）
        m.quickRemove()
        XCTAssertEqual(m.record.count("長野県"), 0)
        // ［＋］で戻せる
        m.quickAdd()
        XCTAssertEqual(m.record.count("長野県"), 1)
        XCTAssertEqual(m.quickBar?.prefecture, "長野県")
        XCTAssertEqual(m.announcement, "長野県、1 回、1 回足しました")
    }

    /// 帯は別の県を押したらその県に替わる。［詳しく］で札を開き、帯は閉じる
    func testQuickBarFollowsTheLastPrefectureAndDetailsOpensCard() async {
        let m = model()
        m.open(userId: "u")
        m.tap("東京都")
        m.tap("千葉県")
        XCTAssertEqual(m.quickBar?.prefecture, "千葉県")
        m.quickAdd()
        XCTAssertEqual(m.record.count("千葉県"), 2)
        XCTAssertEqual(m.record.count("東京都"), 1, "前の県には足さない")
        m.openCard("千葉県")
        XCTAssertEqual(m.selected, "千葉県")
        XCTAssertNil(m.quickBar)
    }

    /// 🔴 帯は 5 秒で消える。触っている間は消さず、離したら 5 秒を数え直す
    func testQuickBarExpiresButNotWhileHeld() async {
        XCTAssertEqual(VisitedMapModel.quickBarDefaultSeconds, 5, "帯は 5 秒（モック A・取り消すと同じ）")
        let m = model()
        m.open(userId: "u")
        XCTAssertEqual(m.quickBarSeconds, 5)
        m.tap("東京都")
        guard let first = m.quickBar?.timerID else { return XCTFail("帯が出ていない") }
        XCTAssertNotNil(m.quickBar?.deadline, "残りの線が読む消える時刻が無い")
        XCTAssertEqual(m.quickBar?.seconds, 5)
        // 触っている間は、時間が来ても消さない（残りの線は満ちたまま）
        m.setQuickBarHeld(true)
        XCTAssertNil(m.quickBar?.deadline)
        m.expireQuickBar(first)
        XCTAssertNotNil(m.quickBar, "触っている間に消えた")
        // 離したら数え直す（古い時間切れは効かない・新しい時間切れで消える）
        m.setQuickBarHeld(false)
        guard let second = m.quickBar?.timerID else { return XCTFail("離したら帯が消えた") }
        XCTAssertNotEqual(first, second)
        m.expireQuickBar(first)
        XCTAssertNotNil(m.quickBar, "古い時間切れで消えた")
        m.expireQuickBar(second)
        XCTAssertNil(m.quickBar)
        // ［＋］［−］も数え直す
        m.tap("東京都")
        let before = m.quickBar?.timerID
        m.quickAdd()
        XCTAssertNotEqual(m.quickBar?.timerID, before)
    }

    /// 帯は本当に時間で消える（秒数を短くして待つ）
    func testQuickBarDisappearsAfterItsSeconds() async throws {
        let m = model()
        m.open(userId: "u")
        m.quickBarSeconds = 0.05
        m.tap("東京都")
        XCTAssertNotNil(m.quickBar)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNil(m.quickBar, "時間が来ても帯が残っている")
        m.setQuickBarHeld(true)
        m.tap("東京都")
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNotNil(m.quickBar, "触っている間に消えた")
    }

    /// 読み上げの操作「1 回減らす」: 帯が無くても、その県を 1 回減らして帯を出す
    func testDecreaseFromAccessibilityActionShowsBar() async {
        let m = model()
        m.open(userId: "u")
        m.tap("沖縄県")
        m.tap("沖縄県")
        m.dismissQuickBar()
        m.decrease("沖縄県")
        XCTAssertEqual(m.record.count("沖縄県"), 1)
        XCTAssertEqual(m.quickBar?.prefecture, "沖縄県")
        m.decrease("パリ")
        XCTAssertEqual(m.quickBar?.prefecture, "沖縄県", "知らない県は無視する")
    }

    /// 帯がある間は「取り消す」の帯を作らない。帯の県と関係の無い一手を戻したら帯は閉じる
    func testQuickBarAndUndoToastDoNotOverlap() async {
        let m = model()
        m.open(userId: "u")
        m.add("北海道")
        XCTAssertNotNil(m.toast, "札の ＋ は「取り消す」を出す")
        m.tap("東京都")
        XCTAssertNil(m.toast, "帯を出したら「取り消す」は下げる")
        m.undo()
        XCTAssertEqual(m.record.count("東京都"), 0)
        XCTAssertEqual(m.quickBar?.prefecture, "東京都", "帯の県の一手を戻しても帯は残る（数が 0 に戻る）")
        m.undo()
        XCTAssertEqual(m.record.count("北海道"), 0)
        XCTAssertNil(m.quickBar, "帯の県と関係の無い一手を戻したら帯は閉じる")
    }

    /// 写真の候補の県も、押したら 1 回足す（候補から消える）
    func testTappingACandidateAddsOne() async throws {
        let m = model()
        m.open(userId: "u")
        m.applyPhotos([try photo("a", location: "長野県")], spots: [])
        XCTAssertEqual(m.candidates, ["長野県"])
        m.tap("長野県")
        XCTAssertEqual(m.record.count("長野県"), 1)
        XCTAssertTrue(m.candidates.isEmpty)
    }

    /// 🔴 レビュー 2026-11-10 の 1: 外した候補の県を地図で押して［−］で戻しても、外した印は残る（黙って候補に戻らない）。
    /// 札の「記録する」で決めて足したときは今までどおり戻す
    func testQuickAddKeepsADismissedCandidateDismissed() async throws {
        let m = model()
        m.open(userId: "u")
        m.applyPhotos([try photo("a", location: "長野県")], spots: [])
        m.dismissCandidate("長野県")
        XCTAssertTrue(m.candidates.isEmpty)
        m.tap("長野県")
        XCTAssertEqual(m.record.count("長野県"), 1)
        m.quickRemove()
        XCTAssertEqual(m.record.count("長野県"), 0)
        XCTAssertTrue(m.record.dismissed.contains("長野県"), "押して［−］で戻したら外した印が消えた")
        XCTAssertTrue(m.candidates.isEmpty, "外した候補がまた出た")
        // 札の「記録する」は今までどおり外した印を戻す
        m.add("長野県")
        XCTAssertFalse(m.record.dismissed.contains("長野県"))
    }

    /// 🔴 レビュー 2026-11-10 の 2: 帯を押さえたまま祝いの札が出ても「触っている」を残さない（帯が消えなくなる）
    func testCelebrationReleasesAHeldQuickBar() async {
        let m = model()
        m.open(userId: "u")
        for name in RegionList.prefectures.dropLast() { m.add(name) }
        m.peek("沖縄県")
        m.setQuickBarHeld(true)
        XCTAssertNil(m.quickBar?.deadline)
        m.quickAdd()
        XCTAssertEqual(m.celebration, .allVisited)
        XCTAssertFalse(m.quickBarHeld, "祝いのあとも触っていることになっている")
        XCTAssertNotNil(m.quickBar?.deadline, "帯が消える時刻を数え直していない")
    }

    /// 🔴 レビュー 2026-11-10 の 4: 地図の指の判定（`VisitedMapTouch.onRelease`）をモデルに渡したとき、
    /// 長押しでは足さず、短く押したときだけ 1 回足す。動かした・ピンチした指は何もしない
    func testMapReleaseAddsOnlyOnAShortPress() async {
        let m = model()
        m.open(userId: "u")
        // 長押しで帯を出し終えた指を離す
        m.release(VisitedMapTouch.onRelease(moved: false, pinched: false, longPressFired: true, heldSeconds: 0.6),
                  on: "東京都")
        XCTAssertEqual(m.record.count("東京都"), 0)
        // 0.5 秒押してから、合図の前に離した
        m.release(VisitedMapTouch.onRelease(moved: false, pinched: false, longPressFired: false, heldSeconds: 0.6),
                  on: "東京都")
        XCTAssertEqual(m.record.count("東京都"), 0, "長押しで足した")
        XCTAssertEqual(m.quickBar?.prefecture, "東京都", "長押しで帯が出ていない")
        // 動かした・ピンチした
        m.release(VisitedMapTouch.onRelease(moved: true, pinched: false, longPressFired: false, heldSeconds: 0.1),
                  on: "東京都")
        m.release(VisitedMapTouch.onRelease(moved: false, pinched: true, longPressFired: false, heldSeconds: 0.1),
                  on: "東京都")
        XCTAssertEqual(m.record.count("東京都"), 0, "動かした・ピンチした指で足した")
        // 短く 2 回押す → 2 回
        m.release(VisitedMapTouch.onRelease(moved: false, pinched: false, longPressFired: false, heldSeconds: 0.1),
                  on: "東京都")
        m.release(VisitedMapTouch.onRelease(moved: false, pinched: false, longPressFired: false, heldSeconds: 0.05),
                  on: "東京都")
        XCTAssertEqual(m.record.count("東京都"), 2)
        // 押し始めが分からないまま離した（指の途中状態が片付いたあと）では足さない（再確認 2026-11-10 の 2）
        m.release(VisitedMapTouch.onRelease(moved: false, pinched: false, longPressFired: false, heldSeconds: nil),
                  on: "東京都")
        XCTAssertEqual(m.record.count("東京都"), 2)
    }

    /// 上限（99）で帯の［＋］を押しても足さず、警告の触覚（帯があるので「取り消す」の帯は作らない）
    func testQuickAddAtLimitWarns() async {
        let m = model()
        m.open(userId: "u")
        for _ in 0..<VisitedPrefectures.maxCount { m.tap("沖縄県") }
        XCTAssertEqual(m.record.count("沖縄県"), VisitedPrefectures.maxCount)
        m.quickAdd()
        XCTAssertEqual(m.record.count("沖縄県"), VisitedPrefectures.maxCount)
        XCTAssertEqual(m.warningTick, 1)
        XCTAssertNil(m.toast)
        XCTAssertEqual(m.announcement, VisitedMapText.limitReached("沖縄県"))
    }

    func testUndoAndMinusAndPersistence() async {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        let m = model(defaults: d)
        m.open(userId: "u")
        m.add("北海道")
        m.add("北海道")
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
        m.add("東京都")
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
        m.tap("パリ")
        m.peek("パリ")
        XCTAssertNil(m.selected)
        XCTAssertNil(m.quickBar)
        XCTAssertEqual(m.record.visitedCount, 0)
    }

    /// 99 回で足せないときは、黙らず一言と警告の触覚（「取り消す」は添えない）
    func testLimitReachedGivesNoticeAndWarning() async {
        let m = model()
        m.open(userId: "u")
        for _ in 0..<VisitedPrefectures.maxCount { m.add("沖縄県") }
        XCTAssertEqual(m.warningTick, 0)
        m.add("沖縄県")
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

    /// 2026-11-10 判断（札 #510）: 押せば同じ日に 2 回入るので、日付もほかの記録と同じ日に直せる
    func testChangeDayAllowsTheSameDayAsAnotherVisit() async {
        let m = model()
        m.open(userId: "u")
        m.add("京都府")
        m.add("京都府")
        XCTAssertEqual(m.record.days("京都府"), ["2026-11-08", "2026-11-08"])
        m.changeDay("京都府", at: 0, to: "2026-10-01")
        XCTAssertEqual(m.record.days("京都府"), ["2026-10-01", "2026-11-08"])
        m.changeDay("京都府", at: 0, to: "2026-11-08")
        XCTAssertEqual(m.record.days("京都府"), ["2026-11-08", "2026-11-08"], "ほかの記録と同じ日に直せない")
        XCTAssertTrue(m.canUndo)
    }
}
