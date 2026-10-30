import XCTest
@testable import JourneyPhoto

/// デザイン v2 の第2段（ホーム・探す・タグの写真・お知らせ・メニュー・2026-10-14）の見た目の決まり。
///
/// 画面は Linux では描けないので、`DesignFoundationTests` と同じく**値は数で**、**部品の作りは
/// 元のファイルを読んで**見張る。型・関数の範囲に絞り、呼び出しの**順**まで見る
/// （字があるかだけでは、修飾子の入れ替えや呼び出しの削除で落ちない）。
///
/// 見張るのは4つ: 使う部品（土台の部品を通っているか・写しを作っていないか）・字の段・
/// 真鍮の置き場所（黒地の上だけ）・写真の上は白。加えて、UI テストが探す道しるべ（識別子）を落とさない
final class V2HomeSearchNotificationsTests: XCTestCase {

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

    /// `start` から `end` の手前までを切り出す（ほかの型・関数の同じ字に当たらないように）
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

    /// `parts` がこの順に `text` に現れる
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

    // MARK: - 数（物差し）

    /// チップは見た目 34・当たり 44（板の chip）。行・札・写真の寸法も板の値
    func testMeasuresFollowTheBoards() {
        XCTAssertEqual(PillChip.height, 34)
        XCTAssertEqual(PillChip.height + PillChip.tapSlack * 2, WebTheme.minTapTarget,
                       "チップの当たりが 44 にならない")
        XCTAssertEqual(NotificationsView.rowHeight, 68)
        XCTAssertEqual(NotificationsView.followBackSlack * 2 + JPHeight.inlineButton, WebTheme.minTapTarget,
                       "フォローバックの当たりが 44 にならない")
        XCTAssertEqual(SiteMenuRow.height, 72)
        XCTAssertEqual(SiteMenuRow.iconTile, 40)
        XCTAssertEqual(HomeTopCardView.cardHeight, 116)
        XCTAssertEqual(HomeTopCardView.photoWidth, 112)
        XCTAssertEqual(HomeMosaic.edge, 8, "ホームの写真は端 8 まで広げる（板 Main）")
        XCTAssertEqual(HomeMosaic.corner, JPRadius.m)
        XCTAssertEqual(SearchView.colorCircleSize, 62)
        // 余白は 4 の倍数（土台の決まり）
        for value in [GalleryView.feedTabGap, HomeMosaic.edge, PillChip.height + PillChip.tapSlack * 2] {
            XCTAssertEqual(value.truncatingRemainder(dividingBy: 4), 0, "\(value) が 4 の倍数でない")
        }
    }

    /// タグの写真の眉は、何で集めた一覧かを言う
    func testCollectionEyebrowNamesTheKind() {
        XCTAssertEqual(CollectionScreen.eyebrow(for: .tag("夕焼け"))?.text, "TAG")
        XCTAssertEqual(CollectionScreen.eyebrow(for: .location("金沢"))?.text, "PLACE")
        XCTAssertEqual(CollectionScreen.eyebrow(for: .category("landscape"))?.text, "CATEGORY")
        XCTAssertEqual(CollectionScreen.eyebrow(for: .camera("X100V"))?.text, "CAMERA")
        XCTAssertNil(CollectionScreen.eyebrow(for: nil), "種類の無い入口は呼ぶ側が渡す")
        XCTAssertFalse(CollectionScreen.eyebrow(for: .tag("x"))?.spoken.isEmpty ?? true, "眉の読み上げが空")
    }

    // MARK: - 共通の部品

