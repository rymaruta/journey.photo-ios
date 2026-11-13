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

    /// 積みの見本は**新しい方から** 12 件。段は浅い方の 2 段とこのアプリの段だけ。区切りの字は値に入れない
    func testKeepsNewestSamplesWithAppFrames() {
        let box = Box()
        let tl = timeline(box)
        for i in 0..<15 {
            box.now = 1000 + Double(i)
            tl.recordSample(frames: ["libA`top\(i)", "SwiftUI`x", "SwiftUI`y", "JourneyPhoto.debug.dylib`Foo;bar^[1]"])
        }
        let rs = section(tl.summary(), "rs")
        XCTAssertTrue(rs.hasPrefix("[+3000 libA`top3^SwiftUI`x^JourneyPhoto.debug.dylib`Foo_bar__1_;"), rs)
        XCTAssertTrue(rs.hasSuffix("+14000 libA`top14^SwiftUI`x^JourneyPhoto.debug.dylib`Foo_bar__1_]"), rs)
        XCTAssertEqual(rs.components(separatedBy: ";").count, PerfTimeline.sampleCap)
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
        XCTAssertEqual(tl.summary(), "t=2000 | st=[] | mem=[] | cnt=[] | rs=[]")
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
}
