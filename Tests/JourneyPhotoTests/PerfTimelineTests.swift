import XCTest
@testable import JourneyPhoto

/// 札 #594 の下調べの通しの記録（`PerfTimeline`・見えない要素 `perf.timeline`）の試験。
/// UI テスト（`PerformanceTests.testUsageSurveyProbe`）が段ごとに数えるので、値の形と、時刻の取り方を確かめる。
/// 画面（`CADisplayLink`・メモリ）は Linux で動かせないので、時計とメモリの口を差し替える
final class PerfTimelineTests: XCTestCase {

    private final class Box {
        var now: TimeInterval = 1000
        var bytes: Int? = 100 * 1_048_576
    }

    private func timeline(enabled: Bool = true, _ box: Box) -> PerfTimeline {
        PerfTimeline(enabled: enabled, origin: 1000, clock: { box.now }, footprint: { box.bytes })
    }

    private func section(_ summary: String, _ key: String) -> String {
        for part in summary.components(separatedBy: " | ") where part.hasPrefix(key + "=") {
            return String(part.dropFirst(key.count + 1))
        }
        return "(無い)"
    }

    /// 停止の始めは**前の刻みの時刻**（刻みが届いた時刻ではない）。届くのが遅れても後ろにずれない
    func testStallStartIsThePreviousFrameTimestampNotTheCallbackTime() {
        let box = Box()
        let tl = timeline(box)
        tl.recordFrame(at: 1001.000)
        tl.recordFrame(at: 1001.016)
        // 1001.016 の次の刻みが 1003.316（2300ms 後）。届いたのはさらに 1.5 秒後
        box.now = 1004.816
        tl.recordFrame(at: 1003.316)
        XCTAssertEqual(section(tl.summary(), "st"), "[1016:2300]")
    }

    /// 100ms 以下は停止に数えない。全部を起きた順に残す（長い順の上限で落とさない）
    func testKeepsEveryStallInOrder() {
        let box = Box()
        let tl = timeline(box)
        var t = 1000.0
        tl.recordFrame(at: t)
        for gap in [0.016, 0.150, 0.016, 0.090, 0.400, 0.120] {
            t += gap
            tl.recordFrame(at: t)
        }
        XCTAssertEqual(section(tl.summary(), "st"), "[16:150,272:400,672:120]")
    }

    /// 裏から戻った直後の空きを数えない
    func testResetSkipsTheGapAcrossBackground() {
        let box = Box()
        let tl = timeline(box)
        tl.recordFrame(at: 1001)
        tl.resetFrames()
        tl.recordFrame(at: 1010)
        XCTAssertEqual(section(tl.summary(), "st"), "[]")
    }

    /// メモリは 1 秒ごとに MB で残す（間の刻みでは読まない）
    func testRecordsMemoryOncePerSecond() {
        let box = Box()
        let tl = timeline(box)
        box.now = 1000.5
        tl.recordFrame(at: 1000.5)
        box.now = 1000.9
        box.bytes = 150 * 1_048_576
        tl.recordFrame(at: 1000.9)
        box.now = 1001.6
        box.bytes = 210 * 1_048_576
        tl.recordFrame(at: 1001.6)
        XCTAssertEqual(section(tl.summary(), "mem"), "[500:100,1600:210]")
    }

    /// body の回数は名前ごとの累計（名前の順）
    func testCountsBodiesPerName() {
        let tl = timeline(Box())
        tl.count("body.map")
        tl.count("body.home")
        tl.count("body.map")
        XCTAssertEqual(section(tl.summary(), "cnt"), "[body.home:1,body.map:2]")
    }

