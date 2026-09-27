import XCTest
@testable import JourneyPhoto

/// 送っていない変更がある画面の「戻る」（`UnsavedLeave`）。
/// 親しい友達と旅行プランの日程が同じ判断を使う。
final class UnsavedLeaveTests: XCTestCase {

    /// 🔴 **送っていない変更があるまま黙って戻らせない。** 送っている最中は戻らせない
    func testLeavingAsksWhenThereAreUnsavedChanges() {
        XCTAssertEqual(UnsavedLeave.decide(hasChanges: false, isSaving: false), .now)
        XCTAssertEqual(UnsavedLeave.decide(hasChanges: true, isSaving: false), .confirm)
        XCTAssertEqual(UnsavedLeave.decide(hasChanges: true, isSaving: true), .wait)
        XCTAssertEqual(UnsavedLeave.decide(hasChanges: false, isSaving: true), .wait)
    }

    /// 🔴 **旅行プランの日程: 日を足しただけでも「変えた」になり、戻ると確かめる。**
    /// 以前は戻るで下書きが黙って消えた（保存は右上のボタンだけ）
    func testTripPlanDayEditAsksBeforeLeaving() {
        let plan = TripPlan(planId: "p1", title: "京都", days: [TripDay()])
        var days = plan.days
        XCTAssertEqual(TripPlanText.leave(plan: plan, days: days, start: nil, end: nil, busy: false), .now)
        days.append(TripDay())
        XCTAssertEqual(TripPlanText.leave(plan: plan, days: days, start: nil, end: nil, busy: false), .confirm)
        // 保存を送っている間は戻らせない（返事が来る前に離れると失敗が見えない）
        XCTAssertEqual(TripPlanText.leave(plan: plan, days: days, start: nil, end: nil, busy: true), .wait)
        // 日付だけ変えても同じ
        XCTAssertEqual(TripPlanText.leave(plan: plan, days: plan.days, start: "2026-10-01", end: nil, busy: false), .confirm)
        // 何も変えていなければ、削除などの最中でも閉じ込めない
        XCTAssertEqual(TripPlanText.leave(plan: plan, days: plan.days, start: nil, end: nil, busy: true), .now,
                       "変えていないのに戻れない")
    }

    /// プランが消えた（別の端末で消された）画面は、そのまま戻れる
    func testMissingPlanLeavesAtOnce() {
        XCTAssertEqual(TripPlanText.leave(plan: nil, days: [TripDay()], start: nil, end: nil, busy: false), .now)
    }
}
