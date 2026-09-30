import XCTest
@testable import JourneyPhoto

/// 探すから語を受け取った地図の寄せ方（`MapQueryFraming`）
final class MapQueryFramingTests: XCTestCase {

    private let kyoto = MapFraming.Frame(latitude: 35.0, longitude: 135.7, latitudeSpan: 0.2, longitudeSpan: 0.2)

    /// 受け取った時点で枠が無ければ待ち、決まった時点で一度だけ寄せる
    func testFramesOnceWhenFrameArrives() {
        var framing = MapQueryFraming()
        framing.received()
        XCTAssertNil(framing.frameIfReady(nil))
        XCTAssertEqual(framing.frameIfReady(kyoto), kyoto)
        XCTAssertNil(framing.frameIfReady(kyoto))
    }

    /// 受け取っていなければ寄せない（普通に開いた地図を動かさない）
    func testDoesNothingWithoutQuery() {
        var framing = MapQueryFraming()
        XCTAssertNil(framing.frameIfReady(kyoto))
        XCTAssertTrue(framing.followsLocation(requestedByUser: false))
    }

    /// 初めて開いた回の自動の現在地は、語の寄せを上書きしない。ボタンで取った現在地は寄せる
    func testAutoLocateDoesNotOverrideQuery() {
        var framing = MapQueryFraming()
        framing.received()
        XCTAssertFalse(framing.followsLocation(requestedByUser: false))
        XCTAssertEqual(framing.frameIfReady(kyoto), kyoto)
        XCTAssertFalse(framing.followsLocation(requestedByUser: false))

        XCTAssertTrue(framing.followsLocation(requestedByUser: true))
        XCTAssertTrue(framing.followsLocation(requestedByUser: false))
    }

    /// ボタンで現在地へ寄せたあと・指で動かしたあとは、語の当たりへ引き戻さない
    func testUserActionCancelsPendingFrame() {
        var located = MapQueryFraming()
        located.received()
        _ = located.followsLocation(requestedByUser: true)
        XCTAssertNil(located.frameIfReady(kyoto))

        var moved = MapQueryFraming()
        moved.received()
        moved.userMovedCamera()
        XCTAssertNil(moved.frameIfReady(kyoto))
    }
}