    /// チップ: 白 7% の地に白 8% の縁、選ぶと白 94% の塗り＋墨＋チェック、件数は灰の等幅
    func testPillChipIsTheV2Chip() throws {
        let chip = try source("Features/Common/PillChip.swift")
        let body = slice(chip, from: "var body: some View", to: ".buttonStyle(.plain)")
        assertInOrder(["if selected {", "Image(systemName: \"checkmark\")", "Text(title)"], in: body,
                      "選んだチップのチェックの印")
        XCTAssertTrue(body.contains("selected ? WebTheme.accentText : WebTheme.text3"), "件数が灰の数字でない")
        XCTAssertTrue(body.contains("JPFont.number("), "件数が等幅の数字でない")
        XCTAssertTrue(body.contains(".background(selected ? WebTheme.accentBackground : WebTheme.surface, in: Capsule())"))
        XCTAssertTrue(body.contains("WebTheme.hairline"), "選んでいないチップの縁が白 8% でない")
        XCTAssertTrue(body.contains(".padding(.vertical, Self.tapSlack)"), "当たりを 44 に広げていない")
        XCTAssertFalse(body.contains("WebTheme.accent)"), "チップに真鍮を使っている（選択は白）")
        XCTAssertTrue(chip.contains(".accessibilityAddTraits(selected ? .isSelected : [])"))
    }

    /// 節の見出し: 眉（真鍮＋線）→ 明朝 22 → 右に「すべて ›」（灰）
    func testSectionHeadingOrder() throws {
        let text = try source("Features/Common/SectionHeading.swift")
        let heading = slice(text, from: "struct JPSectionHeading", to: "extension JPSectionHeading")
        assertInOrder(["JPEyebrowLine(eyebrow, spoken: spoken)", ".font(JPFont.cardTitle)", "trailing"],
                      in: heading, "節の見出しの並び")
        let more = slice(text, from: "struct MoreLink", to: ".contentShape(Rectangle())")
        XCTAssertTrue(more.contains(".foregroundStyle(WebTheme.text2)"), "「すべて ›」が灰でない")
        XCTAssertFalse(more.contains("WebTheme.accent"), "節の行き先を真鍮にしている（合図ではない）")
        XCTAssertTrue(more.contains("minHeight: WebTheme.minTapTarget"), "「すべて ›」の当たりが 44 でない")
    }

    // MARK: - ホーム

    /// 字のタブ: 選んだタブは真鍮の字と 2 の下線、ほかは text-3。白の塗りの切り替えに戻さない
    func testHomeFeedTabsAreBrassTextTabs() throws {
        let gallery = try source("Features/Gallery/GalleryView.swift")
        let picker = slice(gallery, from: "private var feedPicker: some View", to: "static let feedTabGap")
        XCTAssertTrue(picker.contains("Text(feed.label)"), "UI テストは「新着」「フォロー中」を字で探す")
        assertInOrder([".foregroundStyle(selected ? WebTheme.accent : WebTheme.text3)",
                       ".fill(selected ? WebTheme.accent : Color.clear)",
                       ".frame(height: JPStroke.emphasis)"], in: picker, "選んだタブの真鍮の字と下線")
        XCTAssertTrue(picker.contains(".accessibilityAddTraits(selected ? .isSelected : [])"),
                      "選んだことを読み上げで伝えていない（色だけ）")
        XCTAssertTrue(picker.contains("WebTheme.hairline"), "タブの下の区切り線が無い")
        XCTAssertFalse(picker.contains("WebTheme.accentText"), "白の塗りの切り替え（墨の字）に戻っている")
        XCTAssertFalse(picker.contains("in: Capsule()"), "丸い切り替えに戻っている")
    }

    /// 読み込み中・空・失敗は共通の部品。空の一手の道しるべ（`home.emptyAction`）を落とさない
    func testHomeStatesUseSharedParts() throws {
        let gallery = try source("Features/Gallery/GalleryView.swift")
        let loading = slice(gallery, from: "case .loading:", to: "case .failed")
        XCTAssertTrue(loading.contains("JPLoadingState(kind: .grid)"), "読み込み中が骨格でない")
        XCTAssertFalse(loading.contains("ProgressView"))
        let empty = slice(gallery, from: "private var feedEmptyState: some View", to: "private var emptyTitle")
        XCTAssertTrue(empty.contains("ErrorBanner(message: emptyMessage, isBusy: isRefreshing)"),
                      "フォロー中を読めなかった回が失敗の形でない")
        XCTAssertTrue(empty.contains("EmptyState(title: emptyTitle, message: emptyMessage,"))
        XCTAssertTrue(empty.contains("actionIdentifier: \"home.emptyAction\""), "UI テスト（10c）の道しるべが無い")
        XCTAssertFalse(empty.contains("Image(systemName:"), "空の状態に自前の印を置いている（共通の部品の外）")
        let common = try source("Features/Common/ErrorBanner.swift")
        let state = slice(common, from: "struct EmptyState", to: "private struct StateLayout")
        XCTAssertTrue(state.contains(".accessibilityIdentifier(actionIdentifier ?? \"\")"),
                      "空の状態の一手に道しるべを渡せない")
    }

