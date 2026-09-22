import XCTest
@testable import JourneyPhoto

final class DominantColorTests: XCTestCase {

    private func rgba(_ pixels: [(UInt8, UInt8, UInt8, UInt8)]) -> [UInt8] {
        pixels.flatMap { [$0.0, $0.1, $0.2, $0.3] }
    }

    func testAveragesOpaquePixels() {
        let bytes = rgba([(0, 0, 0, 255), (255, 255, 255, 255)])
        XCTAssertEqual(DominantColor.hex(fromRGBA: bytes), "#808080")
    }

    /// ほぼ透明の画素は数えない（Web と同じ線）
    func testSkipsNearlyTransparentPixels() {
        let bytes = rgba([(255, 0, 0, 255), (0, 0, 255, 8)])
        XCTAssertEqual(DominantColor.hex(fromRGBA: bytes), "#ff0000")
    }

    /// 数えられる画素が無ければ **nil**（真っ白を返さない）
    func testReturnsNilWhenEverythingIsTransparent() {
        XCTAssertNil(DominantColor.hex(fromRGBA: rgba([(9, 9, 9, 0), (9, 9, 9, 31)])))
        XCTAssertNil(DominantColor.hex(fromRGBA: []))
    }

    /// 端数のバイト列で落ちない（最後の欠けた画素は読まない）
    func testIgnoresATrailingPartialPixel() {
        XCTAssertEqual(DominantColor.hex(fromRGBA: [10, 20, 30, 255, 99]), "#0a141e")
    }

    /// 桁は必ず2つ（`#a1b2c3` の形）
    func testPadsSingleDigits() {
        XCTAssertEqual(DominantColor.hex(fromRGBA: rgba([(1, 2, 3, 255)])), "#010203")
    }
}
