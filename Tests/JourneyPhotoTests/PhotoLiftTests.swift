import XCTest
@testable import JourneyPhoto

/// ホームの写真の読み上げの操作の文（2026-11-12・札 #543・`PhotoLift`）と、つまむと地図（`PinchToMap`）。
final class PhotoLiftTests: XCTestCase {

    func testTexts() {
        XCTAssertEqual(PhotoLift.doneMessage(.save, faceName: nil), "保存しました")
        XCTAssertEqual(PhotoLift.shareText(title: "白い道", url: "https://journey-photo.com/photo/a"),
                       "白い道\nhttps://journey-photo.com/photo/a")
        XCTAssertEqual(PhotoLift.shareText(title: " ", url: "u"), "u")
    }

    // MARK: - つまむと地図

    func testPinchToMap() {
        XCTAssertEqual(PinchToMap.progress(scale: 1), 0)
        XCTAssertEqual(PinchToMap.progress(scale: 0.6), 1)
        XCTAssertEqual(PinchToMap.progress(scale: 0.8), 0.5, accuracy: 0.0001)
        XCTAssertFalse(PinchToMap.passedStep(scale: 0.9))
        XCTAssertTrue(PinchToMap.passedStep(scale: 0.84))
        // 段で離すと戻る・地図の所まで縮めて離すと地図
        XCTAssertFalse(PinchToMap.opensMap(endScale: 0.7, hasPlace: true), "段で離して地図へ行った（歯止めが無い）")
        XCTAssertTrue(PinchToMap.opensMap(endScale: 0.55, hasPlace: true))
        // 撮影地の無い写真は段で止まるだけ
        XCTAssertFalse(PinchToMap.opensMap(endScale: 0.3, hasPlace: false))
        XCTAssertEqual(PinchToMap.displayScale(scale: 0.3, hasPlace: false), PinchToMap.stepScale)
        XCTAssertEqual(PinchToMap.displayScale(scale: 0.3, hasPlace: true), PinchToMap.minDisplayScale)
        XCTAssertEqual(PinchToMap.displayScale(scale: 1.4, hasPlace: true), 1, "広げる向きで写真を大きくした")
    }
}
