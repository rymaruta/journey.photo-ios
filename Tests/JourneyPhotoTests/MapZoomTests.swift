import XCTest
@testable import JourneyPhoto

/// 地図の拡大・縮小（モック3-4）と分類チップの記号（モック3-1）。
final class MapZoomTests: XCTestCase {

    private let frame = MapFraming.Frame(latitude: 35.0, longitude: 135.0,
                                         latitudeSpan: 1.0, longitudeSpan: 1.0)

    func testZoomInHalvesTheSpan() {
        let z = MapFraming.zoomed(frame, by: 1 / MapFraming.zoomStep)
        XCTAssertEqual(z.latitudeSpan, 0.5, accuracy: 0.0001)
        XCTAssertEqual(z.longitudeSpan, 0.5, accuracy: 0.0001)
        // 中心は動かさない（押すたびに流れていかない）
        XCTAssertEqual(z.latitude, frame.latitude)
    }

    /// 🔴 **押し続けても1点にならない。** 止めないと戻れなくなる
    func testZoomInStopsAtTheFloor() {
        var f = frame
        for _ in 0..<40 { f = MapFraming.zoomed(f, by: 1 / MapFraming.zoomStep) }
        XCTAssertEqual(f.latitudeSpan, MapFraming.minSpan, accuracy: 0.00001)
        XCTAssertGreaterThan(f.latitudeSpan, 0)
    }

    /// 🔴 **押し続けても地球儀にならない**
    func testZoomOutStopsAtTheCeiling() {
        var f = frame
        for _ in 0..<40 { f = MapFraming.zoomed(f, by: MapFraming.zoomStep) }
        XCTAssertEqual(f.latitudeSpan, MapFraming.maxSpan, accuracy: 0.00001)
        XCTAssertLessThan(f.latitudeSpan, 180)
    }

    // MARK: - 続けて押したとき（`ZoomChain`）

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// 🔴 **2回押したら2段寄る。** 地図が落ち着く前（見えている枠が
    /// まだ古い）に2回目を押しても、1回目に頼んだ枠から数える
    func testTwoQuickZoomInsGoTwoSteps() {
        var chain = MapFraming.ZoomChain()
        _ = chain.step(from: frame, by: 1 / MapFraming.zoomStep, now: t0)
        let second = chain.step(from: frame, by: 1 / MapFraming.zoomStep,
                                now: t0.addingTimeInterval(0.2))
        XCTAssertEqual(second?.latitudeSpan ?? 0, 0.25, accuracy: 0.0001)
    }

    /// 🔴 **＋のすぐ後の−は元に戻る。** 古い枠から数えると元の2倍へ飛び、
    /// 押す前より引いた所に出る（逆に動いたように見える）
    func testZoomInThenOutReturnsToTheStart() {
        var chain = MapFraming.ZoomChain()
        _ = chain.step(from: frame, by: 1 / MapFraming.zoomStep, now: t0)
        let back = chain.step(from: frame, by: MapFraming.zoomStep,
                              now: t0.addingTimeInterval(0.3))
        XCTAssertEqual(back?.latitudeSpan ?? 0, 1.0, accuracy: 0.0001)
    }

    /// **間を空けたら見えている枠に従う**（指で動かした地図を無視しない）
    func testAfterAPauseTheVisibleFrameWins() {
        var chain = MapFraming.ZoomChain()
        _ = chain.step(from: frame, by: 1 / MapFraming.zoomStep, now: t0)
        let moved = MapFraming.Frame(latitude: 43.0, longitude: 141.0,
                                     latitudeSpan: 4.0, longitudeSpan: 4.0)
        let next = chain.step(from: moved, by: 1 / MapFraming.zoomStep,
                              now: t0.addingTimeInterval(MapFraming.ZoomChain.window + 0.1))
        XCTAssertEqual(next?.latitude, 43.0)
        XCTAssertEqual(next?.latitudeSpan ?? 0, 2.0, accuracy: 0.0001)
    }

    /// 見えている枠がまだ無い（地図が一度も落ち着いていない）なら動かさない
    func testNothingToZoomFromMeansNoMove() {
        var chain = MapFraming.ZoomChain()
        XCTAssertNil(chain.step(from: nil, by: MapFraming.zoomStep, now: t0))
    }

    /// **知らない分類に記号を当てない**（分類と絵が食い違うチップを並べない）
    func testUnknownCategoryHasNoSymbol() {
        XCTAssertNil(CategoryChoices.symbol("ぜんぜん知らない分類"))
        XCTAssertNil(CategoryChoices.symbol(""))
    }

    /// 持っている分類には全部ある（1つだけ記号の無いチップを作らない）
    func testEveryKnownCategoryHasASymbol() {
        for category in CategoryChoices.all {
            XCTAssertNotNil(CategoryChoices.symbol(category), category)
        }
    }
}
