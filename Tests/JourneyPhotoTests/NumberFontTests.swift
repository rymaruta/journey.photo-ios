import XCTest
import SwiftUI
@testable import JourneyPhoto

/// 数字の書体（SF Pro ＋ 等幅数字）が、頼まれた大きさにいちばん近い文字の種類を選ぶか。
/// 文字の種類で選ぶのは Dynamic Type に追従させるため（`JPFont.mono` の 2026-10-02 判断）
final class NumberFontTests: XCTestCase {

    private func style(_ size: Double, _ hint: Font.TextStyle = .caption) -> Font.TextStyle {
        JPFont.numberStyle(size: size, relativeTo: hint)
    }

    /// 標準の大きさちょうどなら、その種類
    func testExactSizes() {
        XCTAssertEqual(style(11), .caption2)
        XCTAssertEqual(style(12, .caption2), .caption)   // 12pt を 11pt に縮めない（本文系の最小）
        XCTAssertEqual(style(13), .footnote)
        XCTAssertEqual(style(15), .subheadline)
        XCTAssertEqual(style(16), .callout)
    }

    /// ずれる大きさは近い方。同じ近さなら relativeTo、それも無ければ大きい方
    func testNearestAndTies() {
        XCTAssertEqual(style(10), .caption2)
        XCTAssertEqual(style(14), .subheadline)            // 13 と 15 の真ん中 → 大きい方
        XCTAssertEqual(style(14, .footnote), .footnote)    // 決め手があればそちら
        XCTAssertEqual(style(18, .title3), .body)          // 17 の方が近い
        XCTAssertEqual(style(24, .title), .title2)         // 22 の方が近い
    }

    /// headline（body と同じ 17pt）は選ばない。表は小さい順
    func testTableIsAscendingWithoutHeadline() {
        let sizes = JPFont.standardSizes.map(\.size)
        XCTAssertEqual(sizes, sizes.sorted())
        XCTAssertFalse(JPFont.standardSizes.contains { $0.style == .headline })
    }
}
