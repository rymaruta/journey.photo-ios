import XCTest
@testable import JourneyPhoto
#if os(iOS)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#endif

/// **GPS の関所（`ImagePreparer`）を本物の ImageIO で通す。**
///
/// 🔴 **Mac の `xcodebuild test`（シミュレータ）でだけ走る。** Linux の `swift test` は模型の
/// ImageIO（何も読めない）に向けて組むので、ここは `XCTSkip` で飛ばす——Linux が緑でも、
/// この関所は確かめていない。
///
/// 試験の中で GPS・撮影日時・機種・シリアル番号入りの JPEG を作り（`CGImageDestination`）、
/// 出力にそれらが残らないこと・座標が約1kmに丸められること・長い辺が 1920 になることを見る
final class ImagePreparerDeviceTests: XCTestCase {

    private static let skipReason = "本物の ImageIO が要る（Mac の xcodebuild test でだけ走る）"

    func testPrepareStripsLocationDateAndCameraAndShrinks() throws {
        #if os(iOS)
        let original = try Self.makeJPEG(width: 3000, height: 2000, properties: [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 35.681236,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 139.767125,
                kCGImagePropertyGPSLongitudeRef: "E",
            ] as [CFString: Any],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:09:13 08:21:05",
                kCGImagePropertyExifBodySerialNumber: "SN-0123456789",
                kCGImagePropertyExifLensModel: "iPhone 15 Pro back camera 6.86mm f/1.78",
            ] as [CFString: Any],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Apple",
                kCGImagePropertyTIFFModel: "iPhone 15 Pro",
            ] as [CFString: Any],
        ])
        // 前提: 入力には入っている（入っていなければ、この試験は何も確かめていない）
        let input = try Self.properties(of: original)
        XCTAssertNotNil(input[kCGImagePropertyGPSDictionary], "前提: 入力に GPS が無い")
        XCTAssertNotNil((input[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel],
                        "前提: 入力に機種が無い")

        let prepared = try ImagePreparer.prepare(data: original, fileName: "IMG_0001.HEIC")

        // 読み取ったもの（送る値）。座標は約1kmに丸めたものだけ
        XCTAssertEqual(prepared.coords, Photo.Coords(lat: 35.68, lng: 139.77))
        XCTAssertEqual(prepared.takenOn, "2026-09-13")
        XCTAssertEqual(prepared.exif?.camera, "Apple iPhone 15 Pro")
        XCTAssertEqual(prepared.exif?.dateTimeOriginal, "2026-09-13T08:21:05")
        XCTAssertEqual(prepared.fileName, "IMG_0001.jpg")
        XCTAssertEqual(prepared.contentType, "image/jpeg")

        // 上げる本体には残っていない
        let output = try Self.properties(of: prepared.data)
        XCTAssertNil(output[kCGImagePropertyGPSDictionary], "GPS が残っている")
        let exif = output[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        XCTAssertNil(exif[kCGImagePropertyExifDateTimeOriginal], "撮影日時が残っている")
        XCTAssertNil(exif[kCGImagePropertyExifBodySerialNumber], "本体のシリアル番号が残っている")
        XCTAssertNil(exif[kCGImagePropertyExifLensModel], "レンズ名が残っている")
        let tiff = output[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        XCTAssertNil(tiff[kCGImagePropertyTIFFMake], "メーカーが残っている")
        XCTAssertNil(tiff[kCGImagePropertyTIFFModel], "機種が残っている")
        // XMP の側にも無い
        let source = try XCTUnwrap(CGImageSourceCreateWithData(prepared.data as CFData, nil))
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
            for path in ["exif:GPSLatitude", "exif:GPSLongitude", "exif:DateTimeOriginal", "tiff:Make", "tiff:Model"] {
                XCTAssertNil(CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString), "XMP に \(path) が残っている")
            }
        }

        // 長い辺は 1920 に収める（縦横比は保つ）
        let width = try XCTUnwrap(output[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(output[kCGImagePropertyPixelHeight] as? Int)
        XCTAssertEqual(max(width, height), ImagePreparer.maxPixelSize)
        XCTAssertEqual(Double(width) / Double(height), 1.5, accuracy: 0.01)
        #else
        throw XCTSkip(Self.skipReason)
        #endif
    }

    /// 🔴 **XMP にだけ残った撮影地も止める**（`assertStripped`）。EXIF・GPS・TIFF の辞書だけを
    /// 見ていた頃は、XMP の包みに入った市名をそのまま上げる形だった
    func testAssertStrippedCatchesLocationLeftOnlyInXMP() throws {
        #if os(iOS)
        let metadata = CGImageMetadataCreateMutable()
        XCTAssertTrue(CGImageMetadataSetValueWithPath(metadata, nil, "photoshop:City" as CFString, "Kyoto" as CFString),
                      "前提: XMP を書けない")
        let jpeg = try Self.makeJPEG(width: 64, height: 64, xmp: metadata)
        // 前提: GPS の辞書には何も無い（XMP にだけある）
        XCTAssertNil(try Self.properties(of: jpeg)[kCGImagePropertyGPSDictionary])

        XCTAssertThrowsError(try ImagePreparer.assertStripped(jpeg), "XMP の市名を素通しした") { error in
            guard case .metadataRemains? = error as? ImagePreparer.PrepareError else {
                return XCTFail("形が違う: \(error)")
            }
        }
        // 整えた出力は通る（焼き直しは XMP を引き継がない）
        let prepared = try ImagePreparer.prepare(data: jpeg, fileName: "x.jpg")
        XCTAssertNoThrow(try ImagePreparer.assertStripped(prepared.data))
        #else
        throw XCTSkip(Self.skipReason)
        #endif
    }

    #if os(iOS)
    /// 一色の画像を JPEG にする。`properties` は EXIF・GPS・TIFF の辞書、`xmp` は XMP の包み
    private static func makeJPEG(width: Int, height: Int, properties: [CFString: Any] = [:],
                                 xmp: CGMutableImageMetadata? = nil) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: 0.79, green: 0.65, blue: 0.42, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil))
        if let xmp {
            CGImageDestinationAddImageAndMetadata(destination, image, xmp, nil)
        } else {
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private static func properties(of data: Data) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }
    #endif
}