    /// 上の札: 写真つきの横長カード（左に写真・薄めない）・眉は真鍮＋線・題は明朝 18・札の面と縁
    func testHomeTopCardIsPhotoCard() throws {
        let view = try source("Features/Gallery/HomeTopCardView.swift")
        let card = slice(view, from: "private func card(eyebrow: String", to: "private static func spotDetail")
        assertInOrder(["cardPhoto(backdrop: backdrop, backdropURL: backdropURL)",
                       "JPEyebrowLine(eyebrow, spoken: eyebrowLabel)",
                       ".font(JPFont.rowTitle)",
                       ".foregroundStyle(WebTheme.text2)"], in: card, "札の並び（写真 → 眉 → 題 → 一行）")
        XCTAssertTrue(card.contains(".jpCardFace()"), "札の地（surface-1・白 8% の縁・角 16）が無い")
        XCTAssertFalse(card.contains(".opacity(0.35)"), "写真を薄く敷く v1 の形に戻っている")
        XCTAssertFalse(card.contains("WebTheme.surface"), "札の地が v1 の白 7% のまま")
        let theme = try source("Features/Gallery/DailyThemeCard.swift")
        XCTAssertTrue(theme.contains("JPEyebrowLine(\"TODAY'S THEME\""), "今日のテーマの眉が v2 でない")
        XCTAssertTrue(theme.contains(".jpPillButton(.main(onPhoto: true), height: JPHeight.secondaryButton)"),
                      "「参加する」が写真のある画面の主ボタン（白）でない")
        XCTAssertTrue(theme.contains(".jpCardFace()"), "今日のテーマの札の地が共通の札でない")
    }

    /// ホームの写真: 写真の上は白だけ（真鍮を置かない）。いいねのハートも白
    func testHomeMosaicKeepsPhotoTextWhite() throws {
        let mosaic = try source("Features/Gallery/HomeMosaic.swift")
        let tile = slice(mosaic, from: "struct HomeFeedTile", to: "enum HomeTileText")
        XCTAssertFalse(tile.contains("WebTheme.accent"), "写真の上に真鍮を置いている（読めない）")
        XCTAssertFalse(tile.contains("WebTheme.text2") || tile.contains("WebTheme.text3"),
                       "写真の上に不透明の灰を置いている（明るい写真で沈む）")
        let caption = slice(tile, from: "private var caption: some View", to: "private var multipleMark")
        assertInOrder([".font(large ? JPFont.cardTitle : JPFont.rowTitle)", ".foregroundStyle(Color.white)"],
                      in: caption, "撮影地は明朝の白")
        let like = slice(tile, from: "private var likeButton: some View", to: "private var liked")
        XCTAssertTrue(like.contains(".foregroundStyle(Color.white)"), "いいねのハートが白でない")
        XCTAssertTrue(mosaic.contains(".padding(.horizontal, Self.edge)"), "写真を端 8 まで広げていない")
        XCTAssertTrue(tile.contains(".clipShape(RoundedRectangle(cornerRadius: HomeMosaic.corner))"))
        XCTAssertTrue(tile.contains(".accessibilityIdentifier(\"feed.photo\")"), "UI テストの道しるべが無い")
    }

