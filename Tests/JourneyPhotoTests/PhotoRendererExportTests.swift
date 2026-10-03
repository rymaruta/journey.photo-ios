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
    private func makeJPEG(width: Int, height: Int, colorSpaceName: CFString, gray: Bool = false) throws -> Data {
        let space = try XCTUnwrap(CGColorSpace(name: colorSpaceName))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(gray ? CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
                                  : CGColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1))
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

    /// 投稿画面で編集した写真を送る本体（`exportPrepared`・Phase 2）: **GPS が無い・最大辺 1920**。
    /// 一覧用のサムネイルも書き出しから作り（同じ関所・512 以下）、撮影情報は原本から整えたもののまま
    func testPostedEditedBodyHasNoGPSAndFitsIn1920() throws {
        let data = try makeJPEG(width: 4032, height: 3024, colorSpaceName: CGColorSpace.displayP3)
        let base = try ImagePreparer.prepare(data: data, fileName: "photo", withThumbnail: true)
        XCTAssertNotNil(base.coords, "原本の座標（丸めたもの）を読めている")
        let sent = try PhotoRenderer.shared.exportPrepared(source: data, recipe: recipe, base: base)

        let props = try properties(of: sent.data)
        XCTAssertNil(props[kCGImagePropertyGPSDictionary], "送る本体に GPS が無い")
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        XCTAssertNil(exif[kCGImagePropertyExifDateTimeOriginal])
        let width = try XCTUnwrap(props[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(props[kCGImagePropertyPixelHeight] as? Int)
        XCTAssertEqual(max(width, height), 1920)
        XCTAssertNotEqual(sent.data, base.data, "編集が当たっている（整えた本体のままではない）")

        let thumb = try XCTUnwrap(sent.thumbnail, "一覧用のサムネイル")
        let thumbProps = try properties(of: thumb)
        XCTAssertNil(thumbProps[kCGImagePropertyGPSDictionary])
        let tw = try XCTUnwrap(thumbProps[kCGImagePropertyPixelWidth] as? Int)
        let th = try XCTUnwrap(thumbProps[kCGImagePropertyPixelHeight] as? Int)
        XCTAssertEqual(max(tw, th), ImagePreparer.thumbnailMaxPixelSize)

        XCTAssertEqual(sent.coords, base.coords, "座標は原本から")
        XCTAssertEqual(sent.takenOn, base.takenOn, "撮影日は原本から")
        XCTAssertEqual(sent.exif, base.exif, "撮影情報は原本から")
        XCTAssertNotNil(sent.dominantColor)
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

    // MARK: - 関所・色（2026-10-02 のレビュー）

    /// 撮影情報を書き込む焼き方を渡すと、関所が投げる（`encodeStripped` が読み直している）
    func testEncodeStrippedRejectsMetadata() throws {
        let data = try makeJPEG(width: 32, height: 32, colorSpaceName: CGColorSpace.sRGB)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let withGPS: (CGImage) throws -> Data = { image in
            let output = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
                output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 35.0] as [CFString: Any],
            ] as CFDictionary)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            return output as Data
        }
        XCTAssertThrowsError(try ImagePreparer.encodeStripped(image, encode: withGPS)) { error in
            guard case ImagePreparer.PrepareError.metadataRemains = error else {
                return XCTFail("\(error)")
            }
        }
    }

    /// 画像の真ん中の1画素を、`space` の値（浮動小数・拡張域あり）で読む
    private func centerPixel(_ image: CGImage, in space: CGColorSpace) throws -> [Double] {
        var pixel = [Float](repeating: 0, count: 4)
        let alpha = CGImageAlphaInfo.premultipliedLast.rawValue
        let float = CGBitmapInfo.floatComponents.rawValue
        let order = CGBitmapInfo.byteOrder32Little.rawValue
        let info = alpha | float | order
        try pixel.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1,
                                                  bitsPerComponent: 32, bytesPerRow: 16,
                                                  space: space, bitmapInfo: info))
            context.draw(image, in: CGRect(x: -CGFloat(image.width / 2), y: -CGFloat(image.height / 2),
                                           width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        return pixel.prefix(3).map(Double.init)
    }

    private func decode(_ data: Data) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// 色の曲線だけを通しても、P3 の純赤が sRGB の域に潰れない。
    /// 拡張 sRGB で読むと、域の外の色は G・B が負になる（P3 の純赤は約 −0.23 / −0.15）。
    ///
    /// **落ちたときにどの段で潰れたかが1回で分かるよう、段ごとの値を失敗の文に出す**
    /// （Mac の実行は1回1時間かかる。run 37047301740 でここが [1.06, 0.003, −0.003] で落ちた）
    func testToneCurveKeepsP3RedOutsideSRGB() throws {
        let stages = try p3RedStages()
        let report = stages.map { "\($0.name)=\($0.rgb.map { String(format: "%.3f", $0) })" }.joined(separator: " / ")
        let target = try XCTUnwrap(stages.first { $0.name.hasPrefix("3") })
        XCTAssertLessThan(min(target.rgb[1], target.rgb[2]), -0.05, "sRGB の域の外のまま。段ごと: \(report)")
    }

    /// 対照: 曲線を通さない書き出しでは、P3 の純赤が域の外に残る（読み方・書き出しの土台が
    /// 正しいことの確認。ここが落ちるなら、曲線ではなく読み方か書き出しが潰している）
    func testExportWithoutCurveKeepsP3RedOutsideSRGB() throws {
        let stages = try p3RedStages()
        let report = stages.map { "\($0.name)=\($0.rgb.map { String(format: "%.3f", $0) })" }.joined(separator: " / ")
        for prefix in ["0", "1", "2"] {
            let stage = try XCTUnwrap(stages.first { $0.name.hasPrefix(prefix) })
            XCTAssertLessThan(min(stage.rgb[1], stage.rgb[2]), -0.05, "\(stage.name)。段ごと: \(report)")
        }
    }

    /// P3 の純赤を段ごとに描いて、真ん中の画素を拡張 sRGB で読む
    private func p3RedStages() throws -> [(name: String, rgb: [Double])] {
        let data = try makeP3Red()
        let extended = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedSRGB))
        let renderer = PhotoRenderer.shared
        let curve = PhotoRecipe(highlights: 1)
        var stages: [(name: String, rgb: [Double])] = []
        func add(_ name: String, _ rgb: [Double]) {
            stages.append((name, rgb))
            XCTContext.runActivity(named: "\(name): \(rgb)") { _ in }
        }
        add("0 元の PNG", try centerPixel(decode(data), in: extended))
        add("1 無編集で書き出し", try centerPixel(decode(renderer.export(data: data, recipe: .identity)), in: extended))
        add("2 露出 +0.01 だけで書き出し",
            try centerPixel(decode(renderer.export(data: data, recipe: PhotoRecipe(exposure: 0.01))), in: extended))
        add("3 曲線（highlights +1）で書き出し",
            try centerPixel(decode(renderer.export(data: data, recipe: curve)), in: extended))

        // JPEG を通さず、浮動小数で直に描く（8bit・P3 への書き出しで切られていないかを分ける）
        let loaded = try XCTUnwrap(PhotoRenderer.load(data: data, maxPixelSize: 64))
        func direct(_ context: CIContext, _ image: CIImage) throws -> [Double] {
            try centerPixel(XCTUnwrap(context.createCGImage(image, from: loaded.image.extent,
                                                            format: .RGBAh, colorSpace: extended)), in: extended)
        }
        add("4 曲線・アプリの CIContext に直描き", try direct(renderer.context, renderer.apply(curve, to: loaded.image)))
        let srgbWorking = CIContext(options: [.workingColorSpace: try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))])
        add("5 曲線・作業色空間 拡張リニア sRGB に直描き", try direct(srgbWorking, renderer.apply(curve, to: loaded.image)))
        for extrapolate in [true, false] {
            let filter = try XCTUnwrap(CIFilter(name: "CIToneCurve"))
            filter.setValue(loaded.image, forKey: kCIInputImageKey)
            if filter.inputKeys.contains("inputExtrapolate") { filter.setValue(extrapolate, forKey: "inputExtrapolate") }
            let image = try XCTUnwrap(filter.outputImage)
            add("6 恒等の曲線 extrapolate=\(extrapolate)・拡張リニア sRGB", try direct(srgbWorking, image))
            add("7 恒等の曲線 extrapolate=\(extrapolate)・アプリの CIContext", try direct(renderer.context, image))
        }
        return stages
    }

    /// haze（彩度 −0.25・曲線）を当てても、P3 の赤の鮮やかさが大きくは落ちない
    func testHazeKeepsP3RedVivid() throws {
        let exported = try PhotoRenderer.shared.export(data: makeP3Red(),
                                                       recipe: PhotoRecipe(preset: .init(id: "haze")))
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let rgb = try centerPixel(decode(exported), in: p3)
        XCTAssertGreaterThan(rgb[0] - max(rgb[1], rgb[2]), 0.4, "\(rgb)")
    }

    private func makeP3Red() throws -> Data {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(try XCTUnwrap(CGColor(colorSpace: space, components: [1, 0, 0, 1])))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    /// 色温度の向き: ＋で暖かく（R > B）、−で冷たく（B > R）
    func testTemperatureDirection() throws {
        let gray = try makeJPEG(width: 64, height: 64, colorSpaceName: CGColorSpace.sRGB, gray: true)
        let loaded = try XCTUnwrap(PhotoRenderer.load(data: gray, maxPixelSize: 64))
        let srgb = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let warm = try centerPixel(XCTUnwrap(PhotoRenderer.shared.preview(PhotoRecipe(temperature: 1), loaded: loaded)), in: srgb)
        let cool = try centerPixel(XCTUnwrap(PhotoRenderer.shared.preview(PhotoRecipe(temperature: -1), loaded: loaded)), in: srgb)
        XCTAssertGreaterThan(warm[0], warm[2] + 0.02, "暖かく: \(warm)")
        XCTAssertGreaterThan(cool[2], cool[0] + 0.02, "冷たく: \(cool)")
    }

    func testPreviewRendersAtLoadedSize() throws {
        let data = try makeJPEG(width: 3000, height: 2000, colorSpaceName: CGColorSpace.sRGB)
        let loaded = try XCTUnwrap(PhotoRenderer.load(data: data, maxPixelSize: 600))
        let image = try XCTUnwrap(PhotoRenderer.shared.preview(recipe, loaded: loaded))
        XCTAssertEqual(max(image.width, image.height), 600)
    }
}
#endif
