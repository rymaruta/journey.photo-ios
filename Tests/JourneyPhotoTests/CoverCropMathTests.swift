import XCTest
@testable import JourneyPhoto

/// カバーの位置を合わせる計算（owner 2026-10-28）。枠を覆うこと・位置と倍率の制限・元の写真の画素への変換・上げる大きさ
final class CoverCropMathTests: XCTestCase {

    /// 画面 390pt × 帯の高さ
    private var frame: CGSize { CoverCropMath.frame(width: 390) }

    func testFrameUsesProfileCoverHeight() {
        // 高さは定数を写さず、マイページの帯を参照する
        XCTAssertEqual(frame.width, 390)
        XCTAssertEqual(frame.height, ProfileCover.height)
    }

    func testFillSizeCoversTheFrame() {
        // 縦長・横長・正方形・帯よりさらに横長の写真で、等倍が枠を必ず覆い、どちらかの辺は枠にぴったり
        for image in [CGSize(width: 3000, height: 4000), CGSize(width: 4000, height: 3000),
                      CGSize(width: 1000, height: 1000), CGSize(width: 6000, height: 1000)] {
            let fill = FrameCropMath.fillSize(image: image, frame: frame)
            XCTAssertGreaterThanOrEqual(fill.width + 0.0001, frame.width, "\(image)")
            XCTAssertGreaterThanOrEqual(fill.height + 0.0001, frame.height, "\(image)")
            let tight = abs(fill.width - frame.width) < 0.001 || abs(fill.height - frame.height) < 0.001
            XCTAssertTrue(tight, "覆う最小の大きさでない: \(image) → \(fill)")
            // 縦横比は写真のまま
            XCTAssertEqual(fill.width / fill.height, image.width / image.height, accuracy: 0.0001)
        }
    }

    func testZoomIsClampedBetweenOneAndThree() {
        XCTAssertEqual(FrameCropMath.clampZoom(0.2, maxZoom: CoverCropMath.maxZoom), 1)
        XCTAssertEqual(FrameCropMath.clampZoom(2, maxZoom: CoverCropMath.maxZoom), 2)
        XCTAssertEqual(FrameCropMath.clampZoom(40, maxZoom: CoverCropMath.maxZoom), 3)
    }

    func testOffsetNeverLeavesAGapInTheFrame() {
        let image = CGSize(width: 3000, height: 4000)   // 縦長: 等倍で幅 390・高さ 520
        let fill = FrameCropMath.fillSize(image: image, frame: frame)
        // 横には動かせない（幅がぴったり）、縦は (520 - 帯) / 2 まで
        let far = FrameCropMath.clamp(offset: CGSize(width: 999, height: 999), zoom: 1, image: image, frame: frame)
        XCTAssertEqual(far.width, 0, accuracy: 0.0001)
        XCTAssertEqual(far.height, (fill.height - frame.height) / 2, accuracy: 0.0001)
        let up = FrameCropMath.clamp(offset: CGSize(width: -999, height: -999), zoom: 1, image: image, frame: frame)
        XCTAssertEqual(up.height, -(fill.height - frame.height) / 2, accuracy: 0.0001)
        // 2倍なら横にも (780 - 390) / 2 = 195 まで
        let wide = FrameCropMath.clamp(offset: CGSize(width: 999, height: 0), zoom: 2, image: image, frame: frame)
        XCTAssertEqual(wide.width, 195, accuracy: 0.0001)
        // 範囲の中はそのまま
        let inside = FrameCropMath.clamp(offset: CGSize(width: 0, height: 10), zoom: 1, image: image, frame: frame)
        XCTAssertEqual(inside, CGSize(width: 0, height: 10))
    }

