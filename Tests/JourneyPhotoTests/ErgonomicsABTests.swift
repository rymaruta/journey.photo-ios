import XCTest
@testable import JourneyPhoto

/// 人間工学の確かめ（2026-11-25・Artifact「人間工学アーティファクト」）で基準から外れていた2か所の直し。
///
/// - A（観点3）: 上の右の当たりの間を 6pt ずつ空ける（当たりは 44 のまま、中心の間 50pt 以上）
/// - B（観点15）: ホームの「フォロー中の人の新しい写真」の終わりに「新しい写真は、ここまでです」の1行
///
/// 画面の部品は Linux で動かせないので、決まりは値で、配線は元のコードを読んで確かめる
/// （`UXAuditFixesATests` と同じやり方）。各試験は直しを戻すと落ちる
@MainActor
final class ErgonomicsABTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path),
                              encoding: .utf8)
        // 注記（`//`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func slice(_ text: String, from start: String, to end: String) -> String {
        guard let head = text.range(of: start) else { return "" }
        let rest = text[head.lowerBound...]
        guard let tail = rest.range(of: end, range: rest.index(after: rest.startIndex)..<rest.endIndex) else {
            return String(rest)
        }
        return String(rest[..<tail.lowerBound])
    }

    // MARK: - A. 上の右の当たりの間

    /// 当たりの間は 6pt 以上、中心の間は 50pt 以上（当たり 44 ＋ 間）
    func testHeaderHitAreasHaveGap() async throws {
        XCTAssertGreaterThanOrEqual(AppHeaderItems.buttonGap, 6, "当たりの間が 6pt より狭い")
        XCTAssertGreaterThanOrEqual(WebTheme.minTapTarget + AppHeaderItems.buttonGap, 50, "当たりの中心の間が 50pt より狭い")
        let header = try source("Features/Common/AppHeader.swift")
        let trailing = slice(header, from: "ToolbarItem(placement: .topBarTrailing)", to: "struct AskEntryButton")
        XCTAssertTrue(trailing.contains("HStack(spacing: Self.buttonGap)"), "右の並びの間が空いていない")
        XCTAssertFalse(trailing.contains("HStack(spacing: 0)"), "右の並びが隙間なしに戻っている")
    }

    /// 当たりは 44 のまま、絵の大きさも変えない。未読の点は絵の箱に付き、当たりの外の間に付かない（位置がずれない）
    func testHeaderIconsAndDotsStayTheSame() async throws {
        XCTAssertEqual(WebTheme.minTapTarget, 44)
        let header = try source("Features/Common/AppHeader.swift")
        let hit = slice(header, from: "func appHeaderHitArea()", to: "\n}\n")
        XCTAssertTrue(hit.contains(".frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)"), "当たりが 44 でない")
        XCTAssertEqual(header.components(separatedBy: ".webToolbarIcon()").count - 1, 3)
        // 点（`headerDot`）は `.webToolbarIcon()` の直後の overlay で付け、そのあとに当たりを広げる
        let messages = slice(header, from: "Image(systemName: AppHeaderInbox.messagesSymbol)", to: ".appHeaderHitArea()")
        let bell = slice(header, from: "Image(systemName: AppHeaderInbox.bellSymbol)", to: ".appHeaderHitArea()")
        XCTAssertTrue(messages.contains(".webToolbarIcon()") && messages.contains("headerDot"), "メッセージの点が絵の箱に付いていない")
        XCTAssertTrue(bell.contains(".webToolbarIcon()") && bell.contains("headerDot"), "お知らせの点が絵の箱に付いていない")
    }

    /// 帯が 18pt 長くなっても、375pt の iPhone でロゴが右の丸に重ならない（見積もり）。字つきの入口は広い iPhone だけ
    func testHeaderStillFitsNarrowPhones() async {
        let margins: CGFloat = 16 * 2 + 16
        let gaps = AppHeaderItems.buttonGap * 3
        let logoMin: CGFloat = 19 + 8 + 150 * AppLogo.headerMinimumScale
        XCTAssertGreaterThanOrEqual(375 - (44 + 44 * 3 + gaps) - margins, logoMin, "375pt でロゴが重なる")
        XCTAssertGreaterThanOrEqual(22 * AppLogo.headerMinimumScale, WebTheme.minBodyText, "ロゴの字が 12pt を割る")
        XCTAssertTrue(AskEntryButton.iconOnly(largeText: false, windowWidth: 402), "402pt で字つきだとロゴが切れる")
        // Mac run 1818: 440pt でも字つきは帯のガラス（約209pt）に入らず、✦ がロゴの隣へはみ出した
        XCTAssertTrue(AskEntryButton.iconOnly(largeText: false, windowWidth: 440), "440pt で字つきだと帯からはみ出す")
        XCTAssertGreaterThanOrEqual(AskEntryButton.labelMinWindowWidth, 441)
        // 大きな字の設定では ✦ だけ（帯の幅は 375 の ✦ だけと同じ）
        XCTAssertTrue(AskEntryButton.iconOnly(largeText: true, windowWidth: 440))
    }

    // MARK: - B. フォロー中の新しい写真の終わりの1行

    func testFollowingEndNoteText() async {
        XCTAssertEqual(HomeFollowingEndNote.text, "新しい写真は、ここまでです")
        XCTAssertFalse(HomeFollowingEndNote.text.contains("・"), "中黒で区切らない")
        XCTAssertFalse(HomeFollowingEndNote.text.contains("·"))
    }

    /// 新しい写真の段の中、写真の並びのすぐ後ろに置く（段が無い日は出ない）
    func testFollowingEndNoteSitsAtTheEndOfTheFollowingSection() async throws {
        let gallery = try source("Features/Gallery/GalleryView.swift")
        let section = slice(gallery, from: "if !rows.following.isEmpty {", to: ".accessibilityIdentifier(\"home.following\")")
        XCTAssertFalse(section.isEmpty)
        guard let mosaic = section.range(of: "HomeMosaic(groups: rows.following"),
              let note = section.range(of: "HomeFollowingEndNote()") else {
            return XCTFail("新しい写真の段に終わりの1行が無い")
        }
        XCTAssertLessThan(mosaic.lowerBound, note.lowerBound, "終わりの1行が写真の前にある")
        // 読み込み中は並びごと描かない（骨格だけ）ので、終わりの1行も出ない
        let loading = slice(gallery, from: "case .loading:", to: "case .failed")
        XCTAssertFalse(loading.contains("feed("))
        XCTAssertFalse(loading.contains("HomeFollowingEndNote"))
        // ほかの並び（2.・3.）には付けない
        XCTAssertEqual(gallery.components(separatedBy: "HomeFollowingEndNote()").count - 1, 1)
    }

    /// 板どおり: 字は muted（text-3）の footnote（13pt・12pt 以上）、印は黒地の上の真鍮。押せない
    func testFollowingEndNoteFollowsTheBoard() async throws {
        let gallery = try source("Features/Gallery/GalleryView.swift")
        let note = slice(gallery, from: "struct HomeFollowingEndNote", to: "\n}\n")
        XCTAssertTrue(note.contains(".foregroundStyle(WebTheme.text3)"), "字が muted でない")
        XCTAssertTrue(note.contains(".font(JPFont.footnote)"), "字が footnote（13pt）でない")
        XCTAssertFalse(note.contains(".font(.system(size: 1"), "字を 12pt 未満に固定している")
        XCTAssertTrue(note.contains(".foregroundStyle(WebTheme.accent)"))
        XCTAssertFalse(note.contains("Button"), "読むだけの1行が押せる")
        XCTAssertTrue(note.contains("L(\"新しい写真は、ここまでです\", \"You're all caught up\")"))
    }
}
