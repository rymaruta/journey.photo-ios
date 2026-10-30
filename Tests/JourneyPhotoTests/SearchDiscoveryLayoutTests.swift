import XCTest
@testable import JourneyPhoto

/// 「さがす」の3点（2026-10-30 owner 採用・#419・Search の板 `project/Search.dc.html` の①②③）。
///
/// 画面は Linux では描けないので、`V2HomeSearchNotificationsTests` と同じく**値は数で**、
/// **部品の作りは元のファイルを読んで**見張る。どれも直しを戻すと落ちる
final class SearchDiscoveryLayoutTests: XCTestCase {

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

    private func slice(_ text: String, from start: String, to end: String,
                       file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let s = text.range(of: start) else {
            XCTFail("「\(start)」が無い", file: file, line: line)
            return ""
        }
        guard let e = text.range(of: end, range: s.upperBound..<text.endIndex) else {
            XCTFail("「\(end)」が「\(start)」の後に無い", file: file, line: line)
            return ""
        }
        return String(text[s.lowerBound..<e.lowerBound])
    }

    private func assertInOrder(_ parts: [String], in text: String, _ what: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        var cursor = text.startIndex
        for part in parts {
            guard let found = text.range(of: part, range: cursor..<text.endIndex) else {
                XCTFail("\(what): 「\(part)」が無いか、順が違う", file: file, line: line)
                return
            }
            cursor = found.upperBound
        }
    }

