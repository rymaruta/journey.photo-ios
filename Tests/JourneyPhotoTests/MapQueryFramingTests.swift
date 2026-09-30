import XCTest
@testable import JourneyPhoto

/// 探すから語を受け取った地図の寄せ方（`MapQueryFraming`）
final class MapQueryFramingTests: XCTestCase {

    private let kyoto = MapFraming.Frame(latitude: 35.0, longitude: 135.7, latitudeSpan: 0.2, longitudeSpan: 0.2)

    /// 受け取った時点で枠が無ければ待ち、決まった時点で一度だけ寄せる
    func testFramesOnceWhenFrameArrives() {
        var framing = MapQueryFraming()
        framing.received(query: "京都")
        XCTAssertNil(framing.frameIfReady(nil, settled: false))
        XCTAssertEqual(framing.frameIfReady(kyoto, settled: true), kyoto)
        XCTAssertNil(framing.frameIfReady(kyoto, settled: true))
    }

    /// 受け取っていなければ寄せない（普通に開いた地図を動かさない）
    func testDoesNothingWithoutQuery() {
        var framing = MapQueryFraming()
        XCTAssertNil(framing.frameIfReady(kyoto, settled: true))
        XCTAssertTrue(framing.followsLocation(requestedByUser: false))
    }

    /// 初めて開いた回の自動の現在地は、語の寄せを上書きしない。ボタンで取った現在地は寄せる
    func testAutoLocateDoesNotOverrideQuery() {
        var framing = MapQueryFraming()
        framing.received(query: "京都")
        XCTAssertFalse(framing.followsLocation(requestedByUser: false))
        XCTAssertEqual(framing.frameIfReady(kyoto, settled: true), kyoto)
        XCTAssertFalse(framing.followsLocation(requestedByUser: false))

        XCTAssertTrue(framing.followsLocation(requestedByUser: true))
        XCTAssertTrue(framing.followsLocation(requestedByUser: false))
    }

    /// ボタンで現在地へ寄せたあと・指で動かしたあとは、語の当たりへ引き戻さない
    func testUserActionCancelsPendingFrame() {
        var located = MapQueryFraming()
        located.received(query: "京都")
        _ = located.followsLocation(requestedByUser: true)
        XCTAssertNil(located.frameIfReady(kyoto, settled: true))

        var moved = MapQueryFraming()
        moved.received(query: "京都")
        moved.userMovedCamera()
        XCTAssertNil(moved.frameIfReady(kyoto, settled: true))
    }

    /// 写真も索引も取り終えて何にも当たらなかったら、印を両方下ろす
    /// （あとで急に寄らない・自動の現在地も抑えない）。取り終える前は待ち続ける
    func testNothingMatchedLowersBothMarks() {
        var framing = MapQueryFraming()
        framing.received(query: "京都")
        XCTAssertNil(framing.frameIfReady(nil, settled: false))
        XCTAssertTrue(framing.waitingToFrame)
        XCTAssertFalse(framing.followsLocation(requestedByUser: false))

        XCTAssertNil(framing.frameIfReady(nil, settled: true))
        XCTAssertFalse(framing.waitingToFrame)
        XCTAssertFalse(framing.holdsAgainstAutoLocate)
        XCTAssertTrue(framing.followsLocation(requestedByUser: false))
        XCTAssertNil(framing.frameIfReady(kyoto, settled: true))
    }

    /// 前の語の寄せ待ちの間に空の語が来たら、印を両方下ろす（写真全体の枠へ寄らない）
    func testEmptyQueryClearsPendingFrame() {
        var framing = MapQueryFraming()
        framing.received(query: "京都")
        framing.received(query: "")
        XCTAssertNil(framing.frameIfReady(kyoto, settled: true))
        XCTAssertTrue(framing.followsLocation(requestedByUser: false))
    }

    /// 開いたときの自動の現在地が届く前に指で動かしたら、自動の現在地へは引き戻さない。
    /// ボタンで取った現在地へは寄せる
    func testMovedCameraIsNotPulledBackByAutoLocate() {
        var framing = MapQueryFraming()
        framing.userMovedCamera()
        XCTAssertFalse(framing.followsLocation(requestedByUser: false))
        XCTAssertTrue(framing.followsLocation(requestedByUser: true))
    }
}
