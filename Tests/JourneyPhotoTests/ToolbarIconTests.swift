import XCTest
@testable import JourneyPhoto

/// 上のバーのアイコンの大きさと当たり（`webToolbarIcon`・2026-10-14）。
///
/// 17pt では黒地で沈む → 22pt semibold ＋ 44 の枠で iOS 26 のガラスの帯が太り「デカすぎる」
/// （owner）→ 19pt regular・見た目の箱 28・当たり 44。絵は Linux で描けないので、
/// 値と、帯に渡す寸法を 44 に戻していないこと（ソース）を縛る
final class ToolbarIconTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path),
                              encoding: .utf8)
        // 注記（`//`・`///`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// システムの 17pt より大きく（沈まない）、前の 22pt より小さい（デカすぎない）
    func testIconSizeIsBetweenSystemAndOldValue() {
        XCTAssertEqual(WebTheme.toolbarIconSize, 19)
        XCTAssertGreaterThan(WebTheme.toolbarIconSize, 17, "システムの既定（17pt）では黒地で沈む")
        XCTAssertLessThan(WebTheme.toolbarIconSize, 22, "22pt はガラスの帯の中で大きすぎた")
    }

    /// 見た目の箱は 19pt の絵が収まり、44 より小さい。当たりは箱＋両側の余白でちょうど 44
    func testHitAreaStays44WhileLayoutBoxIsSmaller() {
        XCTAssertGreaterThanOrEqual(WebTheme.toolbarIconBox, WebTheme.toolbarIconSize + 4,
                                    "19pt の絵（約 21〜23pt）が箱に収まらない")
        XCTAssertLessThan(WebTheme.toolbarIconBox, WebTheme.minTapTarget,
                          "帯に渡す寸法が 44 のままだと、帯が太ったまま")
        XCTAssertEqual(WebTheme.toolbarIconBox + 2 * WebTheme.toolbarHitSlack, WebTheme.minTapTarget,
                       "当たりが 44 にならない")
        XCTAssertGreaterThan(WebTheme.toolbarHitSlack, 0)
    }

    /// 未読の点は絵の右上の角に（板 01）。44 の枠を前提にした内寄せ（-8, 10）には戻さない
    func testUnreadDotSitsOnTheIconCorner() {
        let o = WebTheme.toolbarBadgeOffset
        XCTAssertLessThanOrEqual(abs(o.x), 2, "点が絵の角から横に離れすぎ")
        XCTAssertLessThanOrEqual(abs(o.y), 2, "点が絵の角から縦に離れすぎ")
    }

    /// 🔴 `webToolbarIcon` が並びの寸法を 44 に戻していない（`webTappable` を使うと帯が太る）。
    /// 字は太字（semibold）にしない。当たりの広げ方（負の余白）が残っている
    func testToolbarIconDoesNotInflateTheGlassBand() throws {
        let theme = try source("Core/Design/WebTheme.swift")
        guard let start = theme.range(of: "func webToolbarIcon()"),
              let end = theme.range(of: "func webTappable()") else {
            return XCTFail("webToolbarIcon / webTappable が見つからない")
        }
        let body = String(theme[start.lowerBound..<end.lowerBound])
        XCTAssertFalse(body.contains(".webTappable()"), "バーのアイコンに 44 の枠（webTappable）が戻っている")
        XCTAssertFalse(body.contains("minTapTarget, minHeight: WebTheme.minTapTarget"),
                       "バーのアイコンの並びの寸法が 44 になっている")
        XCTAssertFalse(body.contains(".semibold"), "バーのアイコンが太字に戻っている")
        XCTAssertTrue(body.contains("WebTheme.toolbarIconSize"))
        XCTAssertTrue(body.contains(".padding(-WebTheme.toolbarHitSlack)"),
                      "当たりを 44 に広げたあと、並びの寸法を箱に戻していない")
        XCTAssertTrue(body.contains(".contentShape(Rectangle())"))
    }

    /// 見出しの3つ（探す・お知らせ・メニュー）がどれも同じ作りを通る。点の位置は値から
    func testAppHeaderUsesTheSharedIconAndOffset() throws {
        let header = try source("Features/Common/AppHeader.swift")
        XCTAssertEqual(header.components(separatedBy: ".webToolbarIcon()").count - 1, 3)
        XCTAssertTrue(header.contains("WebTheme.toolbarBadgeOffset.x"))
        XCTAssertFalse(header.contains(".offset(x: -8, y: 10)"), "44 の枠を前提にした点の位置が残っている")
    }
}
