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

    // MARK: - 項目7 写真の編集の「元の写真」

    /// 右下の印は**触れたらすぐ**元の写真（写真の長押しのように待たない）。離したら戻る
    func testOriginalButtonComparesWhileHeld() {
        var screen = PhotoEditScreen(original: PhotoRecipe(exposure: 0.4))
        XCTAssertFalse(screen.showsBeforeLabel)
        screen.press(.holdOriginal(at: Date()))
        XCTAssertTrue(screen.showsBeforeLabel, "印に触れても元の写真が出ない")
        XCTAssertEqual(screen.displayed, .identity, "出すのは元の写真（無編集）")
        screen.press(.ended)
        XCTAssertFalse(screen.showsBeforeLabel, "離しても元の写真のまま")
        XCTAssertEqual(screen.displayed, screen.current)
        XCTAssertEqual(PhotoEditScreen.originalButtonLabel, "元の写真")
    }

    /// 説明の一言を外し、写真の右下に印を置く。写真の長押し（近道）は残す
    func testPhotoEditShowsTheOriginalButtonInsteadOfTheHint() throws {
        let view = try source("Features/Upload/PhotoEditView.swift")
        XCTAssertFalse(view.contains(#"L("写真を長押しすると、編集前と比べられます""#), "説明の一言が残っている")
        XCTAssertTrue(view.contains(".overlay(alignment: .bottomTrailing) { originalButton }"), "右下に「元の写真」が無い")
        XCTAssertTrue(view.contains("screen.press(.holdOriginal(at: Date()))"))
        XCTAssertTrue(view.contains(".frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)"),
                      "印の当たりが 44 でない")
        XCTAssertTrue(view.contains("screen.press(.tick(now: Date()))"), "写真の長押しの近道が無くなった")
    }

    // MARK: - 項目22 参加したアルバムを一覧から消す

    /// 払うだけだった「一覧から消す」を、右の「…」にも置く（自分のアルバムと同じ形）。払いも近道で残す
    func testJoinedAlbumHasVisibleMenu() throws {
        let view = try source("Features/Albums/AlbumsView.swift")
        XCTAssertTrue(view.contains("joinedMenu(entry)"), "参加しているアルバムの行に「…」が無い")
        guard let start = view.range(of: "private func joinedMenu(") else { return XCTFail("joinedMenu が無い") }
        let menu = String(view[start.lowerBound...].prefix(900))
        XCTAssertTrue(menu.contains("joined.forget(id: entry.id)"), "「…」から一覧から消せない")
        XCTAssertTrue(menu.contains(#"L("一覧から消す", "Remove")"#))
        XCTAssertTrue(menu.contains(".frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)"), "「…」の当たりが 44 でない")
        XCTAssertEqual(view.components(separatedBy: "joined.forget(id: entry.id)").count - 1, 2,
                       "払いの近道か「…」のどちらかが無い")
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
