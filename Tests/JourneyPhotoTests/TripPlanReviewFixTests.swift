import XCTest
@testable import JourneyPhoto

/// 確かめ役の指摘（2026-11-10・札 #521）を、直す前に再現した試験。
///
/// A. 待ちの仕事の中から `flush()` が `autosave.cancel()` を呼ぶと、**自分の仕事を取り消し**、続く
///    `fetchFresh`（`RequestLimiter.acquire` の `Task.checkCancellation`）が投げて送れなかった。
///    送っている間に直すと、`schedule()` が送っている仕事を取り消す筋道も同じ
@MainActor
final class TripPlanReviewFixTests: XCTestCase {

    /// 開くまで待たせる門（送っている最中を作る）
    private final class Gate {
        private var waiting: CheckedContinuation<Void, Never>?
        private var opened = false
        func wait() async {
            if opened { return }
            await withCheckedContinuation { waiting = $0 }
        }
        func open() {
            opened = true
            waiting?.resume()
            waiting = nil
        }
    }

    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    /// 待ち終えた仕事の中で `cancel()` を呼んでも、その仕事は取り消されない（送れる）
    func testCancelInsideTheSendDoesNotCancelItself() async {
        let debouncer = TripAutosaveDebouncer(delay: 1, sleep: { _ in })
        var cancelledInside: Bool?
        var checkThrew: Bool?
        debouncer.schedule {
            debouncer.cancel()   // `flush()` の始めと同じ
            cancelledInside = Task.isCancelled
            do { try Task.checkCancellation(); checkThrew = false } catch { checkThrew = true }   // `RequestLimiter.acquire` と同じ
        }
        await settle()
        XCTAssertEqual(cancelledInside, false, "送る仕事が自分を取り消している")
        XCTAssertEqual(checkThrew, false, "取り消しの確かめで投げる（fetchFresh が nil になって送れない）")
    }

    /// 送っている間に直しても、送っている仕事は止めず、直しは送り終えてから次の回に送る
    func testEditWhileSendingIsSentNext() async {
        let debouncer = TripAutosaveDebouncer(delay: 1, sleep: { _ in })
        let gate = Gate()
        var sends = 0
        var firstCancelled: Bool?
        debouncer.schedule {
            await gate.wait()
            firstCancelled = Task.isCancelled
            sends += 1
        }
        await settle()
        // 1回目は門で待っている（送っている最中）。ここで直す
        debouncer.schedule { sends += 1 }
        await settle()
        XCTAssertEqual(sends, 0, "送っている最中に2回目を走らせた")
        gate.open()
        await settle()
        XCTAssertEqual(firstCancelled, false, "送っている仕事が取り消された")
        XCTAssertEqual(sends, 2, "送っている間の直しを、送り終えてから送っていない")
    }

    /// 見本の口も本番と同じく取り消しを見る（本番は `RequestLimiter.acquire` が `Task.checkCancellation`）
    func testFixtureHonoursCancellationLikeTheServer() async {
        let store = TripPlanFixtureStore()
        let task = Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try await store.list(); return false } catch { return true }
        }
        let threw = await task.value
        XCTAssertTrue(threw, "取り消された仕事でも見本が答える（本番では投げる）")
    }

    // MARK: - C. 画面の外で入れたあとの版

    /// 再現: 日程の画面が開いたときの版のまま、シートが同じプランに入れると、次の送る前の読み直しで「別の端末の変更」になる
    func testOutsideAddMakesTheOpenScreenConflict() async throws {
        let store = TripPlanFixtureStore()
        let opened = try await store.list().first { $0.planId == "fixture-kanazawa" }
        var patch = TripPlanService.Patch()
        patch.days = TripPlanEdit.adding(.spot(spotId: "sp_x", note: nil), to: opened?.days ?? [], day: 0)
        let afterAdd = try await store.update(planId: "fixture-kanazawa", patch).first { $0.planId == "fixture-kanazawa" }
        XCTAssertTrue(TripAutosave.conflicted(base: opened, server: afterAdd), "古い版のまま送ろうとすると止まる（指摘の筋道）")
        // 直し: 送っていない直しが無ければ読み直す（読み直した版なら止まらない）
        XCTAssertTrue(TripAutosave.reloadsAfterOutsideChange(dirty: false, sending: false))
        XCTAssertFalse(TripAutosave.reloadsAfterOutsideChange(dirty: true, sending: false), "直しがあるときに読み直すと消える")
        XCTAssertFalse(TripAutosave.conflicted(base: afterAdd, server: afterAdd))
    }

    /// シートは送る前に読み直し、**いまの日程**に足す（開いたときの日程に足すと、その後の直しを上書きする）
    func testSheetAddsToTheFreshDays() async {
        let stale = TripPlan(planId: "p", title: "t", days: [TripDay(items: [.spot(spotId: "a", note: nil)])])
        let fresh = TripPlan(planId: "p", title: "t",
                             days: [TripDay(items: [.spot(spotId: "a", note: nil), .spot(spotId: "b", note: nil)])])
        let item = TripItem.spot(spotId: "new", note: nil)
        let next = TripAddSheet.daysAdding(item, to: "p", day: 0, in: [fresh])
        XCTAssertEqual(next?.first?.items.count, 3, "日程の画面が後から足した b が残っていない")
        XCTAssertEqual(TripPlanEdit.adding(item, to: stale.days, day: 0)?.first?.items.count, 2,
                       "開いたときの日程に足すと b が消える（直す前の筋道）")
        XCTAssertNil(TripAddSheet.daysAdding(item, to: "gone", day: 0, in: [fresh]), "消えたプランには送らない")
        XCTAssertNil(TripAddSheet.daysAdding(item, to: "p", day: 5, in: [fresh]), "無くなった日には送らない")
    }

    // MARK: - D. 裏に回るとき

    func testDetailSendsWhenGoingToBackground() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let detail = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Trips/TripPlanDetailView.swift"),
                                encoding: .utf8)
        XCTAssertTrue(detail.contains(".onChange(of: scenePhase) { _, phase in"))
        XCTAssertTrue(detail.contains("guard phase != .active, isDirty, !discarding, problem == nil else { return }"))
        XCTAssertTrue(detail.contains("_ = await flush(force: true)"))
        XCTAssertTrue(detail.contains("beginBackgroundTask(withName: \"trip-autosave\""))
    }
}
