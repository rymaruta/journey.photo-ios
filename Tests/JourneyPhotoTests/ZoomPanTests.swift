import XCTest
@testable import JourneyPhoto

/// 写真を大きく見る画面の拡大と移動（2026-09-30 のレビュー: ピンチを離すと 1 倍に戻る・
/// 拡大したまま動かせない）
final class ZoomPanTests: XCTestCase {
    /// 縦の画面（390×800）に、横長の写真（収めると 390×260）
    private let screen = CGSize(width: 390, height: 800)
    private let landscape = CGSize(width: 390, height: 260)

    /// 🔴 離しても倍率を保つ（以前は `onEnded { scale = 1 }`）
    func testPinchKeepsTheScaleAfterRelease() {
        var z = ZoomPan()
        z.endPinch(2, container: screen, content: landscape)
        XCTAssertEqual(z.scale, 2)
        XCTAssertTrue(z.isZoomed)
        // 続けてつまむと掛け算で積もる
        z.endPinch(1.5, container: screen, content: landscape)
        XCTAssertEqual(z.scale, 3)
    }

    func testScaleIsClampedBetweenOneAndFour() {
        var z = ZoomPan()
        z.endPinch(10, container: screen, content: landscape)
        XCTAssertEqual(z.scale, ZoomPan.maxScale)
        XCTAssertEqual(z.liveScale(pinch: 0.1), 1)
        XCTAssertEqual(ZoomPan.clampScale(.nan), 1)
    }

    /// 1.05 倍未満まで戻したら 1 倍・中央へ（中途半端に拡大したまま残さない）
    func testNearlyOneSnapsBackToOneAndCenters() {
        var z = ZoomPan()
        z.endPinch(3, container: screen, content: landscape)
        z.endDrag(CGSize(width: 200, height: 0), container: screen, content: landscape)
        XCTAssertNotEqual(z.offset, .zero)
        z.endPinch(1.02 / 3, container: screen, content: landscape)
        XCTAssertEqual(z.scale, 1)
        XCTAssertEqual(z.offset, .zero)
        XCTAssertFalse(z.isZoomed)
    }

    /// 🔴 拡大したまま動かせる。**はみ出している分だけ**（写真の端が画面の内側へ入り込まない）
    func testDragIsLimitedToTheOverflow() {
        var z = ZoomPan()
        z.endPinch(2, container: screen, content: landscape)
        // 横: 390×2=780 → はみ出しは片側 195。縦: 260×2=520 < 800 → 動かない
        z.endDrag(CGSize(width: 1_000, height: 1_000), container: screen, content: landscape)
        XCTAssertEqual(z.offset.width, 195, accuracy: 0.001)
        XCTAssertEqual(z.offset.height, 0, accuracy: 0.001)
        z.endDrag(CGSize(width: -2_000, height: -50), container: screen, content: landscape)
        XCTAssertEqual(z.offset.width, -195, accuracy: 0.001)
        XCTAssertEqual(z.offset.height, 0, accuracy: 0.001)
    }

    /// 動かしたあと縮めたら、位置をその倍率の範囲へ収め直す（端が内側へ入らない）
    func testZoomingOutReclampsTheOffset() {
        var z = ZoomPan()
        z.endPinch(4, container: screen, content: landscape)
        z.endDrag(CGSize(width: 1_000, height: 0), container: screen, content: landscape)
        XCTAssertEqual(z.offset.width, 585, accuracy: 0.001)   // (1560-390)/2
        z.endPinch(0.5, container: screen, content: landscape)  // → 2 倍
        XCTAssertEqual(z.offset.width, 195, accuracy: 0.001)
    }

    /// 等倍のときは動かさない（横スワイプは写真の送りに渡す）
    func testDragDoesNothingAtOneTimes() {
        var z = ZoomPan()
        z.endDrag(CGSize(width: 300, height: 0), container: screen, content: landscape)
        XCTAssertEqual(z.offset, .zero)
    }

    /// 写真の大きさが測れていなければ画面の大きさで代える
    func testUnknownContentFallsBackToContainer() {
        let o = ZoomPan.clampOffset(CGSize(width: 1_000, height: 1_000), scale: 2, container: screen, content: .zero)
        XCTAssertEqual(o.width, 195, accuracy: 0.001)
        XCTAssertEqual(o.height, 400, accuracy: 0.001)
    }

    func testResetReturnsToOneTimesAndCenter() {
        var z = ZoomPan()
        z.endPinch(3, container: screen, content: landscape)
        z.endDrag(CGSize(width: 100, height: 0), container: screen, content: landscape)
        z.reset()
        XCTAssertEqual(z, ZoomPan())
    }
}
