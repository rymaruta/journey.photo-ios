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
                // 9:16（1080×1920）: 上 14% = 268.8・下 20% = 384
                XCTAssertEqual(safe.minY, 268.8, accuracy: 0.001)
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
}
