import XCTest
@testable import JourneyPhoto

/// とおまわり号の描画の計測（2026-10-31・#430）。UI テスト（`ScreenshotTests.testMeasuresCamperRender…`）が読む字の形と、
/// 数えない起動では何も数えないこと
final class CamperRenderMeterTests: XCTestCase {

    func testSummaryIsParseableAndCountsSlowFrames() {
        let m = CamperRenderMeter(enabled: true)
        m.add("CamperRoomFrame", nanos: 5_000_000)
        m.add("CamperRoomFrame", nanos: 20_000_000)
        m.add("CamperRoomUpdate", nanos: 1_000_000)
        let t = m.tally("CamperRoomFrame")
        XCTAssertEqual(t.count, 2)
        XCTAssertEqual(t.nanos, 25_000_000)
        XCTAssertEqual(t.maxNanos, 20_000_000)
        XCTAssertEqual(t.slow, 1, "16.7 ms を越えたコマだけを遅いコマに数える")
        let summary = m.summary()
        XCTAssertTrue(summary.hasPrefix("CamperRoomFrame n=2 ms=25.00 max=20.00 slow=1; CamperRoomUpdate n=1 ms=1.00 max=1.00 slow=0;"), summary)
        // 端末（iOS）ではアプリ全体の CPU とメモリが終わりに付く（Linux の模型には無い・Mac run 794）
        if CamperRenderMeter.processUsage() != nil {
            XCTAssertTrue(summary.contains(" Process cpu_ms="), summary)
            XCTAssertTrue(summary.hasSuffix(";"), summary)
        }
    }

    func testDisabledMeterCountsNothing() {
        let m = CamperRenderMeter(enabled: false)
        m.add("CamperRoomFrame", nanos: 5_000_000)
        CamperRenderMark.measure("CamperRoomUpdate", meter: m) {}
        CamperRenderMark.count("CamperRoomKick", meter: m)
        XCTAssertEqual(m.summary(), "")
    }

    func testMarkMeasuresAndCounts() {
        let m = CamperRenderMeter(enabled: true)
        let v = CamperRenderMark.measure("CamperRoomUpdate", meter: m) { 42 }
        XCTAssertEqual(v, 42)
        CamperRenderMark.count("CamperRoomKick", meter: m)
        CamperRenderMark.count("CamperRoomKick", meter: m)
        XCTAssertEqual(m.tally("CamperRoomUpdate").count, 1)
        XCTAssertEqual(m.tally("CamperRoomKick").count, 2)
        XCTAssertEqual(m.tally("CamperRoomKick").nanos, 0)
    }

    #if canImport(SceneKit) || canImport(SceneKitShim)
    /// 1 コマは始まりと終わりの組で 1 回。始まりの無い終わり（delegate を付けた直後など）は数えない
    func testFrameMeterPairsBeginAndEnd() {
        let m = CamperRenderMeter(enabled: true)
        let f = CamperFrameMeter("CamperRoomFrame", meter: m)
        f.end()
        XCTAssertEqual(m.tally("CamperRoomFrame").count, 0)
        f.begin()
        f.end()
        f.begin()
        f.end()
        XCTAssertEqual(m.tally("CamperRoomFrame").count, 2)
    }
    #endif
}
