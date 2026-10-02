import XCTest
@testable import JourneyPhoto

/// SNS に渡す画像の透かし（`Watermark`）
final class WatermarkTests: XCTestCase {

    /// 字の大きさは短い辺の割合。小さい写真でも下限で読める
    func testFontSizeFollowsShortSide() {
        XCTAssertEqual(Watermark.fontSize(canvas: CGSize(width: 1920, height: 1080)), 1080 * Watermark.scale, accuracy: 1e-9)
        XCTAssertEqual(Watermark.fontSize(canvas: CGSize(width: 1080, height: 1920)), 1080 * Watermark.scale, accuracy: 1e-9)
        XCTAssertEqual(Watermark.fontSize(canvas: CGSize(width: 200, height: 150)), Watermark.minFontSize)
    }

    /// 長い辺が上限を超えるときだけ縮める（縦横比は保つ）
    func testOutputSizeCapsLongSide() {
        XCTAssertEqual(Watermark.outputSize(image: CGSize(width: 4096, height: 3072)), CGSize(width: 2048, height: 1536))
        XCTAssertEqual(Watermark.outputSize(image: CGSize(width: 1080, height: 1350)), CGSize(width: 1080, height: 1350))
    }

    /// 右下に余白をとって置く
    func testOriginIsBottomRight() {
        let origin = Watermark.origin(text: CGSize(width: 200, height: 40), canvas: CGSize(width: 1000, height: 800), margin: 30)
        XCTAssertEqual(origin, CGPoint(x: 770, y: 730))
    }
}
