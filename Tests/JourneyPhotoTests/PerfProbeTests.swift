import XCTest
@testable import JourneyPhoto

/// 起動直後の動きと重さを数で取る仕組み（2026-11-04・札 #435 / #429）の試験。
///
/// 記録の形（`PerfRecorder.summary()`）・停止の数え方（`StallMeter`）・signpost の名前・配線（元のコードを読む）を確かめる。
/// 各試験は直しを戻すと落ちる。画面（見えない要素・`CADisplayLink`）は Linux で動かせないので Mac の UI テストが見る
final class PerfProbeTests: XCTestCase {

    // MARK: - 道具

    /// 進められる時計（秒）。作った時点（1000 秒）が 0ms
    private final class FakeClock {
        var now: TimeInterval = 1000
    }

    private func recorder(enabled: Bool = true, _ clock: FakeClock) -> PerfRecorder {
        PerfRecorder(enabled: enabled, clock: { clock.now })
    }

    /// `stalls=` の右から `ev=` の手前まで（`[…]`）。`ev=` を足しても停止の一覧の試験が変わらないように
    private func stallsTail(_ rec: PerfRecorder) -> String? {
        rec.summary().components(separatedBy: " | stalls=").last?
            .components(separatedBy: " | ev=").first
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        // 注記（`//`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    // MARK: - signpost の名前

    /// 区間の名前は UI テストの `XCTOSSignpostMetric` と Instruments で引く。起動の同期の区間 4 つが在って、重ならない
    func testLaunchSyncSignpostNamesExistAndAreUnique() {
        let names = PerfSignpost.Name.allCases.map(\.rawValue)
        XCTAssertEqual(Set(names).count, names.count, "区間の名前が重なっている")
        for expected in ["LaunchSync", "LaunchSyncStores", "LaunchSyncSweepOrphans", "LaunchSyncDraftPrepare"] {
            XCTAssertTrue(names.contains(expected), "\(expected) の区間が無い")
        }
        XCTAssertEqual(PerfSignpost.Name.launchSync.rawValue, "LaunchSync")
    }

    /// どの名前でも始めて終えられる（`switch` の書き漏らしで落ちない）。同期の包みは値をそのまま返す
    func testEveryIntervalCanBeginEndAndMeasureReturnsTheValue() {
        for name in PerfSignpost.Name.allCases {
            PerfSignpost.end(PerfSignpost.begin(name))
        }
        XCTAssertEqual(PerfSignpost.measure(.launchSyncSweepOrphans) { 42 }, 42)
    }

    /// 🔴 起動の同期の区間が、実際の呼び出しを包んでいる（包みを外すと落ちる）。
    /// 包むだけで、呼び出し自体（`sweepOrphans`・`prepare`）は残る
    func testLaunchTaskWrapsTheSynchronousCallsInSignposts() throws {
        let app = try source("Sources/JourneyPhoto/App/JourneyPhotoApp.swift")
        XCTAssertTrue(app.contains("PerfSignpost.measure(.launchSyncSweepOrphans) { UploadDraftStore().sweepOrphans() }"),
                      "sweepOrphans を包んでいない")
        XCTAssertTrue(app.contains("PerfSignpost.measure(.launchSyncDraftPrepare) { DraftLibrary.shared.prepare(for: userId) }"),
                      "DraftLibrary.prepare を包んでいない")
        // 頭 → Store の use → 終わり → syncWishlist の前、の順
        let begin = try XCTUnwrap(app.range(of: "PerfSignpost.begin(.launchSync)"))
        let storesBegin = try XCTUnwrap(app.range(of: "PerfSignpost.begin(.launchSyncStores)"))
        let favorites = try XCTUnwrap(app.range(of: "favorites.use(userId: auth.userId)"))
        let seen = try XCTUnwrap(app.range(of: "seenStories.use(userId: auth.userId)"))
        let storesEnd = try XCTUnwrap(app.range(of: "PerfSignpost.end(launchStores)"))
        let end = try XCTUnwrap(app.range(of: "PerfSignpost.end(launchSync)"))
        let wishlist = try XCTUnwrap(app.range(of: "await syncWishlist(since: wishMark)"))
        XCTAssertLessThan(begin.lowerBound, storesBegin.lowerBound)
        XCTAssertLessThan(storesBegin.lowerBound, favorites.lowerBound)
        XCTAssertLessThan(seen.lowerBound, storesEnd.lowerBound)
        XCTAssertLessThan(storesEnd.lowerBound, end.lowerBound)
        XCTAssertLessThan(end.lowerBound, wishlist.lowerBound, "launchSync は syncWishlist の前で終える")
    }

    /// 🔴 UI テストが同期の区間を `XCTOSSignpostMetric` で取っている
    func testPerformanceTestReadsTheLaunchSyncIntervals() throws {
        let text = try source("UITests/JourneyPhotoUITests/PerformanceTests.swift")
        for name in ["LaunchSync", "LaunchSyncStores", "LaunchSyncSweepOrphans", "LaunchSyncDraftPrepare"] {
            XCTAssertTrue(text.contains("name: \"\(name)\""), "\(name) を測っていない")
        }
    }

    // MARK: - 記録（PerfRecorder）

    /// 無効のとき（本番・ふつうの起動）は、何を渡しても記録しない
    func testDisabledRecorderRecordsNothing() {
        let clock = FakeClock()
        let rec = recorder(enabled: false, clock)
        clock.now = 1000.2
        rec.recordSelection(site: "tabs.set", from: "home", to: "search")
        XCTAssertEqual(rec.beginTask("auth.state"), -1)
        rec.endTask(0)
        rec.recordFrame(at: 1)
        rec.recordFrame(at: 2)
        rec.bodyHit(.home)
        XCTAssertEqual(rec.bodyCount(.home), 0)
        XCTAssertTrue(rec.summary().hasPrefix("sel=[] | task=[] | stall=0/0ms/0f | body=home:0,myPage:0,photoDetail:0 | t="),
                      rec.summary())
    }

    /// 履歴の形: 何 ms に・何から何へ・どこで。task は始めと終わり。停止は回数/最大/刻みの数。body は画面ごと
    func testSummaryFormat() {
        let clock = FakeClock()
        let rec = recorder(clock)
        clock.now = 1000.120
        rec.recordSelection(site: "tabs.set", from: "home", to: "search")
        clock.now = 1000.200
        let task = rec.beginTask("auth.state.sync")
        XCTAssertEqual(task, 0)
        rec.bodyHit(.home)
        rec.bodyHit(.home)
        rec.bodyHit(.photoDetail)
        for t in [10.0, 10.016, 10.166, 10.182] { rec.recordFrame(at: t) }
        clock.now = 1000.300
        rec.recordSelection(site: "post.revert", from: "post", to: "home")
        // 終わる前の値は「…」
        XCTAssertTrue(rec.summary().contains("task=[#0 auth.state.sync 200-…]"), rec.summary())
        clock.now = 1000.450
        rec.endTask(task)
        clock.now = 1000.500
        XCTAssertEqual(rec.summary(),
                       "sel=[+120ms home>search@tabs.set;+300ms post>home@post.revert]"
                       + " | task=[#0 auth.state.sync 200-450ms]"
                       + " | stall=1/150ms/3f"
                       + " | body=home:2,myPage:0,photoDetail:1"
                       + " | t=500ms"
                       // 150ms 止まった刻みが戻ってきたのが 200ms → 止まり始めは 50ms（2026-11-07）
                       + " | stalls=[+50ms 150ms]"
                       // 出来事（2026-11-07）: body の最初の 2 回までが入る。ホームの 2 回・写真詳細の 1 回
                       + " | ev=[+200 body.home#1;+200 body.home#2;+200 body.photoDetail#1]"
                       + " | samples=[]")
        XCTAssertEqual(rec.bodyCount(.home), 2)
    }

    /// 履歴には上限がある（暴走しても値を膨らませず、溢れた数は残す）
    func testSelectionHistoryIsCappedAndCountsDropped() {
        let clock = FakeClock()
        let rec = recorder(clock)
        for _ in 0..<(PerfRecorder.selectionCap + 5) {
            rec.recordSelection(site: "x", from: "a", to: "b")
        }
        XCTAssertTrue(rec.summary().contains(";+5dropped]"), rec.summary())
        XCTAssertEqual(rec.summary().components(separatedBy: "a>b@x").count - 1, PerfRecorder.selectionCap)
    }

    /// body の評価は呼ぶたびに1足される（画面ごとに別）
    func testBodyHitAddsOnePerEvaluationPerScreen() {
        let clock = FakeClock()
        let rec = recorder(clock)
        for _ in 0..<7 { rec.bodyHit(.myPage) }
        rec.bodyHit(.home)
        XCTAssertEqual(rec.bodyCount(.myPage), 7)
        XCTAssertEqual(rec.bodyCount(.home), 1)
        XCTAssertEqual(rec.bodyCount(.photoDetail), 0)
    }

    // MARK: - 停止の数え方（StallMeter）

    /// 100ms を超える間隔だけを停止に数える（ちょうど 100ms は数えない）。最大の間隔も残す
    func testStallMeterCountsGapsOverThreshold() {
        var meter = StallMeter()
        meter.ingest(5.000)             // 最初の1回は間隔が無い
        XCTAssertEqual(meter.frames, 0)
        meter.ingest(5.016)
        meter.ingest(5.116)             // 100ms ちょうど: 数えない
        meter.ingest(5.346)             // 230ms: 数える
        meter.ingest(5.362)
        XCTAssertEqual(meter.count, 1)
        XCTAssertEqual(meter.maxMs, 230)
        XCTAssertEqual(meter.frames, 4)
    }

    /// 裏から戻った直後の長い空きは、reset してあれば数えない
    func testStallMeterResetIgnoresTheGapAcrossBackground() {
        var meter = StallMeter()
        meter.ingest(1.0)
        meter.ingest(1.016)
        meter.reset()
        meter.ingest(61.0)              // 裏にいた 1 分
        meter.ingest(61.016)
        XCTAssertEqual(meter.count, 0)
        XCTAssertEqual(meter.maxMs, 16)
    }

    // MARK: - 停止の一覧（起点と長さ・2026-11-07・札 #435・#429）

    /// 閾値を超えた間隔だけを返す（超えない・最初の1回は nil）
    func testStallMeterIngestReturnsTheGapOnlyWhenOverThreshold() {
        var meter = StallMeter()
        XCTAssertNil(meter.ingest(5.000))
        XCTAssertNil(meter.ingest(5.016))
        XCTAssertNil(meter.ingest(5.116), "100ms ちょうどは数えない")
        XCTAssertEqual(meter.ingest(5.346), 230)
        XCTAssertNil(meter.ingest(5.362))
    }

    /// 停止の起点は「刻みが戻ってきた時刻 − 長さ」。`task=`・`sel=` と同じ時計なので突き合わせられる
    func testStallEventsStartIsEndMinusGapInTheRecorderClock() {
        let clock = FakeClock()
        let rec = recorder(clock)
        rec.recordFrame(at: 1.000)
        clock.now = 1000.300
        rec.recordFrame(at: 1.016)
        clock.now = 1001.800
        rec.recordFrame(at: 2.516)      // 1500ms 止まって戻ってきた（1800ms 時点）
        XCTAssertEqual(stallsTail(rec), "[+300ms 1500ms]")
    }

    /// 一覧には上限があり、**長いものから**残す。出力は起点の順
    func testStallEventsKeepTheLongestAndAreSortedByStart() {
        let clock = FakeClock()
        let rec = recorder(clock)
        var t = 10.0
        rec.recordFrame(at: t)
        // 上限 + 3 件の停止。長さは 110ms から 1ms ずつ増やす（最後の 3 件が最長）
        for i in 0..<(PerfRecorder.stallEventCap + 3) {
            clock.now = 1000 + Double(i + 1)
            t += 0.110 + Double(i) * 0.001
            rec.recordFrame(at: t)
        }
        let tail = (stallsTail(rec) ?? "").dropFirst()
        let events = tail.dropLast().split(separator: ";").map(String.init)
        XCTAssertEqual(events.count, PerfRecorder.stallEventCap)
        let gaps = events.map { Int($0.split(separator: " ")[1].replacingOccurrences(of: "ms", with: "")) ?? 0 }
        XCTAssertFalse(gaps.contains(110), "いちばん短いものから落とす")
        XCTAssertTrue(gaps.contains(124), "最長は残る")
        let starts = events.map { Int($0.split(separator: " ")[0].dropFirst().replacingOccurrences(of: "ms", with: "")) ?? 0 }
        XCTAssertEqual(starts, starts.sorted(), "起点の順に並ぶ")
    }

    /// 停止が無ければ空。数えない起動では何も残さない
    func testStallEventsEmptyWhenNoStallOrDisabled() {
        let clock = FakeClock()
        let rec = recorder(clock)
        rec.recordFrame(at: 1.000)
        rec.recordFrame(at: 1.016)
        XCTAssertEqual(stallsTail(rec), "[]", rec.summary())
        let off = PerfRecorder(enabled: false, clock: { clock.now })
        off.recordFrame(at: 1.000)
        off.recordFrame(at: 3.000)
        XCTAssertEqual(stallsTail(off), "[]")
    }

    // MARK: - 出来事（ev）

    private func evTail(_ rec: PerfRecorder) -> String {
        (rec.summary().components(separatedBy: " | ev=").last ?? "")
            .components(separatedBy: " | samples=").first ?? ""
    }

    /// 止まっている最中の積みの見本: `+撮った ms 段^段`・浅い方が先・段は上限まで・件数にも上限。無効なら残さない
    func testSamplesAreRecordedAndCapped() {
        let clock = FakeClock()
        let rec = recorder(clock)
        clock.now = 1005.300
        rec.recordSample(frames: (0..<(PerfRecorder.sampleFrameCap + 5)).map { "f\($0)" })
        let tail = rec.summary().components(separatedBy: " | samples=").last ?? ""
        XCTAssertTrue(tail.hasPrefix("[+5300 f0^f1^"), tail)
        XCTAssertTrue(tail.hasSuffix("^f\(PerfRecorder.sampleFrameCap - 1)]"), tail)
        for _ in 0..<(PerfRecorder.sampleCap + 3) { rec.recordSample(frames: ["x"]) }
        let after = rec.summary().components(separatedBy: " | samples=").last ?? ""
        XCTAssertEqual(after.components(separatedBy: ";").count, PerfRecorder.sampleCap)
        let off = PerfRecorder(enabled: false, clock: { clock.now })
        off.recordSample(frames: ["x"])
        XCTAssertEqual(off.summary().components(separatedBy: " | samples=").last, "[]")
    }

    /// 出来事は `+起動からのms 名前`・起きた順。何も無ければ空。`stalls=` の後ろに付く（既存の欄の順は変えない）
    func testEventsAreRecordedInOrderWithTimes() {
        let clock = FakeClock()
        let rec = recorder(clock)
        XCTAssertEqual(evTail(rec), "[]")
        clock.now = 1000.012
        rec.event("app.init.start")
        clock.now = 1000.340
        rec.event("camper.ext.plan>")
        XCTAssertEqual(evTail(rec), "[+12 app.init.start;+340 camper.ext.plan>]")
        let parts = rec.summary().components(separatedBy: " | ")
        XCTAssertEqual(parts.last?.hasPrefix("ev="), true, "ev は最後の欄（既存の欄の後ろ）")
        XCTAssertTrue(parts.dropLast().last?.hasPrefix("stalls=") == true)
    }

    /// 上限を超えたら先の分を残し、溢れた数を残す。無効のときは何も残さない（名前の文字列も作らない）
    func testEventsAreCappedAndDisabledRecordsNothing() {
        let clock = FakeClock()
        let rec = recorder(clock)
        for i in 0..<(PerfRecorder.eventCap + 3) { rec.event("e\(i)") }
        let tail = evTail(rec)
        XCTAssertTrue(tail.hasSuffix(";+3dropped]"), tail)
        XCTAssertTrue(tail.contains("e0;"), "先の分は残る")
        XCTAssertFalse(tail.contains("e\(PerfRecorder.eventCap)"), "上限より後は残さない")

        var built = false
        let off = PerfRecorder(enabled: false, clock: { clock.now })
        off.event({ built = true; return "x" }())
        off.bodyHit(.home)
        XCTAssertEqual(evTail(off), "[]")
        XCTAssertFalse(built, "無効のときは名前を作らない")
    }

    /// 同じ名前は最初の1回だけ（何度も起きる出来事が 40 件の枠を使い切らない）。細かい 2 区間は枠を使わない
    func testSameEventNameIsKeptOnlyOnce() {
        let clock = FakeClock()
        let rec = recorder(clock)
        clock.now = 1000.100
        rec.event("app.body")
        clock.now = 1000.200
        rec.event("app.body")
        rec.event("x")
        XCTAssertEqual(evTail(rec), "[+100 app.body;+200 x]")
        XCTAssertTrue(PerfSignpost.recordsEvent(.launchSync))
        XCTAssertFalse(PerfSignpost.recordsEvent(.launchSyncSweepOrphans))
        XCTAssertFalse(PerfSignpost.recordsEvent(.launchSyncDraftPrepare))
    }

    /// signpost の区間の始め・終わりも出来事に残る（`PerfSignpost.begin/end` が `PerfRecorder.shared` に渡す配線）
    func testSignpostWiringRecordsEvents() throws {
        let text = try source("Sources/JourneyPhoto/Core/Async/PerfSignpost.swift")
        XCTAssertTrue(text.contains("PerfRecorder.shared.event(\"sp.\\(name.rawValue)>\")"), "begin が出来事を残していない")
        XCTAssertTrue(text.contains("PerfRecorder.shared.event(\"sp.\\(interval.name.rawValue)<\")"), "end が出来事を残していない")
    }

    // MARK: - 配線

    /// 🔴 `selection` を書くのは `select(_:at:)` の1か所だけ（書き込みの場所が記録から漏れない）。
    /// 7か所すべてが `select` を通り、場所の名前が付いている
    func testEverySelectionWriteGoesThroughTheRecordingHelper() throws {
        let root = try source("Sources/JourneyPhoto/App/RootView.swift")
        let writes = root.components(separatedBy: "\n").filter {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return line.hasPrefix("selection = ")
        }
        XCTAssertEqual(writes, ["        selection = tab"], "selection を直に書く所が残っている: \(writes)")
        for site in ["takeActivityRequest", "homeRequests", "tabs.set", "post.revert",
                     "myPageRequests", "searchRequests", "mapRequests"] {
            XCTAssertTrue(root.contains("at: \"\(site)\")"), "\(site) の書き込みが記録を通っていない")
        }
        XCTAssertTrue(root.contains("PerfRecorder.shared.recordSelection(site: site, from: selection, to: tab)"))
        XCTAssertTrue(root.contains("if PerfRecorder.shared.isEnabled { PerfProbeOverlay() }"), "見えない要素を置いていない")
    }

    /// 🔴 ホーム・マイページ・写真詳細の body が評価を数えている。記録の口は UI テストのときだけ有効
    func testMajorScreensCountBodyEvaluations() throws {
        let home = try source("Sources/JourneyPhoto/Features/Gallery/GalleryView.swift")
        XCTAssertTrue(home.contains("let _ = PerfRecorder.shared.bodyHit(.home)"))
        let mine = try source("Sources/JourneyPhoto/Features/Profile/MyPageView.swift")
        XCTAssertTrue(mine.contains("let _ = PerfRecorder.shared.bodyHit(.myPage)"))
        let detail = try source("Sources/JourneyPhoto/Features/PhotoDetail/PhotoDetailView.swift")
        XCTAssertTrue(detail.contains("let _ = PerfRecorder.shared.bodyHit(.photoDetail)"))
        let session = try source("Sources/JourneyPhoto/Core/Auth/PreviewSession.swift")
        XCTAssertTrue(session.contains("static let perfProbeKey = \"JPPreviewPerfProbe\""))
        XCTAssertTrue(session.contains("return UserDefaults.standard.bool(forKey: perfProbeKey)"))
    }
}
