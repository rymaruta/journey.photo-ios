import XCTest
import SwiftUI
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
        XCTAssertTrue(detail.contains("guard TripAutosave.sendsOnScenePhase(phase), isDirty, !discarding, problem == nil else { return }"))
        XCTAssertTrue(detail.contains("_ = await flush(force: true)"))
        XCTAssertTrue(detail.contains("TripBackgroundWindow(name: \"trip-autosave\")"))
        XCTAssertTrue(detail.contains("await flusher.run { await flushNow(force: force) }"), "送りが1本にまとまっていない")
    }
}

/// F. `flush()` が2本同時に走れる（確かめ役の指摘・2026-11-10）。裏に回るとき（inactive と background の2回）・
/// 2秒の待ち・戻るとき・撮影スポットを開くときが重なると、後の1本が断られる・空の書き込みが増える・古い版で誤って止まる
@MainActor
final class TripAutosaveFlushOnceTests: XCTestCase {

    /// 送る1回ぶんを真似る: 直しがあれば読み直し（待つ）→ 書き込む。走っている本数の最大と書き込みの回数を数える
    private final class FakeScreen {
        var dirty = true
        var running = 0
        var maxRunning = 0
        var writes = 0
        /// 読み直しを待っている送り（来た順）
        var gates: [CheckedContinuation<Void, Never>] = []

        func flushBody() async -> Bool {
            guard dirty else { return true }
            running += 1
            maxRunning = max(maxRunning, running)
            await withCheckedContinuation { gates.append($0) }   // 読み直しを待っている間
            writes += 1
            dirty = false
            running -= 1
            return true
        }

        func openGate() {
            guard !gates.isEmpty else { return }
            gates.removeFirst().resume()
        }
    }

    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    /// 再現: まとめずに2回呼ぶと、2本が同時に走る（直す前の flush と同じ形）
    func testWithoutCoalescingTwoFlushesOverlap() async {
        let screen = FakeScreen()
        async let first = screen.flushBody()
        await settle()
        // 1本目が読み直しを待っている間に、2本目（裏に回る・戻る）。直しはまだ送れていない
        let second = Task { await screen.flushBody() }
        await settle()
        XCTAssertEqual(screen.maxRunning, 2, "直す前は2本が同時に走る")
        screen.openGate(); await settle()
        screen.openGate(); await settle()
        _ = await first
        _ = await second.value
        XCTAssertEqual(screen.writes, 2, "直す前は書き込みが2回（後の1本は要らない）")
    }

    /// 直し: `TripAutosaveFlusher` を通すと1本だけ走り、後の呼び出しは前の1本を待ってから直しの有無を見る
    func testFlusherRunsOneAtATime() async {
        let screen = FakeScreen()
        let flusher = TripAutosaveFlusher()
        let first = Task { await flusher.run { await screen.flushBody() } }
        await settle()
        let second = Task { await flusher.run { await screen.flushBody() } }
        let third = Task { await flusher.run { await screen.flushBody() } }
        await settle()
        XCTAssertEqual(screen.running, 1)
        screen.openGate(); await settle()
        let results = [await first.value, await second.value, await third.value]
        XCTAssertEqual(screen.maxRunning, 1, "2本同時に走った")
        XCTAssertEqual(screen.writes, 1, "直しが残っていないのに、後の呼び出しがもう一度書いた")
        XCTAssertEqual(results, [true, true, true], "後の呼び出しが「送れなかった」になった")
    }

    /// 送っている間にまた直した → 後の呼び出しは前の1本のあとでもう一度送る
    func testFlusherSendsAgainWhenEditedWhileSending() async {
        let screen = FakeScreen()
        let flusher = TripAutosaveFlusher()
        let first = Task { await flusher.run { await screen.flushBody() } }
        await settle()
        let second = Task { await flusher.run { await screen.flushBody() } }
        await settle()
        screen.openGate(); await settle()
        screen.dirty = true          // 1本目が終わる直前に直した、とは別に、終わってから直しが残っている形
        await settle()
        screen.openGate(); await settle()
        _ = await first.value
        _ = await second.value
        XCTAssertLessThanOrEqual(screen.maxRunning, 1)
    }

    /// 裏に回る送りは background のときだけ（inactive と background の2回で2本にしない）
    func testSendsOnlyWhenGoingToBackground() async {
        XCTAssertTrue(TripAutosave.sendsOnScenePhase(.background))
        XCTAssertFalse(TripAutosave.sendsOnScenePhase(.inactive))
        XCTAssertFalse(TripAutosave.sendsOnScenePhase(.active))
    }

    /// 裏に回る（inactive → background）と、直しが1つなら書き込みは1回
    func testGoingToBackgroundWritesOnce() async {
        let screen = FakeScreen()
        let flusher = TripAutosaveFlusher()
        var tasks: [Task<Bool, Never>] = []
        for phase in [ScenePhase.inactive, .background] where TripAutosave.sendsOnScenePhase(phase) {
            tasks.append(Task { await flusher.run { await screen.flushBody() } })
        }
        // 2秒の待ちが同じときに切れた
        tasks.append(Task { await flusher.run { await screen.flushBody() } })
        await settle()
        screen.openGate(); await settle()
        for t in tasks { _ = await t.value }
        XCTAssertEqual(screen.writes, 1)
        XCTAssertEqual(screen.maxRunning, 1)
    }
}
