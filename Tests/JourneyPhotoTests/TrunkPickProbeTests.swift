import XCTest
@testable import JourneyPhoto

/// 札 #424（旅のトランクの中身を押しても持ち上がらない回がある）の原因を数で取る記録 `TrunkPickProbe` の試験
/// （2026-11-07）。記録の形・無効のときに何も記録しないこと・履歴の上限・配線（元のコードを読む）を確かめる。
/// 画面（見えない要素）は Linux で動かせないので Mac の UI テスト（`testTrunkPickRepeat`）が見る
final class TrunkPickProbeTests: XCTestCase {

    private final class FakeClock {
        var now: TimeInterval = 1000
    }

    private func probe(enabled: Bool = true, _ clock: FakeClock) -> TrunkPickProbe {
        TrunkPickProbe(enabled: enabled, clock: { clock.now })
    }

    private let snapshot = TrunkPickProbe.Snapshot(flat: true, lidSettled: true, dragStartSet: false, held: "none",
                                                   p: 1, overflows: false, k: 1)

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// 何も起きていない値の形（UI テストが読む）
    func testSummaryShapeWhenNothingHappened() {
        let clock = FakeClock()
        let recorder = probe(clock)
        clock.now += 2
        XCTAssertEqual(recorder.summary(snapshot),
                       "flat=1 settled=1 dragStart=0 held=none p=1.000 overflows=0 k=1.000"
                       + " | drag=0/0/0 | pick=0@-ms | lastDrag=-ms@-,- endedAt=-ms | ev=[] | t=2000ms")
    }

    /// 引く指・押し・節目を数えて、時刻と座標を残す。続けて来る `changed` は履歴に1つ
    func testRecordsDragPickAndEvents() {
        let clock = FakeClock()
        let recorder = probe(clock)
        clock.now += 1
        recorder.recordDragChanged(x: 10.4, y: 20.6)
        clock.now += 0.1
        recorder.recordDragChanged(x: 12, y: 30)
        clock.now += 0.1
        recorder.recordDragEnded()
        clock.now += 0.2
        recorder.recordPick("card")
        recorder.recordEvent("moveDone settled=1")
        recorder.recordDragIgnoredByHeld()
        let text = recorder.summary(snapshot)
        XCTAssertTrue(text.contains("| drag=2/1/1 |"), text)
        XCTAssertTrue(text.contains("| pick=1@1400ms |"), text)
        XCTAssertTrue(text.contains("lastDrag=1100ms@12,30 endedAt=1200ms"), text)
        XCTAssertTrue(text.contains("ev=[+1000 changed;+1200 ended;+1400 pick:card;+1400 moveDone settled=1;+1400 ignoredHeld]"), text)
    }

    /// 履歴は新しい `eventCap` 件だけ（暴走しても値を膨らませない）
    func testEventsAreCapped() {
        let clock = FakeClock()
        let recorder = probe(clock)
        for index in 0..<(TrunkPickProbe.eventCap + 5) { recorder.recordEvent("e\(index)") }
        let text = recorder.summary(snapshot)
        XCTAssertFalse(text.contains(" e0;"), text)
        XCTAssertTrue(text.contains("e\(TrunkPickProbe.eventCap + 4)]"), text)
    }

    /// 無効のとき（本番・ふつうの起動）は何も記録しない
    func testDisabledRecordsNothing() {
        let clock = FakeClock()
        let recorder = probe(enabled: false, clock)
        recorder.recordDragChanged(x: 1, y: 2)
        recorder.recordDragEnded()
        recorder.recordPick("medal")
        recorder.recordEvent("x")
        recorder.recordDragIgnoredByHeld()
        let text = recorder.summary(snapshot)
        XCTAssertTrue(text.contains("| drag=0/0/0 | pick=0@-ms |"), text)
        XCTAssertTrue(text.contains("ev=[]"), text)
    }

    func testHeldLabels() {
        XCTAssertEqual(TrunkPickProbe.label(nil), "none")
        XCTAssertEqual(TrunkPickProbe.label(.more), "more")
        XCTAssertEqual(TrunkPickProbe.label(.card), "card")
        XCTAssertEqual(TrunkPickProbe.label(.tickets), "tickets")
    }

    /// 配線: 押しの入口・引く指の始まりと終わり・見えない要素が元のコードに在る（外すと落ちる）。
    /// 記録は本番の動きを変えない（`pick` の本体は残る）
    func testWiringInTheTrunkView() throws {
        let view = try source("Sources/JourneyPhoto/Features/Trunk/TrunkOpenView.swift")
        XCTAssertTrue(view.contains("TrunkPickProbe.shared.recordPick(TrunkPickProbe.label(item))"))
        XCTAssertTrue(view.contains("TrunkPickProbe.shared.recordDragChanged("))
        XCTAssertTrue(view.contains("TrunkPickProbe.shared.recordDragEnded()"))
        XCTAssertTrue(view.contains("if TrunkPickProbe.shared.isEnabled {"))
        XCTAssertTrue(view.contains("\"trunk.open.debug\""))
        XCTAssertTrue(view.contains("picks += 1"), "pick の本体が残っていない")
    }
}
