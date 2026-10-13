import XCTest
@testable import JourneyPhoto
#if os(iOS)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#endif

final class ReferencePhotoLoaderDeviceTests: XCTestCase {
    func testLargeRotatedPhotoIsDownsampledAndUpright() throws {
        #if os(iOS)
        let width = 3000, height = 2000
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
                                             bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let input = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            input as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let output = try ReferencePhotoLoader.previewJPEG(from: input as Data)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(output as CFData, nil))
        let preview = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertLessThanOrEqual(max(preview.width, preview.height), ReferencePhotoLoader.maxPixelSize)
        XCTAssertLessThan(preview.width, preview.height, "EXIF の90°回転を画素に反映していない")
        #else
        throw XCTSkip("ImageIO の実画像変換は iOS シミュレータで検証する")
        #endif
    }

    func testInvalidImageIsRejected() {
        XCTAssertThrowsError(try ReferencePhotoLoader.previewJPEG(from: Data([0, 1, 2])))
    }
}
