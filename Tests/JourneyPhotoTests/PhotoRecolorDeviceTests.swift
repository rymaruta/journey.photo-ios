import XCTest
@testable import JourneyPhoto
#if os(iOS)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#endif

/// **色の編集し直しの「画像か」の判定（`PhotoRecolor.decodable`）を本物の ImageIO で通す。**
///
/// 🔴 **Mac の `xcodebuild test`（シミュレータ）でだけ走る**（`ImagePreparerDeviceTests` と同じ）。
/// Linux の模型の ImageIO は何を渡しても「読めない」と答えるので、`XCTSkip` で飛ばす——
/// Linux が緑でも、本物の JPEG を読めるかは確かめていない。
/// 読めないと、公開中の写真がいつも「画像でない応答」で断られ、色を編集できない
final class PhotoRecolorDeviceTests: XCTestCase {

    private static let skipReason = "本物の ImageIO が要る（Mac の xcodebuild test でだけ走る）"

    /// 本物の JPEG は画像と読み、HTML・空・途中で切れた先頭だけは読まない
    func testDecodableReadsRealJPEG() throws {
        #if os(iOS)
        let jpeg = try Self.makeJPEG(width: 64, height: 48)
        XCTAssertTrue(PhotoRecolor.decodable(jpeg), "本物の JPEG を画像と読まない")
        XCTAssertFalse(PhotoRecolor.decodable(Data("<!doctype html><html></html>".utf8)), "HTML を画像と読んだ")
        XCTAssertFalse(PhotoRecolor.decodable(Data()), "空を画像と読んだ")
        #else
        throw XCTSkip(Self.skipReason)
        #endif
    }

    #if os(iOS)
    /// 一色の画像を JPEG にする
    private static func makeJPEG(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: 0.79, green: 0.65, blue: 0.42, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination), "前提: JPEG を書けない")
        return data as Data
    }
    #endif
}
