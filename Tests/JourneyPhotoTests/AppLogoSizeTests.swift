import Foundation
import XCTest
@testable import JourneyPhoto

/// ロゴの印（アパーチャ）の大きさ。2026-11-25 owner「このロゴが小さい」（ログイン画面の画面写真に赤丸）。
///
/// 以前は枠が見出し 19・大きいロゴ 29.5 で、字に対する比が 0.86 と 0.74 に割れていた。
/// 比を1つにそろえ、見える絵（枠の約96%）を字の大きさの約0.9倍にした（`AppLogo.markRatio`）。
/// 見た目は ScreenshotTests の `testCapturesSignInLayout` で確かめる
final class AppLogoSizeTests: XCTestCase {

    /// 見出しと大きいロゴで、印と字の比が同じ（画面ごとに見た目を割らない）
    func testMarkRatioIsSameForBothSizes() {
        let header = AppLogo.markPoints(.header) / AppLogo.fontPoints(.header)
        let hero = AppLogo.markPoints(.hero) / AppLogo.fontPoints(.hero)
        XCTAssertEqual(header, hero, accuracy: 0.001)
    }

    /// 見える絵（枠の96%）が大文字の高さ（0.70）より大きく、行の高さ（約1.2）より小さい
    func testVisibleMarkIsBetweenCapHeightAndLineHeight() {
        for size in [AppLogo.Size.header, .hero, .points(32), .points(28)] {
            let font = AppLogo.fontPoints(size)
            let visible = AppLogo.markPoints(size) * 0.96
            XCTAssertGreaterThanOrEqual(visible, font * 0.85, "\(size): 印が字に負ける")
            XCTAssertLessThanOrEqual(visible, font * 1.0, "\(size): 印が行からはみ出す")
        }
        XCTAssertEqual(AppLogo.markPoints(.hero), 37.6, accuracy: 0.01)
        XCTAssertEqual(AppLogo.markPoints(.header), 20.68, accuracy: 0.01)
    }
}
