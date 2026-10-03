import XCTest
@testable import JourneyPhoto

/// 旅の一冊のページを**表示する幅に縮めて読む**画素数（`DownsampledImageSize`・2026-10-03）。
///
/// 元の画像（長い辺 1920px）を縮めずに展開すると1枚約 11MB。ページを `LazyVStack` に並べる
/// 旅の一冊では、通り過ぎたページの絵を抱えたままになりやすい。ここでは画素数の決まりだけを見る
/// （ImageIO の実際の縮小は Linux の模型では動かない——CI の UI テストの「30-旅の一冊」の絵で見る）
final class DownsampledImageSizeTests: XCTestCase {

    /// 横長・縦横比なし: 幅 × 倍率を 256 単位で切り上げる（iPhone の幅 390pt × 3 = 1170 → 1280）
    func testWidthTimesScaleIsRoundedUpToTheStep() {
        XCTAssertEqual(DownsampledImageSize.pixels(width: 390, scale: 3), 1280)
        XCTAssertEqual(DownsampledImageSize.pixels(width: 390, scale: 3, aspectRatio: 1.5), 1280)
        XCTAssertEqual(DownsampledImageSize.pixels(width: 256, scale: 1), 256, "ちょうど刻みなら切り上げない")
    }

    /// 🔴 **縦長の写真も幅いっぱいに描く。** 長い辺＝高さなので、幅の画素 ÷ 縦横比を長い辺にする。
    /// 幅の画素（1170）だけを長い辺に渡すと、幅は 1170 × 0.75 = 877px しか残らずぼやける
    func testPortraitUsesTheHeightAsTheLongSide() {
        // 3:4 の縦長 → 長い辺 1170 / 0.75 = 1560 → 1792
        XCTAssertEqual(DownsampledImageSize.pixels(width: 390, scale: 3, aspectRatio: 0.75), 1792)
        let longSide = DownsampledImageSize.pixels(width: 390, scale: 3, aspectRatio: 0.75)!
        XCTAssertGreaterThanOrEqual(Double(longSide) * 0.75, 1170, "縦長で幅の画素が足りない")
    }

    /// 上限は 2048（元の 1920 より大きく読む意味は無い）・下限は 256
    func testIsClampedBetweenMinimumAndMaximum() {
        XCTAssertEqual(DownsampledImageSize.pixels(width: 1024, scale: 3), 2048)
        XCTAssertEqual(DownsampledImageSize.pixels(width: 390, scale: 3, aspectRatio: 0.2), 2048)
        XCTAssertEqual(DownsampledImageSize.pixels(width: 20, scale: 2), 256)
    }

    /// 幅がまだ分からないうちは読まない（0 の幅で 256px を読んで、測れた後に読み直さない）
    func testUnknownWidthDoesNotLoad() {
        XCTAssertNil(DownsampledImageSize.pixels(width: 0, scale: 3))
        XCTAssertNil(DownsampledImageSize.pixels(width: -1, scale: 3))
        XCTAssertNil(DownsampledImageSize.pixels(width: 390, scale: 0))
    }

    /// おかしな縦横比（0 以下）は無いものとして扱う
    func testInvalidAspectRatioIsIgnored() {
        XCTAssertEqual(DownsampledImageSize.pixels(width: 390, scale: 3, aspectRatio: 0), 1280)
        XCTAssertEqual(DownsampledImageSize.pixels(width: 390, scale: 3, aspectRatio: -2), 1280)
    }

    /// 少しの幅の違いでは同じ画素数になる（回転・余白の違いで読み直しが走らない）
    func testSmallWidthChangesKeepTheSamePixels() {
        XCTAssertEqual(DownsampledImageSize.pixels(width: 390, scale: 3),
                       DownsampledImageSize.pixels(width: 400, scale: 3))
    }

    /// 旅の一冊のページが、縮めて読む部品を使っていること（元の画像をそのまま展開する
    /// `RemoteImage` に戻さない）。画面は模型では描けないので、書いてあることを見る
    func testTripBookPagesUseTheDownsampledImage() throws {
        let source = try String(contentsOfFile: Self.sourcePath("Features/Trips/TripBookView.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private func pageImage"))
        let end = try XCTUnwrap(source.range(of: "private func page(", range: start.upperBound..<source.endIndex))
        let pageImage = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(pageImage.contains("DownsampledRemoteImage("), "旅の一冊のページが縮めて読む部品を使っていない")
        // `DownsampledRemoteImage(` の中にも `RemoteImage(` が含まれるので、前に `Downsampled` が無いものを探す
        let plain = try NSRegularExpression(pattern: "(?<!Downsampled)RemoteImage\\(")
        XCTAssertEqual(plain.numberOfMatches(in: pageImage, range: NSRange(pageImage.startIndex..., in: pageImage)), 0,
                       "旅の一冊のページに元の画像をそのまま展開する部品が残っている")
    }

    private static func sourcePath(_ relative: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto").appendingPathComponent(relative).path
    }
}
