import XCTest
@testable import JourneyPhoto

/// ホームの1枚に重ねる文字（板 01c: 「金沢」／「名前 · 2日前」）
final class HomeTileTextTests: XCTestCase {

    func testPlaceTakesFirstSegment() {
        XCTAssertEqual(HomeTileText.place("パリ, フランス"), "パリ")
        XCTAssertEqual(HomeTileText.place("金沢、石川県"), "金沢")
        XCTAssertEqual(HomeTileText.place(" 鍋ヶ滝 "), "鍋ヶ滝")
    }

    /// 撮影地が無い写真には文字を重ねない（空を返す）
    func testPlaceEmpty() {
        XCTAssertEqual(HomeTileText.place(nil), "")
        XCTAssertEqual(HomeTileText.place("  "), "")
        XCTAssertEqual(HomeTileText.place(", フランス"), "フランス")
    }

    func testBylineAddsAgoOnlyWhenGiven() {
        XCTAssertEqual(HomeTileText.byline(author: "旅人", ago: "2日前"), "旅人 · 2日前")
        XCTAssertEqual(HomeTileText.byline(author: "旅人", ago: nil), "旅人")
        XCTAssertEqual(HomeTileText.byline(author: "旅人", ago: ""), "旅人")
    }
}
