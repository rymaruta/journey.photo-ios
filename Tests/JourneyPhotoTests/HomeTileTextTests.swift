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
    }

    /// 先頭が空の区切りは飛ばす（空の撮影地にしない）
    func testPlaceSkipsEmptyLeadingSegment() {
        XCTAssertEqual(HomeTileText.place(", フランス"), "フランス")
    }

    /// 題のある写真でも、絵の上の撮影地・名前・複数枚を読む
    func testReadoutIncludesOverlayText() {
        XCTAssertEqual(HomeTileText.readout(base: "朝の運河", place: "パリ", byline: "旅人 · 2日前", multiple: "複数枚の投稿"),
                       "朝の運河, パリ, 旅人 · 2日前, 複数枚の投稿")
        XCTAssertEqual(HomeTileText.readout(base: "朝の運河", place: "", byline: "旅人", multiple: nil),
                       "朝の運河, 旅人")
    }

    /// 題が無い写真は base が撮影地を含むので、撮影地を二度読まない
    func testReadoutDoesNotRepeatPlace() {
        XCTAssertEqual(HomeTileText.readout(base: "パリ, フランス の写真", place: "パリ", byline: "旅人", multiple: nil),
                       "パリ, フランス の写真, 旅人")
    }

    func testBylineAddsAgoOnlyWhenGiven() {
        XCTAssertEqual(HomeTileText.byline(author: "旅人", ago: "2日前"), "旅人 · 2日前")
        XCTAssertEqual(HomeTileText.byline(author: "旅人", ago: nil), "旅人")
        XCTAssertEqual(HomeTileText.byline(author: "旅人", ago: ""), "旅人")
    }
}
