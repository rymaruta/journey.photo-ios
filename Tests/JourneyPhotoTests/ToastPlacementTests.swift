import XCTest
@testable import JourneyPhoto

/// 知らせ（トースト）が地図の札の「行きたい」を覆わない（2026-11-20・run 1604 と 1608 の `testMapSpotCardWishAndTapMapToClose`）。
///
/// run 1608 の数（iPhone 18 Pro Max の模擬機）: 画面の下端 956、札の上端 467.3、「行きたい」の枠 y 779〜823。
/// 知らせはいつも下から 116（2行で約 780〜840）に出て「行きたい」に重なり、もう一度押すと知らせを閉じるだけだった
final class ToastPlacementTests: XCTestCase {

    func testToastGoesAboveTheMapCard() {
        XCTAssertEqual(ToastPlacement.bottomPadding(containerMaxY: 956, keepClearAbove: nil), 116)
        let padding = ToastPlacement.bottomPadding(containerMaxY: 956, keepClearAbove: 467.3)
        let toastBottom = 956 - padding
        XCTAssertLessThan(toastBottom, 467.3, "知らせが札に重なる")
        XCTAssertLessThan(toastBottom, 779, "知らせが「行きたい」に重なる")
        // 札が低い（下端近く）でも、いつもの所より下には出さない
        XCTAssertEqual(ToastPlacement.bottomPadding(containerMaxY: 956, keepClearAbove: 900), 116)
        // 壊れた値ではいつもの所
        XCTAssertEqual(ToastPlacement.bottomPadding(containerMaxY: 956, keepClearAbove: .infinity), 116)
        XCTAssertEqual(ToastPlacement.bottomPadding(containerMaxY: 956, keepClearAbove: 1200), 116)
    }

    /// 地図の札が出ている間だけ上端を置き、消えたら外す。知らせはその値で高さを決める
    func testMapCardAndRootAreWired() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto")
        let map = try String(contentsOf: root.appendingPathComponent("Features/Map/PhotoMapView.swift"), encoding: .utf8)
        let card = try XCTUnwrap(map.range(of: "private func officialCard("))
        let end = try XCTUnwrap(map.range(of: ".accessibilityIdentifier(\"map.officialCard\")", range: card.upperBound..<map.endIndex))
        let body = map[card.upperBound..<end.lowerBound]
        XCTAssertTrue(body.contains("toasts.keepClearAbove = top"), "地図の札が知らせに上端を渡していない")
        XCTAssertTrue(body.contains(".onDisappear { toasts.keepClearAbove = nil }"), "札が消えても知らせが上に残る")
        let rootView = try String(contentsOf: root.appendingPathComponent("App/RootView.swift"), encoding: .utf8)
        XCTAssertTrue(rootView.contains("ToastPlacement.bottomPadding(containerMaxY:"), "知らせが覆ってはいけない所を見ていない")
        XCTAssertFalse(rootView.contains("ToastOverlay().padding(.bottom, 116)"))
    }
}
