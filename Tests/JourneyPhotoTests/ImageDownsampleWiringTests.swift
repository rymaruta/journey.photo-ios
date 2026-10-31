import XCTest
@testable import JourneyPhoto

/// 小さい枠に大きい写真を原寸で読まない（2026-10-31・札 #429 アプリ 2）。
///
/// ストーリーの輪・四角いサムネを、元の画像をそのまま展開する `RemoteImage` から、枠の大きさまで縮めて読む
/// `DownsampledRemoteImage` に替えた（Mac run 790 → 793 で輪の画面のメモリの山 157.1 → 135.7MB）。
/// 写真の詳細の大きな写真・旅の一冊の表紙は、縮めても得が無いので替えない（下の試験）。
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
            var body = try block(name, until: "\nstruct ", in: media)
            // 四角いサムネの「縮めない」の口（`downsamples: false`・全画面のリールの面の比べ）の中だけは元の部品
            if let from = body.range(of: "} else if !downsamples {"),
               let to = body.range(of: "} else {", range: from.upperBound..<body.endIndex) {
                body.removeSubrange(from.lowerBound..<to.lowerBound)
            }
            XCTAssertEqual(plainRemoteImages(body), 0, "\(name) が原寸のまま展開する部品を使っている")
            XCTAssertTrue(body.contains("DownsampledRemoteImage(url: story.imageURL, contentMode: .fill"),
                          "\(name) が縮めて読む部品を枠いっぱいの敷き方で使っていない")
            XCTAssertTrue(body.contains("assumedRatioLimit: StoryThumbnailSize.assumedRatioLimit"),
                          "\(name) が縦横比の見込みを渡していない（渡さないと上限 2048px で読み、縮まない）")
            // `RemoteImage` の `AsyncImage` と同じ淡い出
            XCTAssertTrue(body.contains("appearAnimation: .easeOut(duration: 0.15)"), "\(name) の出の動きが前と違う")
        }
    }

    /// 輪の写真（54pt・`StoryRingMetrics.photo`）と四角いサムネ（72×110 など）は、**3:1 までの横長・縦長のどれでも枠を覆える**画素で読む。
    /// 原寸（1920px）より小さく読む（縮める得がある）
    func testStoryThumbPixelsCoverTheFrameAndShrink() throws {
        let boxes = [CGSize(width: 54, height: 54), CGSize(width: 64, height: 64),
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

    // MARK: - 写真の詳細の大きな写真・旅の一冊の表紙（替えない）

    /// 大きな枠（画面の幅 × 520pt の写真の詳細・3:4 の表紙）は、**覆うのに要る画素が元の画像（長い辺 1,920px）と
    /// ほぼ同じ**で、縮めても得が無い（2026-10-31・替えた回の Mac run 793 で、開いた時のメモリの山は減らず、
    /// 閉じた後のメモリが増えた）。だから `RemoteImage` のまま。ここで「縮まない」ことを数で押さえる
    func testLargeFramesNeedAboutTheOriginalPixels() throws {
        for width in [375.0, 393.0, 402.0, 430.0, 440.0] {
            let boxes = [CGSize(width: width, height: Double(PhotoDetailView.heroHeight)),
                         CGSize(width: width, height: width * 4 / 3)]
            for box in boxes {
                for ratio in [16.0 / 9.0, 3.0 / 2.0, 4.0 / 3.0, 1.0, 3.0 / 4.0, 9.0 / 16.0] {
                    let pixels = try XCTUnwrap(DownsampledImageSize.pixels(filling: box, scale: 3, aspectRatio: CGFloat(ratio)))
                    XCTAssertGreaterThanOrEqual(pixels, 1536, "\(box) に縦横比 \(ratio) で、元の画像より大きく縮められる（替える意味が出た）")
                }
                // 縦横比の無い写真（多い）は上限で読む＝元の画像のまま
                XCTAssertEqual(DownsampledImageSize.pixels(filling: box, scale: 3), DownsampledImageSize.maximum)
            }
        }
    }

    /// 写真の詳細の大きな写真と旅の一冊の表紙は `RemoteImage` のまま（上の理由）
    func testLargeFramesKeepTheRemoteImage() throws {
        let view = try source("Features/PhotoDetail/PhotoDetailView.swift")
        let hero = try block("private func heroImage(", until: "\n    private ", in: view)
        XCTAssertTrue(hero.contains("RemoteImage(url: item.detailImageURL, alignment: item.gridAlignment)"))
        XCTAssertFalse(hero.contains("DownsampledRemoteImage("), "大きな写真を縮めて読む部品に替えている（run 793 で閉じた後のメモリが増えた）")
        let book = try source("Features/Trips/TripBookView.swift")
        let cover = try block("private var cover: some View", until: "\n    private ", in: book)
        XCTAssertTrue(cover.contains("RemoteImage(url: cover.detailImageURL, alignment: cover.gridAlignment)"))
        XCTAssertFalse(cover.contains("DownsampledRemoteImage("))
    }

    // MARK: - 読み込み中・失敗・読み直しが前と同じ

    /// 替えた2か所（輪と四角いサムネ）はどれも、押して読み直す記号（`allowsManualRetry`）も、片付いた知らせ（`onSettled`）も
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

    /// 前の2か所は `allowsManualRetry`・`onSettled`・`onLayout`・`placeholderSymbol` を渡していなかった
    /// （渡していたら、縮めて読む部品には同じ口が無いので替えてはいけない）
    func testReplacedSitesDidNotUseOptionsTheDownsampledImageLacks() throws {
        let sites = [
            try block("struct StoryThumb: View", until: "\nstruct ", in: try source("Features/Stories/StoryMedia.swift")),
            try block("struct StoryPoster: View", until: "\nstruct ", in: try source("Features/Stories/StoryMedia.swift")),
        ]
        for site in sites {
            for option in ["allowsManualRetry", "onSettled", "onLayout", "placeholderSymbol"] {
                XCTAssertFalse(site.contains(option + ":"), "\(option) を使う所を縮めて読む部品に替えている")
            }
        }
    }
}