    /// 積みの見本は**新しい方から** `sampleCap` 件。区切りの字は値に入れない
    func testKeepsNewestSamplesWithAppFrames() {
        let box = Box()
        let tl = timeline(box)
        for i in 0..<(PerfTimeline.sampleCap + 3) {
            box.now = 1000 + Double(i)
            tl.recordSample(frames: ["libA`top\(i)", "SwiftUI`x", "SwiftUI`y", "JourneyPhoto.debug.dylib`Foo;bar^[1]"])
        }
        let rs = section(tl.summary(), "rs")
        XCTAssertTrue(rs.hasPrefix("[+3000 libA`top3^SwiftUI`x^SwiftUI`y^JourneyPhoto.debug.dylib`Foo_bar__1_;"), rs)
        let last = PerfTimeline.sampleCap + 2
        XCTAssertTrue(rs.hasSuffix("+\(last)000 libA`top\(last)^SwiftUI`x^SwiftUI`y^JourneyPhoto.debug.dylib`Foo_bar__1_]"), rs)
        XCTAssertEqual(rs.components(separatedBy: ";").count, PerfTimeline.sampleCap)
    }

    /// 残す段: 浅い 3 段・その下で初めて出る画像（下回りは除く）を 4 つ・アプリの段（`$main` は除く）を 3 つ。
    /// ログを標準エラーに写す所を、誰が呼んだか（MapKit など）が残る（2026-11-14・run 1231 では分からなかった）
    func testPickFramesKeepsCallerImages() {
        let frames = ["libsystem_trace.dylib`_os_trace_writev", "libsystem_trace.dylib`_os_log_impl_mirror_to_stderr",
                      "libsystem_trace.dylib`_os_log_impl", "libsystem_trace.dylib`os_log_x", "VectorKit`-[VKMap draw]",
                      "VectorKit`-[VKMap other]", "libdispatch.dylib`_dispatch_call", "MapKit`-[MKMapView layout]",
                      "SwiftUICore`body", "JourneyPhoto.debug.dylib`PhotoMapView.body", "JourneyPhoto.debug.dylib`static_JourneyPhoto.JourneyPhotoApp.$main()"]
        XCTAssertEqual(PerfTimeline.pickFrames(frames), [
            "libsystem_trace.dylib`_os_trace_writev", "libsystem_trace.dylib`_os_log_impl_mirror_to_stderr",
            "libsystem_trace.dylib`_os_log_impl", "VectorKit`-[VKMap draw]", "MapKit`-[MKMapView layout]",
            "JourneyPhoto.debug.dylib`PhotoMapView.body"])
    }

    /// 処理の時間は名前ごとに 回数/合計/最大、いまの値は足し引き・置き換え（名前の順）
    func testMeasureAndGauges() {
        let box = Box()
        let tl = timeline(box)
        XCTAssertEqual(tl.measure("home.choices") { box.now += 0.040; return 1 }, 1)
        _ = tl.measure("home.choices") { box.now += 0.010 }
        tl.gauge("img.decodedKB", add: 300)
        tl.gauge("img.decodedKB", add: -100)
        tl.gauge("urlcache.memKB", set: 50)
        let summary = tl.summary()
        XCTAssertEqual(section(summary, "dur"), "[home.choices:2/50/40]")
        XCTAssertEqual(section(summary, "gauge"), "[img.decodedKB:200,urlcache.memKB:50]")
    }

    /// `_printChanges` の行から「評価し直した理由」の名前を作る。別の出力は数えない
    func testChangeLogKeys() {
        XCTAssertEqual(PerfChangeLog.keys(fromLine: "GalleryView: @self, _auth changed.\n"),
                       ["chg.GalleryView.@self", "chg.GalleryView._auth"])
        XCTAssertEqual(PerfChangeLog.keys(fromLine: "HomeFeedTile: unchanged."), ["chg.HomeFeedTile.unchanged"])
        XCTAssertEqual(PerfChangeLog.keys(fromLine: "Foo<Bar>: _x changed."), ["chg.Foo._x"])
        XCTAssertEqual(PerfChangeLog.keys(fromLine: "[feed] 公開写真のページを読めませんでした: x changed."), [])
        XCTAssertEqual(PerfChangeLog.keys(fromLine: "PERF something"), [])
    }

