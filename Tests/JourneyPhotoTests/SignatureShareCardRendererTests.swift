import XCTest
import UIKit
import ImageIO
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
            aperture: "f/2", iso: 100)
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

    func testSquareCardRenders() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).jpegData(
            withCompressionQuality: 0.9) { context in
                UIColor.gray.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            }
        let credit = SignatureShareCardRenderer.Credit(
            name: "Creator", username: nil, location: nil, coords: nil,
            camera: nil, lens: nil, exposure: nil, aperture: nil, iso: nil)
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
            exposure: "1/125s", aperture: "f/4", iso: 200)
        let result = await SignatureShareCardRenderer.render(
            source, credit: credit, ratio: .story)
        let image = try XCTUnwrap(UIImage(data: try XCTUnwrap(result)))
        XCTAssertEqual(image.size, CGSize(width: 1080, height: 1920))
    }

}

#endif
