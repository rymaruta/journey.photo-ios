import XCTest
@testable import JourneyPhoto

/// SNS 共有カードの安全域の基準（2026-11-14 判断・`ShareCardSafeArea`）。描く処理を通さず、全部の比で確かめる
final class ShareCardSafeAreaTests: XCTestCase {
    typealias R = SignatureShareCardRenderer

    func testEdgeIsSixPercentOfTheShortSideInEveryRatio() {
        for ratio in [R.Ratio.portrait, .story, .square] {
            let height = 1080 / CGFloat(ratio.rawValue)
            let safe = ShareCardSafeArea.rect(ratio: ratio)
            XCTAssertEqual(safe.minX, 64.8, accuracy: 0.001, "\(ratio)")
            XCTAssertEqual(1080 - safe.maxX, 64.8, accuracy: 0.001, "\(ratio)")
            if ratio == .story {
                // 9:16（1080×1920）: 上はフィードの 4:5 の切り取り（285）+ 6%（64.8）= 349.8（ストーリーの帯 14% = 268.8 より内側）・
                // 下は返信欄の 20% = 384（4:5 の切り取りの 349.8 より内側）。2026-11-14 判断
                XCTAssertEqual(safe.minY, 349.8, accuracy: 0.001)
                XCTAssertEqual(height - safe.maxY, 384, accuracy: 0.001)
            } else {
                XCTAssertEqual(safe.minY, 64.8, accuracy: 0.001, "\(ratio)")
                XCTAssertEqual(height - safe.maxY, 64.8, accuracy: 0.001, "\(ratio)")
            }
        }
    }

    func testStoryBandsUseTheTallerOfEdgeAndBand() {
        // 短い辺の 6% が帯より大きいときは、6% を取る（どちらか大きい方）
        let wide = ShareCardSafeArea.rect(width: 2000, height: 400, isStory: true)
        XCTAssertEqual(wide.minY, 56, accuracy: 0.001)
        XCTAssertEqual(400 - wide.maxY, 80, accuracy: 0.001)
        XCTAssertEqual(wide.minX, 24, accuracy: 0.001)
    }

    func testOverflowAndEdgeDistances() {
        let safe = ShareCardSafeArea.rect(ratio: .portrait)
        XCTAssertTrue(ShareCardSafeArea.overflow(of: CGRect(x: 65, y: 65, width: 900, height: 1200), in: safe).isInside)
        let over = ShareCardSafeArea.overflow(of: CGRect(x: 60, y: 40, width: 960, height: 1290), in: safe)
        XCTAssertEqual(over.left, 4.8, accuracy: 0.001)
        XCTAssertEqual(over.top, 24.8, accuracy: 0.001)
        XCTAssertEqual(over.right, 4.8, accuracy: 0.001)
        XCTAssertFalse(over.isInside)
        let edges = ShareCardSafeArea.edgeDistances(of: CGRect(x: 54, y: 108, width: 972, height: 1080),
                                                    width: 1080, height: 1350)
        XCTAssertEqual(edges[0], 0.05, accuracy: 0.0001)
        XCTAssertEqual(edges[1], 0.10, accuracy: 0.0001)
        XCTAssertEqual(edges[2], 0.05, accuracy: 0.0001)
        XCTAssertEqual(edges[3], 0.15, accuracy: 0.0001)
    }

    func testContrastMatchesTheBoardValues() {
        let white = ShareCardSafeArea.luminance(red: 255, green: 255, blue: 255)
        let black = ShareCardSafeArea.luminance(red: 0, green: 0, blue: 0)
        XCTAssertEqual(ShareCardSafeArea.contrast(white, black), 21, accuracy: 0.01)
        // 板の値: 真鍮 #C9A66B は黒の上で 9.15、墨 #07090A は白 94% #F0F0F0 の上で 17.51
        let brass = ShareCardSafeArea.luminance(red: 201, green: 166, blue: 107)
        XCTAssertEqual(ShareCardSafeArea.contrast(brass, black), 9.15, accuracy: 0.02)
        let ink = ShareCardSafeArea.luminance(red: 7, green: 9, blue: 10)
        let primary = ShareCardSafeArea.luminance(red: 240, green: 240, blue: 240)
        XCTAssertEqual(ShareCardSafeArea.contrast(ink, primary), 17.51, accuracy: 0.05)
        XCTAssertEqual(ShareCardSafeArea.minimumTextContrast, 4.5)
    }

