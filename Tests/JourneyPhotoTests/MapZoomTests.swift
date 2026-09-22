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
