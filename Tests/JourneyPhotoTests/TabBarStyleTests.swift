import XCTest
@testable import JourneyPhoto

/// 選んでいるタブの色（`TabBarStyle`）。**真鍮で、中身の白（`WebTheme.foreground`）ではない**
/// （owner の好み 2026-09-29。TabView の tint が中身の白に負けていた疑い・2026-10-02）
final class TabBarStyleTests: XCTestCase {

    func testSelectedTabIsBrass() {
        XCTAssertEqual(TabBarStyle.selectedHex, 0xC9A66B, "選んでいるタブが真鍮でない")
        XCTAssertEqual(TabBarStyle.selectedHex, BrandPalette.accent)
        XCTAssertNotEqual(TabBarStyle.selectedHex, 0xFFFFFF, "選んでいるタブが白（中身の tint）になっている")
    }
}
