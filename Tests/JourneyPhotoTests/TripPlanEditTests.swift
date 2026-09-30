import XCTest
@testable import JourneyPhoto

/// 旅行プランの並べ替え・別の日へ移す・ひとこと（`TripPlanEdit`・2026-09-30）。
///
/// 見張るのは: **順番が変わる**・**別の日へ移る**・**断るときは何も変えない**
/// （範囲外・移す先がいっぱい）・**ひとことは空白を落とし、空なら外し、UTF-16 で200まで**。
final class TripPlanEditTests: XCTestCase {

    private func s(_ id: String) -> TripItem { .spot(spotId: id, note: nil) }
    private func ids(_ day: TripDay) -> [String] {
        day.items.map { item in
            switch item {
            case .spot(let id, _): return id
            case .location(let slug, _): return slug
            }
        }
    }
    private var sample: [TripDay] {
        [TripDay(items: [s("a"), s("b"), s("c")]), TripDay(items: [s("d")])]
    }

    // MARK: - 同じ日の中

    func testMoveUpAndDownSwapNeighbours() throws {
        let up = try XCTUnwrap(TripPlanEdit.moveUp(sample, day: 0, item: 2))
        XCTAssertEqual(ids(up[0]), ["a", "c", "b"])
        let down = try XCTUnwrap(TripPlanEdit.moveDown(sample, day: 0, item: 0))
        XCTAssertEqual(ids(down[0]), ["b", "a", "c"])
        // ほかの日は触らない
        XCTAssertEqual(ids(up[1]), ["d"])
    }

    func testMoveUpAtTopAndDownAtBottomRefuse() {
        XCTAssertNil(TripPlanEdit.moveUp(sample, day: 0, item: 0))
        XCTAssertNil(TripPlanEdit.moveDown(sample, day: 0, item: 2))
        XCTAssertNil(TripPlanEdit.moveDown(sample, day: 1, item: 0))
    }

    // MARK: - 別の日へ

    func testMoveToAnotherDayAppendsAtTheEnd() throws {
        let moved = try XCTUnwrap(TripPlanEdit.moveToDay(sample, day: 0, item: 1, toDay: 1))
        XCTAssertEqual(ids(moved[0]), ["a", "c"])
        XCTAssertEqual(ids(moved[1]), ["d", "b"])
    }

    func testMoveToSameDayOrMissingDayRefuses() {
        XCTAssertNil(TripPlanEdit.moveToDay(sample, day: 0, item: 1, toDay: 0))
        XCTAssertNil(TripPlanEdit.moveToDay(sample, day: 0, item: 1, toDay: 5))
        XCTAssertNil(TripPlanEdit.moveToDay(sample, day: 0, item: 9, toDay: 1))
        XCTAssertNil(TripPlanEdit.moveToDay(sample, day: 7, item: 0, toDay: 1))
    }

    /// 移す先がいっぱい（サーバーの上限）なら移さない。**移す元からも消さない**
    func testMoveIntoAFullDayRefusesAndKeepsTheItem() {
        let full = TripDay(items: (0..<TripPlanService.itemsPerDayMax).map { s("f\($0)") })
        let days = [TripDay(items: [s("x")]), full]
        XCTAssertNil(TripPlanEdit.moveToDay(days, day: 0, item: 0, toDay: 1))
        XCTAssertEqual(TripPlanEdit.movableDays(days, from: 0), [])
    }

    /// 同じ日の中の並べ替えは、いっぱいの日でもできる（数は変わらない）
    func testReorderInsideAFullDayIsAllowed() throws {
        let full = TripDay(items: (0..<TripPlanService.itemsPerDayMax).map { s("f\($0)") })
        let moved = try XCTUnwrap(TripPlanEdit.moveUp([full], day: 0, item: 1))
        XCTAssertEqual(Array(ids(moved[0]).prefix(2)), ["f1", "f0"])
    }

    func testMovableDaysExcludesTheSourceDay() {
        let days = [TripDay(), TripDay(), TripDay()]
        XCTAssertEqual(TripPlanEdit.movableDays(days, from: 1), [0, 2])
    }

    // MARK: - ひとこと

    func testSetNoteTrimsAndKeepsTheKind() throws {
        let days = [TripDay(items: [.location(slug: "金沢", note: nil)])]
        let out = try XCTUnwrap(TripPlanEdit.setNote(days, day: 0, item: 0, note: "  朝いちばんに  \n"))
        XCTAssertEqual(out[0].items[0], .location(slug: "金沢", note: "朝いちばんに"))
    }

    func testEmptyNoteRemovesIt() throws {
        let days = [TripDay(items: [.spot(spotId: "sp_1", note: "前のメモ")])]
        let out = try XCTUnwrap(TripPlanEdit.setNote(days, day: 0, item: 0, note: "   "))
        XCTAssertEqual(out[0].items[0], .spot(spotId: "sp_1", note: nil))
        XCTAssertNil(out[0].items[0].note)
    }

    /// サーバーと同じく UTF-16 の単位で200まで。**絵文字（2単位）の途中では切らない**
    func testNoteIsClampedToTheServerLimitInUTF16() throws {
        let days = [TripDay(items: [s("a")])]
        let long = String(repeating: "😀", count: 150)   // 300 単位
        let out = try XCTUnwrap(TripPlanEdit.setNote(days, day: 0, item: 0, note: long))
        let note = try XCTUnwrap(out[0].items[0].note)
        XCTAssertEqual(note.utf16.count, TripPlanService.noteMax)
        XCTAssertEqual(note, String(repeating: "😀", count: 100))
    }

    func testSetNoteOnMissingItemRefuses() {
        XCTAssertNil(TripPlanEdit.setNote(sample, day: 0, item: 9, note: "x"))
    }

    /// 送る形にひとことが載る（サーバーが受ける `note`）
    func testNoteIsEncoded() throws {
        let days = try XCTUnwrap(TripPlanEdit.setNote(sample, day: 0, item: 0, note: "朝"))
        let json = String(decoding: try JSONEncoder().encode(days[0]), as: UTF8.self)
        XCTAssertTrue(json.contains(#""note":"朝""#), json)
    }

    // MARK: - 保存の対象になる

    /// 並べ替えもひとことも「変えた」扱い（保存ボタンが点き、戻るときに確かめる）
    func testReorderAndNoteMakeThePlanDirty() throws {
        let plan = TripPlan(planId: "p", title: "t", days: sample)
        XCTAssertFalse(TripPlanText.isDirty(plan: plan, days: sample, start: nil, end: nil))
        let moved = try XCTUnwrap(TripPlanEdit.moveDown(sample, day: 0, item: 0))
        XCTAssertTrue(TripPlanText.isDirty(plan: plan, days: moved, start: nil, end: nil))
        let noted = try XCTUnwrap(TripPlanEdit.setNote(sample, day: 1, item: 0, note: "夕方"))
        XCTAssertTrue(TripPlanText.isDirty(plan: plan, days: noted, start: nil, end: nil))
    }
}
