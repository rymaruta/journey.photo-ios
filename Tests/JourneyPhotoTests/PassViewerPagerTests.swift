import XCTest
@testable import JourneyPhoto

/// すれちがいの束の「‹ 1 / 7 枚 ›」（2026-11-14 判断・人間工学の点検・WCAG 2.5.1・`PassViewerPager`）。
/// 払わなくても押して前・次の乗車券へ行ける。払う・回す操作は残す
final class PassViewerPagerTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        // 注記（`//`・`///`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// 最初では前へ、最後では次へ行けない。1枚だけなら両方とも行けない
    func testEdges() {
        XCTAssertFalse(PassViewerPager.canGoBack(index: 0, count: 7), "最初の1枚で ‹ を押せる")
        XCTAssertTrue(PassViewerPager.canGoForward(index: 0, count: 7))
        XCTAssertTrue(PassViewerPager.canGoBack(index: 3, count: 7))
        XCTAssertTrue(PassViewerPager.canGoForward(index: 3, count: 7))
        XCTAssertTrue(PassViewerPager.canGoBack(index: 6, count: 7))
        XCTAssertFalse(PassViewerPager.canGoForward(index: 6, count: 7), "最後の1枚で › を押せる")
        XCTAssertFalse(PassViewerPager.canGoBack(index: 0, count: 1))
        XCTAssertFalse(PassViewerPager.canGoForward(index: 0, count: 1))
        XCTAssertFalse(PassViewerPager.canGoBack(index: 0, count: 0))
        XCTAssertFalse(PassViewerPager.canGoForward(index: 0, count: 0))
    }

    /// 枚数の字・読み上げの名前は「乗車券」・押せない側は板の 32%
    func testWordsAndDim() {
        XCTAssertEqual(PassViewerPager.countText(index: 1, count: 7), "2 / 7 枚")
        XCTAssertEqual(PassViewerPager.previousLabel, "前の乗車券")
        XCTAssertEqual(PassViewerPager.nextLabel, "次の乗車券")
        XCTAssertEqual(PassViewerPager.disabledOpacity, 0.32)
    }

    /// 束の画面のつなぎ: 下のボタンの行の上に「‹ 枚数 ›」・押せない側は押せなくする・払う操作と読み上げの操作は残す・
    /// 上の眉の下に枚数を重ねて出さない・案内は「次のカード」を言わない（ボタンで分かる）
    func testViewerWiring() throws {
        let viewer = try source("Features/Pass/PassViewerView.swift")
        for part in ["pager\n                    actions(current)",
                     "PassViewerPager.canGoBack(index: index, count: count)",
                     "PassViewerPager.canGoForward(index: index, count: count)",
                     ".disabled(!enabled)", ".opacity(enabled ? 1 : PassViewerPager.disabledOpacity)",
                     ".accessibilityLabel(label)", ".webTappable()",
                     // 払う・回す操作（速さの境目は変えない）と読み上げの操作は残す
                     // 読み上げの操作の名前は「次の乗車券」（呼び名の統一・`PassWordingTests`・2026-11-14 統合 1.1.89）
                     "PassSpinGesture.classify(", "accessibilityAction(named: L(\"次の乗車券\""] {
            XCTAssertTrue(viewer.contains(part), "束の画面に \(part) が無い")
        }
        XCTAssertEqual(viewer.components(separatedBy: "PassViewerPager.countText(").count - 1, 1,
                       "枚数を2か所に出している（上の眉の下に残っている）")
        XCTAssertFalse(viewer.contains("払って次のカード"), "案内がまだ払って次へ行く説明をしている")
        XCTAssertFalse(viewer.contains("素早く払うと次のカード"), "案内がまだ払って次へ行く説明をしている")
        // 速さの境目は変えていない（2026-11-14: 変える根拠の数字が無い）
        XCTAssertEqual(PassSpinGesture.flickDuration, 0.25)
        XCTAssertEqual(PassSpinGesture.flickDistance, 200)
        XCTAssertEqual(PassSpinGesture.flickTravel, 120)
    }
}
