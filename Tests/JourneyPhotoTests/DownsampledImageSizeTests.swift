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

    /// 縦横比の分からない写真を小さな枠に敷く（行きたい場所の一覧の表紙・56pt）。
    /// 2:1 までの形と見込めば 56 × 2 × 3 = 336 → 512px。上限（2048px）で読まない
    func testFillWithAnAssumedRatioLimitReadsSmallForThumbnails() {
        let thumb = CGSize(width: 56, height: 56)
        XCTAssertEqual(DownsampledImageSize.pixels(filling: thumb, scale: 3, assumedRatioLimit: 2), 512)
        // 見込みの比までなら、横長でも縦長でもぼやけない（実際の縦横比で要る画素以上）
        let assumed = DownsampledImageSize.pixels(filling: thumb, scale: 3, assumedRatioLimit: 2)!
        for ratio: CGFloat in [2, 1.5, 1, 0.75, 0.5] {
            XCTAssertGreaterThanOrEqual(assumed, DownsampledImageSize.pixels(filling: thumb, scale: 3, aspectRatio: ratio)!,
                                        "縦横比 \(ratio) で画素が足りない")
        }
        // 縦横比が分かればそちらを使う。見込みを渡さなければ今までどおり上限
        XCTAssertEqual(DownsampledImageSize.pixels(filling: thumb, scale: 3, aspectRatio: 1, assumedRatioLimit: 2), 256)
        XCTAssertEqual(DownsampledImageSize.pixels(filling: thumb, scale: 3), DownsampledImageSize.maximum)
        // 1 未満の見込みはおかしな値として上限で読む
        XCTAssertEqual(DownsampledImageSize.pixels(filling: thumb, scale: 3, assumedRatioLimit: 0.5),
                       DownsampledImageSize.maximum)
    }

    /// 🔴 **行きたい場所の撮影スポットの行は、台帳の写真を表紙に敷く**（2026-10-03 owner「ピンだけで悲しい」）。
    /// 写真の無い行だけ印。画面は模型では描けないので、書いてあることを見る
    func testWishlistSpotRowShowsTheSpotPhoto() throws {
        let source = try String(contentsOfFile: Self.sourcePath("Features/Profile/MyPageView.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private func officialWishlistRow"))
        let end = try XCTUnwrap(source.range(of: "Spacer(minLength: 8)", range: start.upperBound..<source.endIndex))
        let row = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(row.contains("row.spot?.photo"), "台帳の写真を見ていない（ピンだけになる）")
        // 縮小版 → 元の画像の切り替えは `SpotThumbImage`。見込みの縦横比を渡すと中は縮めて読む部品になる
        XCTAssertTrue(row.contains("SpotThumbImage(image: photo, assumedRatioLimit:"), "表紙を縮めて読んでいない")
        let thumb = try String(contentsOfFile: Self.sourcePath("Features/Common/SpotThumbImage.swift"), encoding: .utf8)
        XCTAssertTrue(thumb.contains("if let assumedRatioLimit {\n                DownsampledRemoteImage("),
                      "見込みの縦横比を渡しても縮めて読んでいない")
        XCTAssertTrue(thumb.contains("assumedRatioLimit: assumedRatioLimit"), "縦横比の無い写真を上限の大きさで読んでいる")
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

    // MARK: - 格子の1枚（2026-10-28・マイページの送りの重さ）

    /// 🔴 格子の1枚（`PhotoFrame`）はマスの大きさまで縮めて読む。3列の 4:5 のマス（約 130×162.5pt・3倍）
    func testGridCellReadsAtTheCellSize() {
        let cell = CGSize(width: 130, height: 162.5)
        // 縦横比の分かる写真: 3:2 の横長は高さに合わせて 243.75pt 幅 → 731px → 768
        XCTAssertEqual(DownsampledImageSize.pixels(filling: cell, scale: 3, aspectRatio: 1.5), 768)
        // 枠と同じ 4:5 → 長い辺は高さ 487.5px → 512
        XCTAssertEqual(DownsampledImageSize.pixels(filling: cell, scale: 3, aspectRatio: 0.8), 512)
        // 縦横比の無い写真は 2:1 までと見込む（上限の 2048px で読まない）
        let assumed = DownsampledImageSize.pixels(filling: cell, scale: 3, assumedRatioLimit: PhotoFrame.assumedRatioLimit)
        XCTAssertEqual(assumed, 1024)
        XCTAssertLessThan(assumed!, DownsampledImageSize.maximum)
    }

    /// 🔴 格子の1枚が縮めて読む部品を使う（元の大きさで展開する `RemoteImage` に戻さない）。
    /// 地の色・切り抜き・自動の1回の読み直し・期限切れの署名の合図・淡い出は今までどおり
    func testPhotoFrameUsesTheDownsampledImage() throws {
        let source = try String(contentsOfFile: Self.sourcePath("Features/Common/PhotoGrid.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "struct PhotoFrame: View {"))
        let frame = String(source[start.lowerBound...])
        XCTAssertTrue(frame.contains("DownsampledRemoteImage(url: photo.gridImageURL, contentMode: .fill,"), "格子の1枚が縮めて読んでいない")
        XCTAssertTrue(frame.contains("alignment: photo.gridAlignment"), "切り抜きの位置が変わった")
        XCTAssertTrue(frame.contains("assumedRatioLimit: Self.assumedRatioLimit"))
        XCTAssertTrue(frame.contains("appearAnimation: .easeOut(duration: 0.15)"), "出るときの動きが RemoteImage と違う")
        let plain = try NSRegularExpression(pattern: "(?<!Downsampled)RemoteImage\\(")
        XCTAssertEqual(plain.numberOfMatches(in: frame, range: NSRange(frame.startIndex..., in: frame)), 0,
                       "格子の1枚に元の大きさで展開する部品が残っている")
        // 縮めて読む部品も、期限切れの署名の合図と自動の1回の読み直しを持つ
        let image = try String(contentsOfFile: Self.sourcePath("Features/Common/DownsampledRemoteImage.swift"), encoding: .utf8)
        XCTAssertTrue(image.contains("SignedImageExpiry.report(url)"))
        XCTAssertTrue(image.contains("RemoteImageRetry.step(automaticDone: automaticRetries,"))
        XCTAssertTrue(image.contains("WebTheme.surface"))
        // 戻ったときは控えから（取りに行く前に出す・取りに行かない）
        XCTAssertTrue(image.contains("if let image = image ?? url.flatMap({ Self.memory.entry(for: $0)?.image }) {"))
        XCTAssertTrue(image.contains("if let cached = Self.memory.entry(for: url, atLeast: pixels) {"))
        XCTAssertTrue(image.contains("Self.memory.store(decoded.image, pixels: pixels, for: url, cost: decoded.cost)"))
    }

    /// 縮めた絵の控え: URL ごとにいちばん大きく読めた1枚。小さな絵を大きな求めに返さない
    func testDecodedImageMemoryKeepsTheLargestPerURL() throws {
        final class Box {}
        let memory = DecodedImageMemory<Box>(costLimit: 1_000_000)
        let url = try XCTUnwrap(URL(string: "https://x/a.jpg"))
        XCTAssertNil(memory.entry(for: url))
        let small = Box(), large = Box()
        memory.store(small, pixels: 512, for: url, cost: 10)
        XCTAssertTrue(memory.entry(for: url)?.image === small)
        XCTAssertTrue(memory.entry(for: url, atLeast: 512)?.image === small)
        XCTAssertNil(memory.entry(for: url, atLeast: 768), "小さな絵を大きな枠に返している")
        memory.store(large, pixels: 1024, for: url, cost: 10)
        XCTAssertTrue(memory.entry(for: url, atLeast: 768)?.image === large)
        memory.store(small, pixels: 256, for: url, cost: 10)
        XCTAssertTrue(memory.entry(for: url)?.image === large, "小さな絵で大きな控えを置き換えた")
        XCTAssertEqual(memory.entry(for: url)?.pixels, 1024)
        XCTAssertNil(memory.entry(for: try XCTUnwrap(URL(string: "https://x/b.jpg"))))
        memory.removeAll()
        XCTAssertNil(memory.entry(for: url))
    }

    private static func sourcePath(_ relative: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto").appendingPathComponent(relative).path
    }
}