    private func photo(_ id: String, focal: String?) throws -> Photo {
        var exif = ""
        if let focal { exif = ",\"exif\":{\"focalLength\":\"\(focal)\"}" }
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\"\(exif)}".utf8))
    }

    // MARK: - ① 撮影地の札は名前だけ

    func testPlaceCardShowsNameOnly() throws {
        let search = try source("Features/Search/SearchView.swift")
        let card = slice(search, from: "private func spotCard(", to: "nonisolated static let spotNameBottomInset")
        XCTAssertFalse(card.contains("枚の写真"), "撮影地の札に枚数の行が残っている")
        XCTAssertFalse(card.contains("spot.count"), "撮影地の札に枚数を出している")
        XCTAssertFalse(card.contains("JPFont.meta"), "撮影地の札に枚数の行（等幅）が残っている")
        XCTAssertEqual(card.components(separatedBy: "Text(").count - 1, 1, "札の字は名前の1つだけ")
        // 札・写真・明朝の名前は今のまま
        assertInOrder([".frame(width: 156, height: 116)", "RemoteImage(url: spot.cover.gridImageURL",
                       "Text(LocationMatch.display(spot.id))", ".font(JPFont.rowTitle)",
                       ".foregroundStyle(Color.white)", ".padding(.bottom, Self.spotNameBottomInset)",
                       ".clipShape(RoundedRectangle(cornerRadius: JPRadius.m))"],
                      in: card, "札 → 写真 → 明朝の白い名前 → 下端から 10 → 角 14")
        XCTAssertEqual(SearchView.spotNameBottomInset, 10, "名前は札の下端から 10（板）")
    }

    // MARK: - ② 機材は横に並べた札

    func testGearCardMeasuresFollowTheBoard() {
        XCTAssertEqual(SearchView.gearCardHeight, 88)
        XCTAssertGreaterThanOrEqual(SearchView.gearCardHeight, WebTheme.minTapTarget, "札が押せる所の 44 に届かない")
        XCTAssertEqual(SearchView.gearCardSpacing, 8)
        XCTAssertEqual(SearchView.gearCardPaddingV, 10)
        XCTAssertEqual(SearchView.gearCardPaddingH, 12)
        XCTAssertEqual(SearchView.gearIconSize, 24)
        XCTAssertEqual(SearchView.gearIconGap, 6)
        XCTAssertEqual(JPRadius.m, 14)
        // 390 幅（左右 16・隙間 8 が2つ）で1枚の幅は約112
        let width = (390 - JPSpace.gutter * 2 - SearchView.gearCardSpacing * 2) / 3
        XCTAssertEqual(width, 112, accuracy: 3)
    }

    func testGearSectionIsCardsInARow() throws {
        let search = try source("Features/Search/SearchView.swift")
        let gear = slice(search, from: "private var gear: some View", to: "private func gearCard(")
        XCTAssertTrue(gear.contains("HStack(spacing: Self.gearCardSpacing)"), "札を横に並べていない")
        XCTAssertFalse(gear.contains("JPCardDivider"), "縦の行の区切り線が残っている")
        XCTAssertFalse(search.contains("func gearRow("), "縦の行が残っている")
        assertInOrder(["sectionHeader(eyebrow: \"GEAR\"", "L(\"機材から探す\", \"Browse by gear\")",
                       "GearPhotosView(section: section)", "gearCard(section)",
                       ".accessibilityLabel(section.group.accessibilityLabel)",
                       ".accessibilityIdentifier(\"search.gear.", ".padding(.horizontal, JPSpace.gutter)"],
                      in: gear, "眉と明朝の題 → 行き先 → 札 → 読み上げ → 道しるべ → 左右 16")
    }

    func testGearCardContentsAndColors() throws {
        let search = try source("Features/Search/SearchView.swift")
        let card = slice(search, from: "private func gearCard(", to: "nonisolated static let gearCardHeight")
        assertInOrder(["VStack(alignment: .leading, spacing: Self.gearIconGap)",
                       "Image(systemName: \"camera\")", ".foregroundStyle(WebTheme.text2)",
                       ".frame(height: Self.gearIconSize)",
                       "VStack(alignment: .leading, spacing: 2)",
                       "Text(section.group.label)", ".font(JPFont.body)", ".foregroundStyle(WebTheme.text)",
                       "Text(section.group.range)", ".font(JPFont.meta)", ".foregroundStyle(WebTheme.text3)",
                       ".padding(.vertical, Self.gearCardPaddingV)", ".padding(.horizontal, Self.gearCardPaddingH)",
                       "minHeight: Self.gearCardHeight",
                       ".background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.m))",
                       ".strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline)",
                       ".contentShape(RoundedRectangle(cornerRadius: JPRadius.m))"],
                      in: card, "印 → 6 → 名前 → 2 → 焦点距離・内側・地 surface-1・縁 白8%・札全体が押せる")
        XCTAssertFalse(card.contains("section.count"), "札に枚数を出している")
        XCTAssertFalse(card.contains("chevron.right"), "札に「›」が残っている")
        XCTAssertFalse(card.contains("WebTheme.accent"), "印・数は合図ではない（真鍮にしない）")
    }

    func testGearAccessibilityLabelIsNameAndRange() {
        XCTAssertEqual(GearGroups.Group.wide.accessibilityLabel, L("広角で撮る 〜35mm", "Wide up to 35mm"))
        XCTAssertEqual(GearGroups.Group.standard.accessibilityLabel, L("標準で撮る 36〜70mm", "Standard 36–70mm"))
        XCTAssertEqual(GearGroups.Group.telephoto.accessibilityLabel, L("望遠で撮る 71mm〜", "Telephoto 71mm+"))
        for group in GearGroups.Group.allCases {
            XCTAssertFalse(group.accessibilityLabel.contains("枚"), "読み上げに枚数が残っている")
        }
    }

    /// 写真の無い区分は出さず、残りの札で幅を割る（空の札を置かない）
    func testGearSkipsEmptyGroupsAndSplitsTheRest() throws {
        let photos = [try photo("a", focal: "24mm"), try photo("b", focal: "200mm"), try photo("c", focal: nil)]
        let sections = GearGroups.sections(in: photos, limit: .max)
        XCTAssertEqual(sections.map(\.group), [.wide, .telephoto], "写真の無い「標準」の札を出している")
        let search = try source("Features/Search/SearchView.swift")
        let gear = slice(search, from: "private var gear: some View", to: "private func gearCard(")
        XCTAssertTrue(gear.contains("ForEach(sections)"), "並べる札が区分の一覧から来ていない")
        XCTAssertFalse(gear.contains("Group.allCases"), "写真の無い区分まで札にしている")
        let card = slice(search, from: "private func gearCard(", to: "nonisolated static let gearCardHeight")
        XCTAssertTrue(card.contains(".frame(maxWidth: .infinity"), "札が残りの幅を等分しない")
    }

    // MARK: - ③ 色の丸は5等分の位置から左に詰める

    func testColorCirclesKeepFiveSlotsLeftAligned() throws {
        XCTAssertEqual(SearchView.colorColumnCount, 5)
        XCTAssertEqual(ColorFamilies.Family.allCases.count, SearchView.colorColumnCount,
                       "色味の数と列の数が合わない（6つ目が2段目に落ちる）")
        let search = try source("Features/Search/SearchView.swift")
        let colors = slice(search, from: "private var colors: some View", to: "private func colorCircle(")
        XCTAssertTrue(colors.contains("count: Self.colorColumnCount"), "色の数で幅を割っている（少ないと左右に浮く）")
        XCTAssertTrue(colors.contains("alignment: .leading"), "左から詰めていない")
        XCTAssertFalse(colors.contains("HStack(alignment: .top, spacing: 0)"), "並んだ数で割る並べ方が残っている")
        XCTAssertFalse(colors.contains("count: sections.count"), "色の数で幅を割っている")
    }
}
