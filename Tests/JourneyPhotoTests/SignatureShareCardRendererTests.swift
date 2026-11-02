import XCTest
import UIKit
import ImageIO
import CoreLocation
@testable import JourneyPhoto

#if !os(Linux)
final class SignatureShareCardRendererTests: XCTestCase {
    func testPortraitCardRendersExpectedDimensionsAndRemovesMetadata() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600)).jpegData(
            withCompressionQuality: 0.95) { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
            }
        let credit = SignatureShareCardRenderer.Credit(
            name: "Photographer", username: "photographer", location: "Kyoto",
            coords: nil, camera: "Camera", lens: "35mm", exposure: "1/125s",
            aperture: "f/2", iso: 100, verified: false, proStyle: nil,
            early: false, badge: nil)
        let result = await SignatureShareCardRenderer.render(source, credit: credit)
        let data = try XCTUnwrap(result)
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(image.size.width, 1080)
        XCTAssertEqual(image.size.height, 1350)
        // JPEGの画素を書き直しており、元のGPS/EXIFを受け渡さない。
        let imageSource = CGImageSourceCreateWithData(data as CFData, nil)
        let properties = imageSource.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] }
        XCTAssertNil(properties?[kCGImagePropertyGPSDictionary as String])
    }

    func testExportedCardBorderReachesImageCorners() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400))
            .jpegData(withCompressionQuality: 0.95) { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            }
        let credit = SignatureShareCardRenderer.Credit(
            name: "Creator", username: nil, location: nil, coords: nil,
            camera: nil, lens: nil, exposure: nil, aperture: nil, iso: nil,
            verified: false, proStyle: nil, early: false, badge: nil)
        let rendered = await SignatureShareCardRenderer.render(source, credit: credit)
        let data = try XCTUnwrap(rendered)
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(image.size, CGSize(width: 1080, height: 1350))
        // 共有JPEGの四隅は黒背景。真鍮フレームは画像境界から8px内側にあり、
        // 線幅4pxの中心が10pxなので、(10,10)は真鍮色になる。
        // (0,0)に金色を要求すると、意図した8pxの余白を不具合と誤判定する。
        let bitmap = try XCTUnwrap(image.cgImage)
        func pixel(at x: Int, _ y: Int) throws -> [UInt8] {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            var rgba = [UInt8](repeating: 0, count: 4)
            let context = try XCTUnwrap(CGContext(
                data: &rgba, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let cropped = try XCTUnwrap(bitmap.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return rgba
        }
        let corner = try pixel(at: 0, 0)
        XCTAssertLessThan(Int(corner[0]), 30, "画像の四隅は黒い背景で統一する")
        let frame = try pixel(at: 10, 10)
        XCTAssertGreaterThan(Int(frame[0]), 60, "8px内側の真鍮フレームが描かれていない")
    }

    func testSquareCardRenders() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).jpegData(
            withCompressionQuality: 0.9) { context in
                UIColor.gray.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            }
        let credit = SignatureShareCardRenderer.Credit(
            name: "Creator", username: nil, location: nil, coords: nil,
            camera: nil, lens: nil, exposure: nil, aperture: nil, iso: nil, verified: false, proStyle: nil,
            early: false, badge: nil)
        let result = await SignatureShareCardRenderer.render(source, credit: credit, ratio: .square)
        XCTAssertEqual(UIImage(data: try XCTUnwrap(result))?.size, CGSize(width: 1080, height: 1080))
    }
    func testStoryCardRendersExpectedDimensions() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800))
            .jpegData(withCompressionQuality: 0.9) { context in
                UIColor.black.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
            }
        let credit = SignatureShareCardRenderer.Credit(
            name: "Long Photographer Name", username: "journey_photo",
            location: "Florence, Italy", coords: nil,
            camera: "Hasselblad X2D II 100C", lens: "XCD 35-100mm f/2.8-4 E",
            exposure: "1/125s", aperture: "f/4", iso: 200, verified: false, proStyle: nil,
            early: false, badge: nil)
        let result = await SignatureShareCardRenderer.render(
            source, credit: credit, ratio: .story)
        let image = try XCTUnwrap(UIImage(data: try XCTUnwrap(result)))
        XCTAssertEqual(image.size, CGSize(width: 1080, height: 1920))
    }

    func testWideLandscapePhotoCanBeExportedInAllRatios() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 1800, height: 650))
            .jpegData(withCompressionQuality: 0.85) { context in
                UIColor.blue.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1800, height: 650))
            }
        let credit = SignatureShareCardRenderer.Credit(
            name: "Photographer", username: "photo", location: "Venice",
            coords: nil, camera: nil, lens: nil, exposure: nil,
            aperture: nil, iso: nil, verified: false, proStyle: nil,
            early: false, badge: nil)
        for (ratio, height) in [
            (SignatureShareCardRenderer.Ratio.portrait, CGFloat(1350)),
            (.story, CGFloat(1920)),
            (.square, CGFloat(1080))
        ] {
            let rendered = await SignatureShareCardRenderer.render(
                source, credit: credit, ratio: ratio)
            let data = try XCTUnwrap(rendered)
            XCTAssertEqual(UIImage(data: data)?.size,
                           CGSize(width: 1080, height: height))
        }
    }

    func testLongCameraLensAndVisibleMarksRenderForAllRatios() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800))
            .jpegData(withCompressionQuality: 0.9) { context in
                UIColor.darkGray.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
            }
        let credit = SignatureShareCardRenderer.Credit(
            name: "Photographer", username: "journey",
            location: "月崎, 大多喜里見線, 市原市, 千葉県",
            coords: CLLocationCoordinate2D(latitude: 35.34, longitude: 140.14),
            camera: "Hasselblad X2D II 100C Medium Format Camera",
            lens: "Hasselblad XCD 35-100E f/2.8-4 Zoom Lens",
            exposure: "1/125s", aperture: "f/4.8", iso: 200,
            verified: true, proStyle: .iris, early: true, badge: nil)
        for ratio in [SignatureShareCardRenderer.Ratio.portrait, .story, .square] {
            let result = await SignatureShareCardRenderer.render(source, credit: credit, ratio: ratio)
            let image = try XCTUnwrap(UIImage(data: try XCTUnwrap(result)))
            XCTAssertEqual(image.size.width, 1080)
        }
    }

    func testLongEquipmentNamesFitWithinThreeLineArea() {
        let camera = "Hasselblad X2D II 100C Medium Format Camera"
        let lens = "Hasselblad XCD 35-100E f/2.8-4 Zoom Lens"
        for (name, width) in [(camera, CGFloat(235)), (lens, CGFloat(246))] {
            let fontSize = SignatureShareCardRenderer.equipmentFontSize(name, maxWidth: width)
            XCTAssertLessThanOrEqual(fontSize, 22)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byCharWrapping
            paragraph.lineSpacing = 1
            let measured = (name as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                    .paragraphStyle: paragraph
                ], context: nil)
            XCTAssertLessThanOrEqual(measured.height, 72.5, "\(name) must fit without clipping")
        }
    }

    func testInvalidPhotoDataReturnsNil() async {
        let credit = SignatureShareCardRenderer.Credit(
            name: "Creator", username: nil, location: nil, coords: nil,
            camera: nil, lens: nil, exposure: nil, aperture: nil, iso: nil, verified: false, proStyle: nil,
            early: false, badge: nil)
        let result = await SignatureShareCardRenderer.render(
            Data("not a photo".utf8), credit: credit)
        XCTAssertNil(result)
    }

    func testAvatarImageCanBeRendered() async throws {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 1000))
            .jpegData(withCompressionQuality: 0.9) { context in
                UIColor.gray.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 800, height: 1000))
            }
        let avatar = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
            .pngData { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            }
        let credit = SignatureShareCardRenderer.Credit(
            name: "Creator", username: "creator", location: "Tokyo",
            coords: nil, camera: nil, lens: nil, exposure: nil,
            aperture: nil, iso: nil, verified: false, proStyle: nil,
            early: false, badge: nil)
        let rendered = await SignatureShareCardRenderer.render(
            photo, credit: credit, avatarData: avatar)
        XCTAssertNotNil(UIImage(data: try XCTUnwrap(rendered)))
    }

}

#endif
