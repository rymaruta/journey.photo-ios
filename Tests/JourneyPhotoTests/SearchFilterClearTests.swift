import XCTest
@testable import JourneyPhoto

/// 検索の季節・時間帯フィルターは、横スクロールを戻さず一括解除できること。
final class SearchFilterClearTests: XCTestCase {
    private func searchViewSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(
            "Sources/JourneyPhoto/Features/Search/SearchView.swift"), encoding: .utf8)
    }

    func testClearAllControlIsVisibleOnlyWhenTimeFiltersAreActive() throws {
        let source = try searchViewSource()
        let start = try XCTUnwrap(source.range(of: "private var shootingTimeChips: some View {"))
        let end = try XCTUnwrap(source.range(of: "private var availableDayParts:", range: start.lowerBound..<source.endIndex))
        let body = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(body.contains("if !model.timeFilter.isEmpty"),
                      "季節・時間帯を選んだときだけ解除ボタンを表示する")
        XCTAssertTrue(body.contains("Text(L(\"すべて解除\", \"Clear all\"))"),
                      "解除操作の目的を日本語・英語で明示する")
        XCTAssertTrue(body.contains("model.clearTimeFilter()"),
                      "ボタンから既存の一括解除処理を呼ぶ")
        XCTAssertTrue(body.contains(".accessibilityIdentifier(\"search.clearTimeFilters\")"),
                      "UIテストから解除ボタンを特定できる")
    }

    func testClearControlStaysOutsideTheHorizontalChipScroll() throws {
        let source = try searchViewSource()
        let start = try XCTUnwrap(source.range(of: "private var shootingTimeChips: some View {"))
        let end = try XCTUnwrap(source.range(of: "private var availableDayParts:", range: start.lowerBound..<source.endIndex))
        let body = String(source[start.lowerBound..<end.lowerBound])
        let scroll = try XCTUnwrap(body.range(of: "ScrollView(.horizontal"))
        let clear = try XCTUnwrap(body.range(of: "search.clearTimeFilters"))

        XCTAssertTrue(body[..<scroll.lowerBound].contains("HStack"),
                      "チップと解除操作を横並びにする")
        XCTAssertLessThan(scroll.lowerBound, clear.lowerBound)
        XCTAssertTrue(body[scroll.upperBound..<clear.lowerBound].contains("if !model.timeFilter.isEmpty"),
                      "横スクロールの外側に、条件付きの解除操作を置く")
    }
}
