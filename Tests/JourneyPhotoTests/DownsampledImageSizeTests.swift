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

    // MARK: - 枠いっぱいに敷き詰める（撮影地の代表写真の並び・2026-10-03）

    /// 🔴 **枠より横長の写真は、高さに合わせて広がる。** 幅の画素（1170）だけで読むと、
    /// 4:3 の枠（390×292.5pt）に 16:9 の写真を敷いたとき、写真の幅は 520pt＝1560px 要るのにぼやける
    func testFillWithAWiderPhotoUsesTheHeight() {
        let box = CGSize(width: 390, height: 292.5)
        // 520 × 3 = 1560 → 1792
        XCTAssertEqual(DownsampledImageSize.pixels(filling: box, scale: 3, aspectRatio: 16.0 / 9.0), 1792)
        let longSide = DownsampledImageSize.pixels(filling: box, scale: 3, aspectRatio: 16.0 / 9.0)!
        XCTAssertGreaterThanOrEqual(Double(longSide) * 9.0 / 16.0, 292.5 * 3, "横長で高さの画素が足りない")
    }

    /// 縦長の写真は幅に合わせて広がり、長い辺は高さ（幅 ÷ 縦横比）
    func testFillWithATallerPhotoUsesTheWidth() {
        let box = CGSize(width: 390, height: 292.5)
        // 幅 390pt・高さ 520pt → 520 × 3 = 1560 → 1792
        XCTAssertEqual(DownsampledImageSize.pixels(filling: box, scale: 3, aspectRatio: 0.75), 1792)
        // 枠と同じ 4:3 → 長い辺は幅 390 × 3 = 1170 → 1280
        XCTAssertEqual(DownsampledImageSize.pixels(filling: box, scale: 3, aspectRatio: 4.0 / 3.0), 1280)
    }

    /// 縦横比が分からなければ上限で読む（どの形でもぼやけない）。枠が測れないうちは読まない
    func testFillWithoutRatioReadsTheMaximumAndWaitsForTheBox() {
        let box = CGSize(width: 390, height: 292.5)
        XCTAssertEqual(DownsampledImageSize.pixels(filling: box, scale: 3), DownsampledImageSize.maximum)
        XCTAssertEqual(DownsampledImageSize.pixels(filling: box, scale: 3, aspectRatio: 0), DownsampledImageSize.maximum)
        XCTAssertNil(DownsampledImageSize.pixels(filling: CGSize(width: 390, height: 0), scale: 3, aspectRatio: 1))
        XCTAssertNil(DownsampledImageSize.pixels(filling: CGSize(width: 0, height: 300), scale: 3, aspectRatio: 1))
        XCTAssertNil(DownsampledImageSize.pixels(filling: box, scale: 0, aspectRatio: 1))
    }

    /// 撮影地の代表写真の並びが、縮めて読む部品を使っていること（元の画像をそのまま展開する
    /// `RemoteImage` に戻さない）。ページを払うと隣の絵も抱えるので、ここが一番効く
    func testSpotHeroPagerUsesTheDownsampledImage() throws {
        let source = try String(contentsOfFile: Self.sourcePath("Features/Spots/SpotDetailView.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private var heroPager"))
        let end = try XCTUnwrap(source.range(of: ".tabViewStyle(", range: start.upperBound..<source.endIndex))
        let pager = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(pager.contains("DownsampledRemoteImage("), "撮影地の代表写真が縮めて読む部品を使っていない")
        XCTAssertTrue(pager.contains("contentMode: .fill"), "敷き詰め（fill）の画素数で読んでいない")
        let plain = try NSRegularExpression(pattern: "(?<!Downsampled)RemoteImage\\(")
        XCTAssertEqual(plain.numberOfMatches(in: pager, range: NSRange(pager.startIndex..., in: pager)), 0,
                       "撮影地の代表写真に元の画像をそのまま展開する部品が残っている")
    }

    private static func sourcePath(_ relative: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto").appendingPathComponent(relative).path
    }
}
