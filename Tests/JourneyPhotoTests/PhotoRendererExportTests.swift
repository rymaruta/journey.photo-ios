import XCTest
@testable import JourneyPhoto

// **本物の Core Image / ImageIO でしか意味が無い試験。** Linux の模型は何も描かない
// （`Shims/CoreImage`）ので、Darwin でだけ組む。Mac のワークフローのテスト段
// （シミュレータ）で走る。
#if canImport(Darwin)
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// 写真の編集の書き出し: EXIF / GPS が無い・最大辺 1920 以下・ICC が付く・元の色空間を保つ
final class PhotoRendererExportTests: XCTestCase {

    /// 撮影情報（GPS・撮影日時・機種）入りの JPEG を作る
    private func makeJPEG(width: Int, height: Int, colorSpaceName: CFString) throws -> Data {
        let space = try XCTUnwrap(CGColorSpace(name: colorSpaceName))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 35.6812, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 139.7671, kCGImagePropertyGPSLongitudeRef: "E",
            ] as [CFString: Any],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:09:13 08:21:05",
            ] as [CFString: Any],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone 15 Pro",
            ] as [CFString: Any],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func properties(of data: Data) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    private let recipe = PhotoRecipe(exposure: 0.4, contrast: 0.3, temperature: 0.5, highlights: 0.4,
                                     shadows: 0.3, preset: .init(id: "dusk", strength: 0.7))

    func testSourceReallyHasMetadata() throws {
        let original = try properties(of: makeJPEG(width: 64, height: 48, colorSpaceName: CGColorSpace.sRGB))
        XCTAssertNotNil(original[kCGImagePropertyGPSDictionary], "元に GPS が無いと、下の試験が何も見ていない")
    }

    func testExportStripsMetadataAndFitsIn1920() throws {
        let data = try makeJPEG(width: 4000, height: 3000, colorSpaceName: CGColorSpace.sRGB)
        let exported = try PhotoRenderer.shared.export(data: data, recipe: recipe)
        let props = try properties(of: exported)
        XCTAssertNil(props[kCGImagePropertyGPSDictionary], "GPS が残っていない")
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        XCTAssertNil(exif[kCGImagePropertyExifDateTimeOriginal])
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        XCTAssertNil(tiff[kCGImagePropertyTIFFModel])
        let width = try XCTUnwrap(props[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(props[kCGImagePropertyPixelHeight] as? Int)
        XCTAssertEqual(max(width, height), 1920)
        XCTAssertLessThanOrEqual(abs(width * 3 - height * 4), 8, "縦横比を保つ")
    }

    func testExportKeepsDisplayP3WithICC() throws {
        let data = try makeJPEG(width: 800, height: 600, colorSpaceName: CGColorSpace.displayP3)
        let props = try properties(of: PhotoRenderer.shared.export(data: data, recipe: recipe))
        let profile = try XCTUnwrap(props[kCGImagePropertyProfileName] as? String, "ICC が付く")
        XCTAssertTrue(profile.contains("P3"), profile)
    }

    func testExportOfSRGBStaysSRGBWithICC() throws {
        let data = try makeJPEG(width: 800, height: 600, colorSpaceName: CGColorSpace.sRGB)
        let props = try properties(of: PhotoRenderer.shared.export(data: data, recipe: recipe))
        let profile = try XCTUnwrap(props[kCGImagePropertyProfileName] as? String, "ICC が付く")
        XCTAssertTrue(profile.contains("sRGB"), profile)
    }

    func testEveryPlannedFilterExists() {
        let steps = PhotoRecipePlan.steps(for: PhotoRecipe(exposure: 1, contrast: 1, saturation: 1, temperature: 1,
                                                           highlights: -1, shadows: 1,
                                                           preset: .init(id: "haze")))
        XCTAssertEqual(steps.count, 5)
        for step in steps {
            let filter = CIFilter(name: step.filter)
            XCTAssertNotNil(filter, step.filter)
            for key in step.parameters.keys {
                XCTAssertTrue(filter?.inputKeys.contains(key) ?? false, "\(step.filter).\(key)")
            }
        }
    }

    func testPreviewRendersAtLoadedSize() throws {
        let data = try makeJPEG(width: 3000, height: 2000, colorSpaceName: CGColorSpace.sRGB)
        let loaded = try XCTUnwrap(PhotoRenderer.load(data: data, maxPixelSize: 600))
        let image = try XCTUnwrap(PhotoRenderer.shared.preview(recipe, loaded: loaded))
        XCTAssertEqual(max(image.width, image.height), 600)
    }
}
#endif