    // MARK: - SNS ごとの切り取り（2026-11-14 判断・owner「別の SNS に投稿しようとしたら変になる、みたいなことないよね？」）

    func testPlatformCropRects() {
        // 9:16 はフィードで 4:5（上下 285 ずつ）と 3:4（上下 240 ずつ）に切られる
        let feed = ShareCardSafeArea.PlatformCrop.feed4x5.rect(width: 1080, height: 1920)
        XCTAssertEqual(feed?.minY ?? 0, 285, accuracy: 0.001)
        XCTAssertEqual(feed?.height ?? 0, 1350, accuracy: 0.001)
        XCTAssertEqual(ShareCardSafeArea.PlatformCrop.feed3x4.rect(width: 1080, height: 1920)?.minY ?? 0, 240, accuracy: 0.001)
        // 4:5 と 1:1 はフィードでは切られない
        XCTAssertNil(ShareCardSafeArea.PlatformCrop.feed4x5.rect(width: 1080, height: 1350))
        XCTAssertNil(ShareCardSafeArea.PlatformCrop.feed3x4.rect(width: 1080, height: 1080))
        // 格子（3:4）は 4:5 の左右を 33.75 ずつ、1:1 の左右を 135 ずつ切る
        XCTAssertEqual(ShareCardSafeArea.PlatformCrop.grid3x4.rect(width: 1080, height: 1350)?.minX ?? 0, 33.75, accuracy: 0.001)
        XCTAssertEqual(ShareCardSafeArea.PlatformCrop.grid3x4.rect(width: 1080, height: 1080)?.minX ?? 0, 135, accuracy: 0.001)
    }

    /// どの比の安全域も、フィードの切り取り（4:5・3:4）の内側に、切り取りの端から短い辺の 6% 以上離れている。
    /// 安全域に 4:5 の切り取りを足す前（上 268.8）は、9:16 × 4:5 の上が 268.8 − 285 = −16.2（切り取りの外）で落ちる
    func testSafeAreaStaysInsideEveryFeedCropWithTheEdgeMargin() {
        for ratio in [R.Ratio.portrait, .story, .square] {
            let height = 1080 / CGFloat(ratio.rawValue)
            let safe = ShareCardSafeArea.rect(ratio: ratio)
            for crop in ShareCardSafeArea.PlatformCrop.allCases where crop.mustKeepText {
                guard let box = crop.rect(width: 1080, height: height) else { continue }
                let margin = min(box.width, box.height) * ShareCardSafeArea.edgeFraction
                XCTAssertGreaterThanOrEqual(safe.minY - box.minY, margin - 0.001, "\(ratio) \(crop) 上")
                XCTAssertGreaterThanOrEqual(box.maxY - safe.maxY, margin - 0.001, "\(ratio) \(crop) 下")
                XCTAssertGreaterThanOrEqual(safe.minX - box.minX, margin - 0.001, "\(ratio) \(crop) 左")
            }
        }
    }

    /// 格子（小さな見本）でも、4:5 の字は欠けない（左右 33.75 しか切られず、安全域は 64.8）
    func testPortraitSafeAreaSurvivesTheProfileGrid() {
        let safe = ShareCardSafeArea.rect(ratio: .portrait)
        let grid = ShareCardSafeArea.PlatformCrop.grid3x4.rect(width: 1080, height: 1350)
        XCTAssertNotNil(grid)
        if let grid { XCTAssertTrue(grid.contains(safe)) }
    }
}