    /// いまの季節のスポットの段: 見出しは共通の節の見出し、札は v2 の面と縁
    func testHomeSpotShelfUsesSectionHeading() throws {
        let shelf = try source("Features/Gallery/HomeSpotShelfView.swift")
        XCTAssertTrue(shelf.contains("JPSectionHeading(eyebrow: HomeSpotShelf.eyebrow(shelf.season)"))
        XCTAssertTrue(shelf.contains(".background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.m))"))
        XCTAssertFalse(shelf.contains("WebTheme.surface, in: RoundedRectangle"), "札の地が v1 のまま")
        XCTAssertTrue(shelf.contains(".accessibilityIdentifier(\"home.spotShelf.card\")"), "UI テスト（10d）の道しるべが無い")
    }

    // MARK: - メニュー

    /// メニュー: 眉の節・72 の行（印の札・明朝の題・説明）・規約のリンクは真鍮・道しるべはそのまま
    func testSiteMenuIsV2() throws {
        let menu = try source("Features/Common/SiteMenuView.swift")
        let view = slice(menu, from: "struct SiteMenuView", to: "struct SiteMenuRow")
        XCTAssertEqual(view.components(separatedBy: "JPEyebrowLine(").count - 1, 2, "節の眉が2つでない")
        XCTAssertFalse(view.contains("JPSectionTitle"), "v1 の灰の小さい見出しが残っている")
        XCTAssertFalse(view.contains("JPCard"), "行を札で囲む v1 の形が残っている")
        for id in ["menu.map", "menu.saved", "menu.tripPlans", "menu.logout"] {
            XCTAssertTrue(view.contains("\"\(id)\""), "\(id) の道しるべを落とした")
        }
        let footer = slice(view, from: "private var footer: some View", to: "private static var version")
        assertInOrder(["LegalConsent.termsURL", "LegalConsent.privacyURL", ".foregroundStyle(WebTheme.accent)"],
                      in: footer, "規約のリンク（真鍮・黒地の上）")
        let row = slice(menu, from: "struct SiteMenuRow", to: "struct SiteMenuPlainRow")
        assertInOrder([".background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: JPRadius.field))",
                       ".font(JPFont.rowTitle)", ".font(JPFont.caption)", ".foregroundStyle(WebTheme.text3)"],
                      in: row, "「見る」の行（印の札 → 明朝の題 → 説明）")
        XCTAssertTrue(row.contains(".frame(minHeight: Self.height)"))
        // 「いいね＝作者に届く／保存＝自分だけ」の違いを説明の一行で読ませる（板の付箋）
        XCTAssertTrue(view.contains("作者に届きます"))
        XCTAssertTrue(view.contains("自分だけ"))
    }

    // MARK: - 探す

    /// 探す: 大見出し（明朝）・節の見出しは共通の部品・欄は v2 の地・道しるべはそのまま
    func testSearchIsV2() throws {
        let search = try source("Features/Search/SearchView.swift")
        let view = slice(search, from: "struct SearchView: View", to: "final class SearchViewModel")
        assertInOrder(["Text(Labels.Navigation.searchTab)", ".font(JPFont.photoTitle)", "searchField", "scopeChips"],
                      in: view, "大見出し → 探す欄 → 種類のチップ")
        XCTAssertFalse(view.contains("JPSectionTitle"), "段の見出しが v1 の灰の小さい字のまま")
        XCTAssertFalse(view.contains("moreLabel("), "「すべて ›」が自前の形のまま")
        XCTAssertGreaterThanOrEqual(view.components(separatedBy: "sectionHeader(eyebrow:").count - 1, 6,
                                    "発見の段の見出しが眉＋明朝になっていない")
        XCTAssertTrue(view.contains("JPSectionHeading(eyebrow: eyebrow, spoken: spoken, title: title, trailing: trailing)"))
        let field = slice(view, from: "private var searchField: some View", to: "private var scopeChips")
        XCTAssertTrue(field.contains(".background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: JPRadius.field))"))
        XCTAssertTrue(field.contains("strokeBorder(WebTheme.hairline"))
        for id in ["search.field", "search.clear", "search.emptyMap", "search.season.", "search.dayPart.",
                   "search.spot", "search.spots", "search.clearTimeFilters", "search.time.note"] {
            XCTAssertTrue(view.contains("\"\(id)"), "\(id) の道しるべを落とした")
        }
    }

