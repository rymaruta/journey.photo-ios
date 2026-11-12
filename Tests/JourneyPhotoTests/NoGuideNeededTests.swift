import XCTest
@testable import JourneyPhoto

/// 資料「説明なしで分かるアプリ」（2026-11-12・札 #517）の 1.1.85 束H。
/// 見ても何が起きるか分からない所を、言葉・見える印・⋯ の行で直す。画面は Linux で描けないので、
/// 言葉は純の関数で、置き方は書いてあるもので見る
final class NoGuideNeededTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    // MARK: - 項目16 ≡ の乗車券の行の一言

    /// 「入り切り」をやめ、押すと何ができるかで言う。オンの人には「オフにする」
    func testPassMenuNoteSaysWhatHappens() throws {
        XCTAssertEqual(PassTicket.menuNote(enabled: false), "届いたカードを見る、オンにする")
        XCTAssertEqual(PassTicket.menuNote(enabled: true), "届いたカードを見る、オフにする")
        let menu = try source("Features/Common/SiteMenuView.swift")
        XCTAssertTrue(menu.contains("note: PassTicket.menuNote(enabled: pass.settings.enabled)"),
                      "≡ の乗車券の行が一言を使っていない")
        XCTAssertFalse(menu.contains("入り切り\", "), "≡ の行に「入り切り」が残っている")
    }
}