    func testCropRectIsInThePhotoPixels() {
        let image = CGSize(width: 3000, height: 4000)
        // 等倍・真ん中: 幅いっぱい（3000px）、高さは帯の比のぶん、上下の真ん中
        let center = FrameCropMath.cropRect(image: image, frame: frame, zoom: 1, offset: .zero, maxZoom: CoverCropMath.maxZoom)
        let expectedHeight = 3000 * frame.height / frame.width
        XCTAssertEqual(center.minX, 0, accuracy: 0.001)
        XCTAssertEqual(center.width, 3000, accuracy: 0.001)
        XCTAssertEqual(center.height, expectedHeight, accuracy: 0.001)
        XCTAssertEqual(center.midY, 2000, accuracy: 0.001)
        // 範囲の縦横比は枠と同じ（帯に歪まず収まる）
        XCTAssertEqual(center.width / center.height, frame.width / frame.height, accuracy: 0.0001)

        // 写真を下へいっぱい動かす＝写真の上端が帯の上端に来る（範囲は写真の上端から）
        let top = FrameCropMath.cropRect(image: image, frame: frame, zoom: 1, offset: CGSize(width: 0, height: 9999),
                                         maxZoom: CoverCropMath.maxZoom)
        XCTAssertEqual(top.minY, 0, accuracy: 0.001)
        // 上へいっぱい＝写真の下端
        let bottom = FrameCropMath.cropRect(image: image, frame: frame, zoom: 1, offset: CGSize(width: 0, height: -9999),
                                            maxZoom: CoverCropMath.maxZoom)
        XCTAssertEqual(bottom.maxY, 4000, accuracy: 0.001)

        // 画面で 10pt 下へ動かすと、範囲は写真の画素で 10 × (3000 / 390) だけ上へ
        let moved = FrameCropMath.cropRect(image: image, frame: frame, zoom: 1, offset: CGSize(width: 0, height: 10),
                                           maxZoom: CoverCropMath.maxZoom)
        XCTAssertEqual(center.minY - moved.minY, 10 * 3000 / 390, accuracy: 0.001)

        // 2倍: 範囲は半分。3倍を超えても 3倍で止まる
        let twice = FrameCropMath.cropRect(image: image, frame: frame, zoom: 2, offset: .zero, maxZoom: CoverCropMath.maxZoom)
        XCTAssertEqual(twice.width, 1500, accuracy: 0.001)
        let over = FrameCropMath.cropRect(image: image, frame: frame, zoom: 10, offset: .zero, maxZoom: CoverCropMath.maxZoom)
        XCTAssertEqual(over.width, 1000, accuracy: 0.001)
        // 1倍未満にしても枠を覆う（範囲が写真からはみ出さない）
        let under = FrameCropMath.cropRect(image: image, frame: frame, zoom: 0.3, offset: .zero, maxZoom: CoverCropMath.maxZoom)
        XCTAssertEqual(under.width, 3000, accuracy: 0.001)
    }

    func testCropRectDoesNotDependOnScreenWidth() {
        // 画面の幅が違っても（同じ縦横比なら）同じ範囲を切る＝表示倍率に左右されない
        let image = CGSize(width: 4000, height: 3000)
        let small = CGSize(width: 390, height: 240), large = CGSize(width: 780, height: 480)
        let a = FrameCropMath.cropRect(image: image, frame: small, zoom: 1.5, offset: CGSize(width: 30, height: -12), maxZoom: 3)
        let b = FrameCropMath.cropRect(image: image, frame: large, zoom: 1.5, offset: CGSize(width: 60, height: -24), maxZoom: 3)
        XCTAssertEqual(a.minX, b.minX, accuracy: 0.001)
        XCTAssertEqual(a.minY, b.minY, accuracy: 0.001)
        XCTAssertEqual(a.width, b.width, accuracy: 0.001)
        XCTAssertEqual(a.height, b.height, accuracy: 0.001)
        // どの位置・倍率でも写真の中に収まる
        for zoom in [1.0, 1.7, 3.0] {
            for offset in [CGSize(width: -9999, height: -9999), CGSize(width: 9999, height: 9999), .zero] {
                let r = FrameCropMath.cropRect(image: image, frame: small, zoom: zoom, offset: offset, maxZoom: 3)
                XCTAssertGreaterThanOrEqual(r.minX, -0.001)
                XCTAssertGreaterThanOrEqual(r.minY, -0.001)
                XCTAssertLessThanOrEqual(r.maxX, image.width + 0.001)
                XCTAssertLessThanOrEqual(r.maxY, image.height + 0.001)
            }
        }
    }

    func testOutputKeepsLongSideWithinUploadLimit() {
        // いままでのカバーと同じ長い辺 1920（`ImagePreparer.maxPixelSize`）
        XCTAssertEqual(CoverCropMath.outputLongSide, ImagePreparer.maxPixelSize)
        let big = CoverCropMath.outputSize(crop: CGSize(width: 4096, height: 2520.6))
        XCTAssertEqual(big.width, 1920)
        XCTAssertEqual(big.height, (2520.6 * 1920 / 4096).rounded())
        // 元より大きくはしない（拡大して切った小さい範囲は、その画素のまま）
        let small = CoverCropMath.outputSize(crop: CGSize(width: 1000, height: 615.4))
        XCTAssertEqual(small, CGSize(width: 1000, height: 615))
    }
}
