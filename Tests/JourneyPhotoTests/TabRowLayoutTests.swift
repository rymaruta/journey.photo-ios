import XCTest
@testable import JourneyPhoto

/// マイページのタブの並べ方（板 05c の flex-grow）
final class TabRowLayoutTests: XCTestCase {

    /// 入るなら、どの札も中身の幅以上（長い名前が切れない）で、余りは等分
    func testFitsGivesEachAtLeastItsIdealWidth() {
        let ideals: [CGFloat] = [47, 73, 99, 86]
        let widths = TabRowLayout.widths(ideals: ideals, available: 343)
        XCTAssertEqual(widths.reduce(0, +), 343, accuracy: 0.001)
        for (width, ideal) in zip(widths, ideals) {
            XCTAssertGreaterThanOrEqual(width, ideal, "等分だと「行きたい場所」(99) が 86 に押し込まれた")
        }
    }

    /// 入らなければ中身の比で縮める（長い名前ほど広い）
    func testOverflowShrinksProportionally() {
        let widths = TabRowLayout.widths(ideals: [50, 100], available: 120)
        XCTAssertEqual(widths[0], 40, accuracy: 0.001)
        XCTAssertEqual(widths[1], 80, accuracy: 0.001)
    }

    func testEmpty() {
        XCTAssertEqual(TabRowLayout.widths(ideals: [], available: 100), [])
    }
}