    /// 無効のとき（本番）は何も残さない
    func testDisabledRecordsNothing() {
        let box = Box()
        let tl = timeline(enabled: false, box)
        tl.recordFrame(at: 1001)
        tl.recordFrame(at: 1003)
        tl.count("body.map")
        tl.recordSample(frames: ["a"])
        box.now = 1002
        tl.gauge("img.decodedKB", add: 10)
        XCTAssertEqual(tl.measure("x") { 7 }, 7)
        XCTAssertEqual(tl.summary(), "t=2000 | st=[] | mem=[] | cnt=[] | rs=[] | dur=[] | gauge=[]")
    }

    /// 🔴 配線: 刻み・裏に入る・積みの見本・body の回数が通しの記録に届いている（外すと落ちる）
    func testIsWiredIntoTheProbe() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func read(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }
        let overlay = try read("Sources/JourneyPhoto/Core/Async/PerfProbeOverlay.swift")
        for wire in ["PerfTimeline.shared.recordFrame(at: link.timestamp)", "PerfTimeline.shared.resetFrames()",
                     "PerfTimeline.shared.recordSample(frames: frames)", "PerfTimeline.shared.summary()",
                     "accessibilityIdentifier(Self.timelineIdentifier)", "static let timelineIdentifier = \"perf.timeline\""] {
            XCTAssertTrue(overlay.contains(wire), "PerfProbeOverlay に \(wire) が無い")
        }
        XCTAssertTrue(overlay.contains("PerfChangeLog.start()"), "評価し直した理由を読み始めていない")
        for (path, wire) in [("Sources/JourneyPhoto/Features/Gallery/HomeTopCardView.swift", "PerfTimeline.shared.measure(\"home.topCard.choices\")"),
                             ("Sources/JourneyPhoto/Features/Gallery/HomeTopCardView.swift", "PerfTimeline.shared.measure(\"home.topCard.visibleShelf\")"),
                             ("Sources/JourneyPhoto/Features/Gallery/HomeTopCardView.swift", "PerfTimeline.shared.measure(\"home.topCard.detailNeeds\")"),
                             ("Sources/JourneyPhoto/Features/Gallery/HomeTopCardView.swift", "PerfChangeLog.note(Self.self)"),
                             ("Sources/JourneyPhoto/Features/Gallery/GalleryView.swift", "PerfChangeLog.note(Self.self)"),
                             ("Sources/JourneyPhoto/App/RootView.swift", "PerfChangeLog.note(Self.self)"),
                             ("Sources/JourneyPhoto/Features/Common/DownsampledRemoteImage.swift", "PerfTimeline.shared.gauge(\"img.decodedKB\", add: cost / 1024)"),
                             ("Sources/JourneyPhoto/Core/Async/PerfTimeline.swift", "gauges[\"urlcache.memKB\"] = urlCacheKB")] {
            XCTAssertTrue(try read(path).contains(wire), "\(path) に \(wire) が無い")
        }
        XCTAssertEqual(try read("Sources/JourneyPhoto/Features/Gallery/HomeMosaic.swift").components(separatedBy: "PerfChangeLog.note(Self.self)").count, 3,
                       "格子と札の body で理由を書かせていない")
        let recorder = try read("Sources/JourneyPhoto/Core/Async/PerfProbe.swift")
        XCTAssertTrue(recorder.contains("PerfTimeline.shared.count(key)"), "hit が通しの記録に数えていない")
        XCTAssertTrue(recorder.contains("PerfTimeline.shared.count(\"body.\\(screen.rawValue)\")"), "bodyHit が通しの記録に数えていない")
        for (path, key) in [("Sources/JourneyPhoto/Features/Map/PhotoMapView.swift", "body.map"),
                            ("Sources/JourneyPhoto/Features/Messages/DMInboxView.swift", "body.dmInbox"),
                            ("Sources/JourneyPhoto/Features/Upload/PostSheet.swift", "body.postSheet"),
                            ("Sources/JourneyPhoto/Features/Upload/UploadView.swift", "body.upload")] {
            XCTAssertTrue(try read(path).contains("PerfTimeline.shared.count(\"\(key)\")"), "\(path) の body を数えていない")
        }
    }

    // MARK: - 主スレッドの積みのファイル（`PerfMainTrace`・2026-11-14 run 1244 の 5956ms）

    /// 行に止まりと同じ時計の `t=` があり、浅い 8 段で切れる深い所の**画面読み・ログの段**と、このアプリの段を残す
    func testMainTraceLineKeepsTimelineClockAndDeepScreenReadFrames() {
        let shallow = (0..<8).map { "SwiftUICore`frame\($0)" }
        let deep = ["UIKitCore`x", "XCTAutomationSupport`-[XCTAccessibilityFramework attributesForElement:]",
                    "JourneyPhoto.debug.dylib`JourneyPhoto.HomeTopCardView.body.getter", "UIAccessibility`load",
                    "AXCoreUtilities`a", "AXRuntime`b", "libsystem_trace.dylib`_os_trace_writev"]
        let line = PerfMainTrace.line(ms: 1200, timelineMs: 9440, pingMs: nil, frames: shallow + deep)
        let head = line.components(separatedBy: " | ")[0]
        XCTAssertEqual(head, "ms=1200 t=9440 ping=pending")
        let frames = line.components(separatedBy: " | ")[1].components(separatedBy: " ; ")
        XCTAssertEqual(Array(frames.prefix(8)), shallow)
        XCTAssertEqual(frames[8], "…")
        // 印のある段は 3 つまで（深い方の順）。アプリの段はそのあと
        XCTAssertEqual(Array(frames[9...]), [deep[1], deep[3], deep[4], deep[2]])
        XCTAssertEqual(PerfMainTrace.line(ms: 5, timelineMs: 7, pingMs: 12, frames: ["a`b"]), "ms=5 t=7 ping=12 | a`b")
        // 壁時計（札 #590）は t= のあと。読む側（`PerfMainTraceLine`）は欄の名前で読むので、足しても t= と ping= は読める
        XCTAssertEqual(PerfMainTrace.line(ms: 5, timelineMs: 7, wall: "01:02:03.456", pingMs: 12, frames: ["a`b"]),
                       "ms=5 t=7 wall=01:02:03.456 ping=12 | a`b")
        // 印は UI テストの種類分け（`PerfSurveyStage.kind`）と同じもの
        XCTAssertEqual(Set(PerfMainTrace.markers), ["UIAccessibility", "AXRuntime", "AXCoreUtilities", "XCTAutomationSupport",
                                                    "_os_log_impl_mirror_to_stderr", "_os_trace_writev"])
    }

    /// 🔴 ファイルの書き手が `PerfMainTrace.line` で `t=` を書き、下調べの UI テストがファイルを渡して止まりごとにログへ出す
    func testUsageSurveyWiresTheMainTraceFile() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func read(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }
        let overlay = try read("Sources/JourneyPhoto/Core/Async/PerfProbeOverlay.swift")
        XCTAssertTrue(overlay.contains("PerfMainTrace.line(ms:"), "ファイルの行を PerfMainTrace で書いていない")
        XCTAssertTrue(overlay.contains("wall: sentWall,"), "ファイルの行に壁時計（札 #590）が無い")
        XCTAssertTrue(overlay.contains("timelineMs: Int(((sent - PerfRecorder.shared.origin) * 1000).rounded())"),
                      "t= が止まり（PerfTimeline）と同じ時計でない")
        let probe = try read("UITests/JourneyPhotoUITests/PerformanceTests.swift")
        XCTAssertTrue(probe.contains("app.launchArguments += [\"-JPMainSampleFile\", tracePath]"), "下調べでファイルを渡していない")
        XCTAssertTrue(probe.contains("(\"stalls\", stallsText)"), "PERF の行に止まりの一覧が無い")
        XCTAssertTrue(probe.contains("PerfMainTraceLine.during(trace, startMs: stall.startMs, gapMs: stall.gapMs)"))
        let support = try read("UITests/JourneyPhotoUITests/PerfSurveySupport.swift")
        XCTAssertTrue(support.contains("if field.hasPrefix(\"t=\") { t = Int(field.dropFirst(2)) }"), "読む側が t= を読んでいない")
        XCTAssertTrue(support.contains("stalls = inside"))
        // 印は読む側の種類分けと同じ（片方だけ変えない）
        for marker in PerfMainTrace.markers { XCTAssertTrue(support.contains("\"\(marker)\""), "\(marker) を読む側が知らない") }
    }

    /// 🔴 下調べの写真詳細の段は、画面の中で押せる写真のうち一番上を押す（木の順の 1 つ目ではない・Mac の回 1256）。
    /// 押せる札が無いときは、落とす前に事実（位置・上端・札の並び・画面の木）を残す（回 1255）
    func testUsageSurveyTapsTheTopmostHittableHomePhoto() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let probe = try String(contentsOf: root.appendingPathComponent("UITests/JourneyPhotoUITests/PerformanceTests.swift"), encoding: .utf8)
        let begin = try XCTUnwrap(probe.range(of: "// 3. 写真詳細を開いて戻る × 3"))
        let end = try XCTUnwrap(probe.range(of: "finish(\"photoDetailOpenBack3\")"))
        let stage = String(probe[begin.upperBound..<end.lowerBound])
        XCTAssertTrue(stage.contains("let target = topmostHittableFeedPhoto(app)"), "押す写真を位置で選んでいない")
        XCTAssertTrue(stage.contains("target.tap()"))
        XCTAssertFalse(stage.contains("photo.tap()"), "木の順の 1 つ目（firstMatch）を押している")
        let note = try XCTUnwrap(stage.range(of: "if target == nil { noteUnhittableHomePhoto(app, photo, round: round) }"), "押せないときの記録が無い")
        let fail = try XCTUnwrap(stage.range(of: "XCTFail(\"\\(round) 回目: ホームの画面の中に押せる写真が無い\")"))
        XCTAssertLessThan(note.lowerBound, fail.lowerBound, "落とす前に記録する")
        // 選び方: 押せるもののうち、上（同じ高さなら左）
        XCTAssertTrue(probe.contains(".filter { $0.isHittable }"))
        XCTAssertTrue(probe.contains("return fa.minY != fb.minY ? fa.minY < fb.minY : fa.minX < fb.minX"))
        XCTAssertTrue(probe.contains("app.launchArguments += [\"-JPPreviewFeedProbe\", \"YES\"]"), "上端（home.feed.probe）を出していない")
    }

    /// 🔴 写真詳細のメモリの試験も、画面の中で押せる写真のうち一番上を毎回選んで押す（木の順の 1 つ目ではない・Mac の回 1256）
    func testPhotoDetailMemoryTapsTheTopmostHittableHomePhoto() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let probe = try String(contentsOf: root.appendingPathComponent("UITests/JourneyPhotoUITests/PerformanceTests.swift"), encoding: .utf8)
        let begin = try XCTUnwrap(probe.range(of: "func testPhotoDetailMemory() {"))
        let body = String(probe[begin.upperBound...].prefix(1600))
        let measure = try XCTUnwrap(body.range(of: "measureTimed([XCTMemoryMetric(application: app)], 3) {"))
        let pick = try XCTUnwrap(body.range(of: "let target = topmostHittableFeedPhoto(app)"), "押す写真を位置で選んでいない")
        XCTAssertLessThan(measure.lowerBound, pick.lowerBound, "1 回ごとに選び直していない")
        XCTAssertTrue(body.contains("target.tap()"))
        XCTAssertFalse(body.contains("photo.tap()"), "木の順の 1 つ目（firstMatch）を押している")
        XCTAssertFalse(body.contains("photo.isHittable"), "木の順の 1 つ目が押せるかで確かめている")
        let note = try XCTUnwrap(body.range(of: "if target == nil { noteUnhittableHomePhoto(app, photo, round: round) }"))
        let fail = try XCTUnwrap(body.range(of: "XCTFail(\"\\(round) 回目: ホームの画面の中に押せる写真が無い\")"))
        XCTAssertLessThan(note.lowerBound, fail.lowerBound, "落とす前に記録する")
    }
}

