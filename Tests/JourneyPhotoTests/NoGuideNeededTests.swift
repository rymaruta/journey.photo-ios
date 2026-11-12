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

    // MARK: - 項目6 ホームの札「現像前の旅」

    /// 札の題は中身の名前、3行目はどこから見つけたか。「現像」の言葉を札に出さない
    func testDevelopCardSaysWhatItIs() throws {
        XCTAssertEqual(DevelopTrips.cardTitle, "まだ載せていない旅")
        XCTAssertEqual(DevelopTrips.cardDetail(limited: false), "写真アプリから見つけました")
        XCTAssertEqual(DevelopTrips.cardDetail(limited: true), "選んで許可した写真の中から見つけました")
        XCTAssertEqual(DevelopTrips.resumePrefix(done: 4, total: 10), "続きから 4 / 10、")
        XCTAssertFalse(DevelopTrips.cardEyebrowSpoken.contains("現像"))
        let view = try source("Features/Gallery/HomeTopCardView.swift")
        XCTAssertTrue(view.contains("title: DevelopTrips.cardTitle,"), "札の題が「まだ載せていない旅」でない")
        XCTAssertTrue(view.contains("eyebrow: DevelopTrips.cardEyebrow, eyebrowLabel: DevelopTrips.cardEyebrowSpoken"))
        XCTAssertNil(view.range(of: #"L\("[^"]*現像"#, options: .regularExpression),
                     "ホームの札の字に「現像」が残っている")
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