    /// タグのチップは共通のチップに件数を添える（自前の札を作らない）
    func testSearchTagChipsUseSharedChip() throws {
        let search = try source("Features/Search/SearchView.swift")
        let tags = slice(search, from: "private var tagChips: some View", to: "private var shootingTimeChips")
        XCTAssertTrue(tags.contains("PillChip(title: item.tag, count: item.count,"), "タグのチップが共通のチップでない")
        XCTAssertFalse(search.contains("private func chip("), "自前のチップが残っている")
    }

    /// 「すべて解除」は黒地の上の手がかり＝真鍮。墨の字（黒地の上で見えない）に戻さない
    func testSearchClearAllIsReadableBrass() throws {
        let search = try source("Features/Search/SearchView.swift")
        let chips = slice(search, from: "private var shootingTimeChips: some View", to: "private var availableDayParts")
        let clear = slice(chips, from: "Text(L(\"すべて解除\", \"Clear all\"))", to: ".accessibilityLabel(")
        XCTAssertTrue(clear.contains(".foregroundStyle(WebTheme.accent)"), "「すべて解除」が真鍮でない")
        XCTAssertFalse(clear.contains("WebTheme.accentText"), "「すべて解除」が墨の字（黒地で見えない）")
    }

    /// 写真の上の撮影地の札は白だけ（真鍮・不透明の灰を置かない）。名前は明朝
    func testSearchPlaceCardKeepsPhotoTextWhite() throws {
        let search = try source("Features/Search/SearchView.swift")
        let card = slice(search, from: "private func spotCard(", to: "private var colors: some View")
        XCTAssertFalse(card.contains("WebTheme.accent"), "写真の上に真鍮")
        XCTAssertFalse(card.contains("WebTheme.text2") || card.contains("WebTheme.text3"), "写真の上に不透明の灰")
        assertInOrder([".font(JPFont.rowTitle)", ".foregroundStyle(Color.white)",
                       ".padding(.bottom, Self.spotNameBottomInset)"],
                      in: card, "撮影地の名前（明朝・白）→ 下端から 10")
    }

    /// タグの写真: 眉（真鍮）→ 明朝 32 の題 → 枚数の一行。バーの中央に題を二重に出さない
    func testCollectionHeadingIsV2() throws {
        let screen = try source("Features/Gallery/CollectionPhotosScreen.swift")
        let heading = slice(screen, from: "private var heading: some View", to: "private var eyebrowMark")
        assertInOrder([".jpEyebrow()", ".foregroundStyle(WebTheme.accent)", "Text(title)",
                       ".font(JPFont.photoTitle)", "CollectionScreen.subtitle("], in: heading,
                      "眉 → 題 → 枚数")
        let toolbar = slice(screen, from: ".toolbar {", to: "ShareLink(")
        XCTAssertFalse(toolbar.contains("Text(title)"), "バーにも題を出している（二重）")
        XCTAssertTrue(screen.contains("PillChip(title: option.chipLabel, selected: sort == option)"))
        for (path, mark) in [("Features/Search/ColorPhotosView.swift", "eyebrow: \"COLOR\""),
                             ("Features/Search/GearPhotosView.swift", "eyebrow: \"GEAR\""),
                             ("Features/Search/SearchView.swift", "eyebrow: \"THIS SEASON\", eyebrowSpoken:")] {
            XCTAssertTrue(try source(path).contains(mark), "\(path) が眉を渡していない")
        }
    }

    // MARK: - お知らせ

