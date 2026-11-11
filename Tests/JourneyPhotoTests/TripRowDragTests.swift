import XCTest
@testable import JourneyPhoto

/// 行を運ぶ元（`TripRowDrag.swift`・2026-11-11 判断）。運ぶ操作が落とさずに終わっても、落とす先の線を残さない
/// （Mac run 1036: `.draggable` では速く運んだ 8 回中 1 回、離して 5 秒後も線が 1 本残った）
final class TripRowDragTests: XCTestCase {

    private struct Spot: Equatable { let day: Int; let item: Int? }

    func testTargetedSetsAndUntargetedClearsOnlyThatSpot() {
        var mark = TripDropMark<Spot>()
        mark.targeted(true, Spot(day: 1, item: 0))
        XCTAssertEqual(mark.spot, Spot(day: 1, item: 0))
        // 次の先に入った知らせが、前の先から出た知らせより先に来る
        mark.targeted(true, Spot(day: 1, item: 1))
        mark.targeted(false, Spot(day: 1, item: 0))
        XCTAssertEqual(mark.spot, Spot(day: 1, item: 1))
        mark.targeted(false, Spot(day: 1, item: 1))
        XCTAssertNil(mark.spot)
    }

    func testDroppedClears() {
        var mark = TripDropMark<Spot>()
        mark.targeted(true, Spot(day: 0, item: nil))
        mark.dropped()
        XCTAssertNil(mark.spot)
    }

    /// (b) の並び: 入った知らせのあと、出た知らせも drop も来ずに運ぶ操作が終わる → 終わりの知らせで空
    func testEndWithoutExitOrDropClearsMark() {
        var mark = TripDropMark<Spot>()
        mark.targeted(true, Spot(day: 1, item: 0))
        mark.dragEnded()
        XCTAssertNil(mark.spot)
    }

    /// 運ぶ元の終わりの知らせ（`didEndWith` から呼ぶ `ended()`）が、渡した終わりの処理を呼ぶ
    func testEventsEndedRunsOnEnd() {
        var mark = TripDropMark<Spot>()
        mark.targeted(true, Spot(day: 1, item: 0))
        var began = 0
        let events = TripRowDragEvents(payload: "p", onBegin: { began += 1 }, onEnd: { mark.dragEnded() })
        events.began()
        XCTAssertEqual(began, 1)
        XCTAssertEqual(mark.spot, Spot(day: 1, item: 0), "持ち上がっただけでは消さない")
        events.ended()
        XCTAssertNil(mark.spot)
        XCTAssertEqual(events.payload, "p")
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    /// 本物の UIKit の受け手は Linux では動かせないので、つなぎを字で縛る:
    /// `didEndWith` → `events?.ended()`、画面の終わりの処理 → `dropMark.dragEnded()`、今の作りの行は `tripRowDragSource`
    func testWiringFromDidEndToDropMark() throws {
        let drag = try source("Features/Trips/TripRowDrag.swift")
        let didEnd = try XCTUnwrap(drag.range(of: "didEndWith operation: UIDropOperation) {"))
        let body = drag[didEnd.upperBound...].prefix(120)
        XCTAssertTrue(body.contains("events?.ended()"), "didEndWith で終わりを知らせていない")
        XCTAssertTrue(drag.contains("interaction.isEnabled = true"), "iPhone の既定は切なので入れる")

        let detail = try source("Features/Trips/TripPlanDetailView.swift")
        let onEnd = try XCTUnwrap(detail.range(of: "}, onEnd: {"))
        XCTAssertTrue(detail[onEnd.upperBound...].prefix(80).contains("dropMark.dragEnded()"),
                      "運ぶ操作が終わっても落とす先の印を空に戻していない")
        XCTAssertTrue(detail.contains(".tripRowDragSource(rowDragEvents("), "今の作りの行が UIDragInteraction で運んでいない")
    }
}
