import XCTest
@testable import JourneyPhoto

/// 色の組が読めるか（WCAG の比）を見張る。
///
/// 線は **文字 4.5:1・部品の縁と大きい文字 3:1**。値を変えたらここが
/// 比を計算し直すので、「見た目の調整で知らないうちに読めなくなる」を止める。
/// 期待値はサイトの `textContrast.test.ts` と同じ式で node が出した値。
final class BrandPaletteTests: XCTestCase {

    private typealias P = BrandPalette

    private func assertAtLeast(_ fg: UInt32, on bg: UInt32, _ minimum: Double,
                               _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let ratio = P.contrast(fg, bg)
        XCTAssertGreaterThanOrEqual(ratio, minimum,
                                    "\(what): \(String(format: "%.2f", ratio)) < \(minimum)",
                                    file: file, line: line)
    }

    /// 式そのものが合っていること（白と黒は 21:1、同じ色は 1:1）
    func testFormulaMatchesWCAG() {
        XCTAssertEqual(P.contrast(0xFFFFFF, 0x000000), 21, accuracy: 0.001)
        XCTAssertEqual(P.contrast(0x777777, 0x777777), 1, accuracy: 0.001)
        // node で出した値と一致する（小数2桁）
        XCTAssertEqual(P.contrast(P.accent, P.background), 9.15, accuracy: 0.005)
        XCTAssertEqual(P.contrast(P.ink, P.accentFill), 7.11, accuracy: 0.005)
        XCTAssertEqual(P.contrast(0xFFFFFF, P.accentDeep), 5.66, accuracy: 0.005)
    }

    /// 真鍮を文字に使う場所（黒・カード・入力欄・案内の帯の上）
    func testAccentTextIsReadable() {
        assertAtLeast(P.accent, on: P.background, 4.5, "真鍮 / 黒")
        assertAtLeast(P.accent, on: P.surface, 4.5, "真鍮 / カード")
        assertAtLeast(P.accent, on: P.surface2, 4.5, "真鍮 / 入力欄")
        assertAtLeast(P.accent, on: P.accentSoft, 4.5, "真鍮 / 案内の帯")
        assertAtLeast(P.accentStrong, on: P.background, 4.5, "押している間の真鍮 / 黒")
    }

    /// 塗りの上の文字
    func testFillsCarryReadableText() {
        assertAtLeast(P.ink, on: P.accentFill, 4.5, "墨 / 真鍮の塗り")
        assertAtLeast(P.ink, on: P.accent, 4.5, "墨 / 真鍮（件数バッジ）")
        assertAtLeast(P.ink, on: P.primary, 4.5, "墨 / 白の主ボタン")
        assertAtLeast(0xFFFFFF, on: P.accentDeep, 4.5, "白 / 暗い真鍮（トグル・地図）")
        assertAtLeast(0xFFFFFF, on: P.dangerFill, 4.5, "白 / 削除の塗り")
    }

    /// **真鍮の塗りに白い字を載せない**——規則の根拠をここで固定する。
    /// 誰かが「白の方が映える」と塗りの字を白にしたくなったとき、
    /// この数字が止める
    func testWhiteOnBrassFillIsForbidden() {
        XCTAssertLessThan(P.contrast(0xFFFFFF, P.accentFill), 3.0)
        XCTAssertLessThan(P.contrast(0xFFFFFF, P.accent), 3.0)
    }

    /// 部品の縁（入力欄の枠・トグルの軌道・件数バッジ）は 3:1
    func testComponentEdges() {
        assertAtLeast(P.outline, on: P.background, 3, "枠 / 黒")
        assertAtLeast(P.outline, on: P.surface2, 3, "枠 / 入力欄")
        assertAtLeast(P.accentDeep, on: P.background, 3, "暗い真鍮 / 黒")
        assertAtLeast(P.accentDeep, on: P.surface, 3, "暗い真鍮 / カード")
    }

    /// 意味の色
    func testSemanticColors() {
        assertAtLeast(P.danger, on: P.background, 4.5, "危険 / 黒")
        assertAtLeast(P.danger, on: P.surface2, 4.5, "危険 / 入力欄")
        assertAtLeast(P.success, on: P.background, 3, "成功のアイコン / 黒")
        assertAtLeast(P.location, on: P.background, 3, "現在地 / 黒")
        assertAtLeast(P.chipText, on: P.surface, 4.5, "チップの字 / カード")
    }
}
