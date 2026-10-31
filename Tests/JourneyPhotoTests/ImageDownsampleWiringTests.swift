import XCTest
@testable import JourneyPhoto

/// 小さい枠に大きい写真を原寸で読まない（2026-10-31・札 #429 アプリ 2）。
///
/// ストーリーの輪・四角いサムネ、写真の詳細の大きな写真、旅の一冊の表紙を、元の画像をそのまま展開する
/// `RemoteImage` から、枠の大きさまで縮めて読む `DownsampledRemoteImage` に替えた。
/// 画面は模型では描けないので、**書いてあること**（直しを戻すと落ちる）と、**読む画素数が枠の画素を下回らない**
/// （粗くならない）ことの両方で押さえる
final class ImageDownsampleWiringTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    /// 型・関数の宣言から、次の `struct`・`private func` の手前まで
    private func block(_ start: String, until end: String, in text: String) throws -> String {
        let from = try XCTUnwrap(text.range(of: start), "\(start) が無い")
        let to = text.range(of: end, range: from.upperBound..<text.endIndex)?.lowerBound ?? text.endIndex
        return String(text[from.lowerBound..<to])
    }

    /// `DownsampledRemoteImage(` の中にも `RemoteImage(` が含まれるので、前に `Downsampled` が無いものを数える
    private func plainRemoteImages(_ text: String) -> Int {
        let plain = try! NSRegularExpression(pattern: "(?<!Downsampled)RemoteImage\\(")
        return plain.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    // MARK: - ストーリーの輪とサムネ

    func testStoryThumbAndPosterDownsample() throws {
        let media = try source("Features/Stories/StoryMedia.swift")
        for name in ["struct StoryThumb: View", "struct StoryPoster: View"] {
            let body = try block(name, until: "\nstruct ", in: media)
            XCTAssertEqual(plainRemoteImages(body), 0, "\(name) が原寸のまま展開する部品を使っている")
            XCTAssertTrue(body.contains("DownsampledRemoteImage(url: story.imageURL, contentMode: .fill"),
                          "\(name) が縮めて読む部品を枠いっぱいの敷き方で使っていない")
            XCTAssertTrue(body.contains("assumedRatioLimit: StoryThumbnailSize.assumedRatioLimit"),
                          "\(name) が縦横比の見込みを渡していない（渡さないと上限 2048px で読み、縮まない）")
            // `RemoteImage` の `AsyncImage` と同じ淡い出
            XCTAssertTrue(body.contains("appearAnimation: .easeOut(duration: 0.15)"), "\(name) の出の動きが前と違う")
        }
    }

    /// 輪（64pt・52pt）と四角いサムネ（72×110 など）は、**3:1 までの横長・縦長のどれでも枠を覆える**画素で読む。
    /// 原寸（1920px）より小さく読む（縮める得がある）
    func testStoryThumbPixelsCoverTheFrameAndShrink() throws {
        let boxes = [CGSize(width: 64, height: 64), CGSize(width: 52, height: 52),
                     CGSize(width: 72, height: 110), CGSize(width: 48, height: 64)]
        for box in boxes {
            let pixels = try XCTUnwrap(DownsampledImageSize.pixels(
                filling: box, scale: 3, assumedRatioLimit: StoryThumbnailSize.assumedRatioLimit))
            XCTAssertLessThan(pixels, 1920, "\(box) で原寸と同じ大きさで読んでいる")
            for ratio in [3.0, 16.0 / 9.0, 4.0 / 3.0, 1.0, 3.0 / 4.0, 9.0 / 16.0, 1.0 / 3.0] {
                // 長い辺が `pixels` の写真を、縦横比 `ratio` のまま縮めた大きさ
                let width = ratio >= 1 ? Double(pixels) : Double(pixels) * ratio
                let height = ratio >= 1 ? Double(pixels) / ratio : Double(pixels)
                // 枠を覆うのに要る倍率が 1 以下（＝引き伸ばさない）
                let needed = max(Double(box.width) * 3 / width, Double(box.height) * 3 / height)
                XCTAssertLessThanOrEqual(needed, 1.0001, "\(box) に縦横比 \(ratio) の写真を敷くと粗くなる（\(pixels)px）")
            }
        }
    }

    // MARK: - 写真の詳細の大きな写真

    func testPhotoDetailHeroDownsamples() throws {
        let view = try source("Features/PhotoDetail/PhotoDetailView.swift")
        let hero = try block("private func heroImage(", until: "\n    private ", in: view)
        XCTAssertEqual(plainRemoteImages(hero), 0, "写真の詳細の大きな写真が原寸のまま展開する部品を使っている")
        XCTAssertTrue(hero.contains("DownsampledRemoteImage(url: item.detailImageURL, contentMode: .fill"))
        XCTAssertTrue(hero.contains("aspectRatio: item.aspectRatio.map { CGFloat($0) }"),
                      "縦横比を渡していない（覆うのに要る画素が出せない）")
        XCTAssertTrue(hero.contains("alignment: item.gridAlignment"), "切り抜きの中心（focalPoint）が前と違う")
        XCTAssertTrue(hero.contains("appearAnimation: .easeOut(duration: 0.15)"))
        // 拡大しない画面のまま（拡大は別の画面 `PhotoViewerView` が自分で読む）。ここに拡大を足すなら、読む大きさも見直す
        XCTAssertFalse(hero.contains("MagnifyGesture") || hero.contains("MagnificationGesture"),
                       "大きな写真が拡大できるようになった。拡大の上限ぶん大きく読まないと粗くなる")
    }

    /// 大きな写真の枠（いちばん広い iPhone の幅 440pt × 520pt・3倍の画面）を、どの縦横比の写真でも覆える
    func testHeroPixelsNeverFallBelowTheFrame() throws {
        for width in [375.0, 393.0, 402.0, 430.0, 440.0] {
            let box = CGSize(width: width, height: Double(PhotoDetailView.heroHeight))
            for ratio in [3.0, 16.0 / 9.0, 3.0 / 2.0, 4.0 / 3.0, 1.0, 3.0 / 4.0, 9.0 / 16.0, 1.0 / 3.0] {
                let pixels = try XCTUnwrap(DownsampledImageSize.pixels(filling: box, scale: 3, aspectRatio: CGFloat(ratio)))
                let w = ratio >= 1 ? Double(pixels) : Double(pixels) * ratio
                let h = ratio >= 1 ? Double(pixels) / ratio : Double(pixels)
                // 上限（2048px）で頭打ちになる横長は、元の画像（長い辺 1920px）も同じく足りない——前と同じ
                guard pixels < DownsampledImageSize.maximum else { continue }
                XCTAssertGreaterThanOrEqual(w, width * 3 - 0.5, "幅 \(width) に縦横比 \(ratio) の写真で横が足りない")
                XCTAssertGreaterThanOrEqual(h, Double(PhotoDetailView.heroHeight) * 3 - 0.5,
                                            "幅 \(width) に縦横比 \(ratio) の写真で縦が足りない")
            }
            // 縦横比が分からない写真は上限で読む（原寸 1920px より大きい＝縮めない。粗くしない）
            XCTAssertEqual(DownsampledImageSize.pixels(filling: box, scale: 3), DownsampledImageSize.maximum)
        }
    }

    // MARK: - 旅の一冊の表紙

    func testTripBookCoverDownsamples() throws {
        let view = try source("Features/Trips/TripBookView.swift")
        let cover = try block("private var cover: some View", until: "\n    private ", in: view)
        XCTAssertEqual(plainRemoteImages(cover), 0, "旅の一冊の表紙が原寸のまま展開する部品を使っている")
        XCTAssertTrue(cover.contains("DownsampledRemoteImage(url: cover.detailImageURL, contentMode: .fill"))
        XCTAssertTrue(cover.contains("aspectRatio: cover.aspectRatio.map { CGFloat($0) }"))
        XCTAssertTrue(cover.contains("alignment: cover.gridAlignment"))
        XCTAssertTrue(cover.contains("appearAnimation: .easeOut(duration: 0.15)"))
    }

    // MARK: - 読み込み中・失敗・読み直しが前と同じ

    /// 替えた4か所はどれも、押して読み直す記号（`allowsManualRetry`）も、片付いた知らせ（`onSettled`）も
    /// 使っていなかった（前の `RemoteImage` の既定のまま）。縮めて読む部品も同じく、自動の1回のあとは記号だけ
    /// （押す記号は出さない）。失敗・URL の無いときは写真の記号、読んでいる間は輪
    func testLoadingFailureAndRetryMatchTheOldBehaviour() {
        // 自動の1回 → 記号だけ（押す記号は出さない）。`RemoteImage` の既定（`allowsManualRetry: false`）と同じ
        XCTAssertEqual(RemoteImageRetry.step(automaticDone: 0, manualDone: 0),
                       .retryAutomatically(afterSeconds: RemoteImageRetry.automaticDelay))
        XCTAssertEqual(RemoteImageRetry.step(automaticDone: 1, manualDone: 0), .giveUp)
        XCTAssertEqual(DownsampledImagePhase.of(hasImage: false, failed: false, hasURL: true), .loading)
        XCTAssertEqual(DownsampledImagePhase.of(hasImage: false, failed: true, hasURL: true), .failed)
        XCTAssertEqual(DownsampledImagePhase.of(hasImage: true, failed: true, hasURL: true), .image)
    }

    /// 前の4か所は `allowsManualRetry`・`onSettled`・`onLayout`・`placeholderSymbol` を渡していなかった
    /// （渡していたら、縮めて読む部品には同じ口が無いので替えてはいけない）
    func testReplacedSitesDidNotUseOptionsTheDownsampledImageLacks() throws {
        let sites = [
            try block("struct StoryThumb: View", until: "\nstruct ", in: try source("Features/Stories/StoryMedia.swift")),
            try block("struct StoryPoster: View", until: "\nstruct ", in: try source("Features/Stories/StoryMedia.swift")),
            try block("private func heroImage(", until: "\n    private ", in: try source("Features/PhotoDetail/PhotoDetailView.swift")),
            try block("private var cover: some View", until: "\n    private ", in: try source("Features/Trips/TripBookView.swift")),
        ]
        for site in sites {
            for option in ["allowsManualRetry", "onSettled", "onLayout", "placeholderSymbol"] {
                XCTAssertFalse(site.contains(option + ":"), "\(option) を使う所を縮めて読む部品に替えている")
            }
        }
    }
}