    /// お知らせ: 共通のチップ・日付の眉・空と失敗は共通の部品・危険の赤を出さない・行は札で囲まない
    func testNotificationsAreV2() throws {
        let notes = try source("Features/Notifications/NotificationsView.swift")
        let chips = slice(notes, from: "private var filterChips: some View", to: "private var shownRows")
        XCTAssertTrue(chips.contains("PillChip(title: option.label, selected: filter == option)"))
        let list = slice(notes, from: "private var list: some View", to: "extension NotificationsView")
        XCTAssertTrue(list.contains("JPEyebrowLine(group.bucket.label)"), "日付の区切りが眉＋線でない")
        XCTAssertTrue(list.contains("ErrorBanner(message: message, isBusy: model.isLoading)"),
                      "読めなかった回が共通の失敗の形でない")
        XCTAssertFalse(list.contains("WebTheme.danger"), "読めなかった回を危険の赤で出している")
        XCTAssertTrue(list.contains("JPLoadingState(kind: .rows)"), "読み込み中が骨格でない")
        XCTAssertTrue(list.contains(".listStyle(.plain)"))
        let empty = slice(notes, from: "private var emptyState: some View", to: "private var list: some View")
        XCTAssertTrue(empty.contains("EmptyState(title:"), "空の状態が共通の部品でない")
        XCTAssertTrue(notes.contains(".accessibilityIdentifier(\"notifications.settings\")"))
        XCTAssertTrue(notes.contains(".accessibilityIdentifier(\"notifications.pushBanner\")"))
    }

    /// お知らせの行: 誰が＝白、何をした＝text-2、時刻＝text-3。未読は真鍮の点（黒地の上）。
    /// フォローバックは白の小ボタン（36・当たり 44）
    func testNotificationRowTypography() throws {
        let notes = try source("Features/Notifications/NotificationsView.swift")
        let content = slice(notes, from: "private func mainContent(", to: "private var avatar: some View")
        assertInOrder(["Text(line.who).bold().foregroundStyle(WebTheme.text)",
                       "Text(line.rest).foregroundStyle(WebTheme.text2)",
                       ".font(JPFont.body)",
                       ".font(JPFont.caption)", ".foregroundStyle(WebTheme.text3)"], in: content,
                      "行の字の明るさの段")
        let row = slice(notes, from: "private struct NotificationRow", to: "private func main(")
        assertInOrder(["if entry.unread {", ".fill(WebTheme.accent)", ".frame(width: 8, height: 8)"], in: row,
                      "未読の真鍮の点")
        let follow = slice(notes, from: "private var followBackButton: some View", to: "final class NotificationsViewModel")
        assertInOrder([".frame(height: JPHeight.inlineButton)",
                       ".background(WebTheme.accentBackground, in: Capsule())",
                       ".foregroundStyle(WebTheme.accentText)",
                       ".padding(.vertical, NotificationsView.followBackSlack)"], in: follow,
                      "フォローバックの白の小ボタン")
        // 印は送りの側が持つ。ボタンが自分で下ろすと、送らなかった2回目が送信中に押せる姿へ戻す
        XCTAssertTrue(follow.contains("followBackSending.contains(userId)"))
        XCTAssertFalse(follow.contains("busy"))
        XCTAssertTrue(notes.contains("guard followBackSending.insert(userId).inserted else { return }"))
    }

    // MARK: - 字の段

    /// 第2段で触った画面は本文 12 未満の字を作らない（眉の 11 は `jpEyebrow` / `JPEyebrowLine` だけ）
    func testNoTextBelowTwelveInTouchedScreens() throws {
        let paths = ["Features/Gallery/GalleryView.swift", "Features/Gallery/HomeTopCardView.swift",
                     "Features/Gallery/DailyThemeCard.swift", "Features/Gallery/HomeSpotShelfView.swift",
                     "Features/Gallery/CollectionPhotosScreen.swift", "Features/Common/SiteMenuView.swift",
                     "Features/Common/SectionHeading.swift", "Features/Common/PillChip.swift",
                     "Features/Search/SearchView.swift", "Features/Notifications/NotificationsView.swift"]
        for path in paths {
            let text = try source(path)
            for small in ["JPFont.mono(10", "JPFont.mono(11", "size: 10)", "size: 11)", "JPTypeScale.eyebrow"] {
                XCTAssertFalse(text.contains(small), "\(path) が 12 未満の字（\(small)）を作っている")
            }
        }
    }
}
