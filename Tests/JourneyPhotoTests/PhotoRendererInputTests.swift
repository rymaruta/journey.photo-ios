import XCTest
import ImageIO
@testable import JourneyPhoto

/// 写真の編集の入口のうち、Linux でも見られるもの: 縮めて読む指定・プレビューの大きさ・
/// 書き出しが関所（`assertStripped`）を通ること
final class PhotoRendererInputTests: XCTestCase {

    func testDownsampleDecodesHDRToSDR() {
        let options = ImagePreparer.downsampleOptions(maxPixelSize: 1920)
        XCTAssertEqual(options[kCGImageSourceDecodeRequest] as? String, kCGImageSourceDecodeToSDR as String,
                       "HDR のまま 8bit に焼くと明るい所が飛ぶ")
        XCTAssertEqual(options[kCGImageSourceThumbnailMaxPixelSize] as? Int, 1920)
        XCTAssertEqual(options[kCGImageSourceCreateThumbnailWithTransform] as? Bool, true)
        XCTAssertEqual(options[kCGImageSourceCreateThumbnailFromImageAlways] as? Bool, true)
    }

    /// 関所が呼ばれていること。**撮影情報を消せたと確かめられない出力は返さない**
    /// （Linux の模型では読み直しができないので encodeFailed、Mac では読めない JPEG として投げる）
    func testEncodeStrippedRunsTheCheck() {
        XCTAssertThrowsError(try ImagePreparer.encodeStripped(anyImage(), encode: { _ in Data("not a jpeg".utf8) }))
    }

    func testPreviewSizeIsLongSideOfFittedImage() {
        let box = CGSize(width: 390, height: 600)
        // 縦長の写真（3:4）: 幅 390 で決まる → 長い辺（高さ）520pt × 3。枠の幅（390）で読むと縦が足りない
        XCTAssertEqual(PhotoRenderer.previewPixelSize(box: box, scale: 3, imageSize: CGSize(width: 3000, height: 4000)), 1560)
        // もっと縦長（1:2）: 高さ 600 で決まる → 600pt × 3
        XCTAssertEqual(PhotoRenderer.previewPixelSize(box: box, scale: 3, imageSize: CGSize(width: 2000, height: 4000)), 1800)
        // 横長の写真（4:3）: 幅 390 に合わせる → 長い辺 390pt × 3
        XCTAssertEqual(PhotoRenderer.previewPixelSize(box: box, scale: 3, imageSize: CGSize(width: 4000, height: 3000)), 1170)
        // 写真の比が分からなければ枠の長い辺（どの比でも足りる）
        XCTAssertEqual(PhotoRenderer.previewPixelSize(box: box, scale: 2), 1200)
        XCTAssertNil(PhotoRenderer.previewPixelSize(box: .zero, scale: 3))
        XCTAssertNil(PhotoRenderer.previewPixelSize(box: box, scale: .nan))
        XCTAssertEqual(PhotoRenderer.previewPixelSize(box: box, scale: 2, imageSize: .zero), 1200, "壊れた写真の大きさは無視")
    }

    #if canImport(Darwin)
    private func anyImage() -> CGImage {
        let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }
    #else
    private func anyImage() -> CGImage { CGImage() }
    #endif
}
