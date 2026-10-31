import XCTest
@testable import JourneyPhoto

/// ホームの整理（#417・2026-10-30 owner 採用の①〜⑨・板 Main の先頭の注記）。
///
/// 画面は Linux では描けないので、**値は数で**、**部品の作りは元のファイルを読んで**見張る
/// （`V2HomeSearchNotificationsTests` と同じ作法・注記の行は数えない）。⑨の判定と既読は振る舞いで確かめる
final class HomeTidyTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path),
                              encoding: .utf8)
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

    private func photo(_ id: String, owner: String?, at date: String?, published: Bool? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\""]
        if let date { fields.append("\"createdAt\":\"\(date)\"") }
        if let owner { fields.append("\"userId\":\"\(owner)\"") }
        if let published { fields.append("\"published\":\(published)") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    // MARK: - ① すれちがいの束の札は低い帯

    /// 板: 高さ 76・内側 12/4・間 12・束の絵 44×54（前の1枚の高さ 50）
    func testPassBandMeasures() {
        XCTAssertEqual(PassHomeCard.height, 76)
        XCTAssertEqual(PassHomeCard.leadingInset, 12)
        XCTAssertEqual(PassHomeCard.trailingInset, 4)
        XCTAssertEqual(PassHomeCard.gap, 12)
        XCTAssertEqual(PassMiniStack.bandSize, CGSize(width: 44, height: 54))
        XCTAssertEqual(PassMiniStack.bandScale * PassCardStyle.stackSize.height, 50, accuracy: 0.001,
                       "帯の絵の前の1枚が板の 50 にならない")
    }

    /// 帯: 束の絵（縮めた小さなきっぷ）→ 眉 → 明朝 18 の「今日 N 枚」→ 12 の地名、右に「束を開く ›」（真鍮・当たり 44）
    func testPassBandLayout() throws {
        let slot = try source("Features/Pass/PassHomeSlot.swift")
        let card = slice(slot, from: "struct PassHomeCard", to: "private var countTitle")
        assertInOrder(["PassMiniStack(faces: cards.prefix(3).map { $0.face() }, compact: true)",
                       "Text(L(\"カードが届きました\"", ".jpEyebrow()",
                       "countTitle", ".font(JPFont.rowTitle)",
                       "Text(PassBook.bundleLine(cards.map(\\.card)))", ".font(JPFont.caption)", ".lineLimit(1)",
                       ".frame(maxWidth: .infinity, alignment: .leading)",
                       "Text(L(\"束を開く ›\"", ".foregroundStyle(WebTheme.accent)",
                       ".frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)",
                       ".frame(minHeight: Self.height)"], in: card, "帯の並び")
        XCTAssertFalse(card.contains("JPFont.cardTitle"), "数の題が明朝 22 のまま（板は 18）")
        XCTAssertFalse(card.contains(".padding(JPSpace.m)"), "高い札（四方 16）のまま")
        XCTAssertTrue(card.contains(".accessibilityIdentifier(\"pass.home.open\")"), "UI テストの道しるべを落とした")
        // 数だけ SF の等幅数字
        XCTAssertTrue(slot.contains("Text(\"\\(cards.count)\").font(JPFont.number(JPTypeScale.title3"))
    }

    func testPassBandCountWords() {
        let today = PassHomeCard.countParts(count: 7, isToday: true)
        XCTAssertEqual(today.prefix + "7" + today.suffix, L("今日 7 枚", "7 today"))
        let other = PassHomeCard.countParts(count: 3, isToday: false)
        XCTAssertEqual(other.prefix + "3" + other.suffix, L("3 枚", "3 cards"))
    }

    // MARK: - ② 「すべて見る ›」は眉と同じ行

    func testSectionHeadingTrailingSitsOnTheEyebrowRow() throws {
        let text = try source("Features/Common/SectionHeading.swift")
        let heading = slice(text, from: "struct JPSectionHeading", to: "extension JPSectionHeading")
        XCTAssertFalse(heading.contains("HStack(alignment: .bottom"), "「すべて見る」が題の行の下揃えに戻っている")
        assertInOrder(["HStack(alignment: .center, spacing: JPSpace.s) {",
                       "JPEyebrowLine(eyebrow, spoken: spoken)",
                       "if hasTrailing { trailingSlot }",
                       "if let title {"], in: heading, "眉の行に「すべて見る」")
        XCTAssertTrue(heading.contains("trailing.padding(.vertical, -JPSectionHeadingLayout.trailingBleed)"),
                      "眉の行が 44 に伸びる（眉と題の間が開く）")
        // はみ出した当たりの下側を、長い題が塞がない
        assertInOrder(["if hasTrailing { trailingSlot }", ".zIndex(1)", "Text(title)", ".allowsHitTesting(false)"],
                      in: heading, "「すべて見る」の当たりが題に塞がれる")
        // 当たり 44 のまま、行は眉の背（16）で組む
        XCTAssertEqual(JPSectionHeadingLayout.trailingBleed * 2 + 16, WebTheme.minTapTarget)
        // 「すべて ›」の当たりは 44 のまま
        let more = slice(text, from: "struct MoreLink", to: ".contentShape(Rectangle())")
        XCTAssertTrue(more.contains("minHeight: WebTheme.minTapTarget"))
    }

    // MARK: - ③ 上段の札の背 116

    func testTopCardsAreOneLineEach() throws {
        XCTAssertEqual(HomeTopCardView.cardHeight, 116)
        XCTAssertEqual(HomeTopCardView.lineLimit, 1, "札の字が2行に戻ると並びの背が 156 に伸びる")
        let view = try source("Features/Gallery/HomeTopCardView.swift")
        let card = slice(view, from: "private func card(eyebrow: String", to: "nonisolated static let cardHeight")
        XCTAssertEqual(card.components(separatedBy: ".lineLimit(Self.lineLimit)").count - 1, 3, "題・一行・出典の3つが1行でない")
        XCTAssertFalse(card.contains(".lineLimit(2)"))
        assertInOrder([".lineLimit(Self.lineLimit)", ".truncationMode(detailTruncation)"], in: card,
                      "出典を真ん中で切っていない（末尾のライセンス名が消える）")
    }

    /// 出典は1行（地域 · 作者とライセンス）。改行で2行にしない
    func testSpotDetailIsOneLine() {
        let line = HomeTopCardView.spotDetail(region: "岡山", credit: "写真: A / CC BY-SA 4.0")
        XCTAssertEqual(line, "岡山 · 写真: A / CC BY-SA 4.0")
        XCTAssertFalse(line?.contains("\n") ?? true)
        XCTAssertEqual(HomeTopCardView.spotDetail(region: nil, credit: "c"), "c")
        XCTAssertNil(HomeTopCardView.spotDetail(region: nil, credit: nil))
    }

    /// 今日のテーマ: 「参加する」は題の右（見た目 36・当たり 44）・説明は1行・背は隣の札と同じ 116
    func testThemeJoinSitsRightOfTheTitle() throws {
        let theme = try source("Features/Gallery/DailyThemeCard.swift")
        let body = slice(theme, from: "var body: some View", to: ".background(alignment: .trailing)")
        assertInOrder(["JPEyebrowLine(\"TODAY'S THEME\"", "HStack(alignment: .center", "Text(theme.title)",
                       ".lineLimit(1)", "joinControl", "Text(theme.prompt)", ".lineLimit(1)",
                       "minHeight: HomeTopCardView.cardHeight"], in: body, "題の右に「参加する」")
        let join = slice(theme, from: "private var joinControl: some View", to: "static let joinInset")
        XCTAssertTrue(join.contains("minHeight: JPOutlineSize.inline.height"), "「参加する」の見た目が 36 でない")
        XCTAssertEqual(join.components(separatedBy: ".padding(.vertical, JPOutlineSize.inline.tapSlack)").count - 1, 2,
                       "「参加する」「参加済み」の当たりが 44 でない")
        XCTAssertFalse(theme.contains("JPHeight.secondaryButton"), "幅いっぱいの 44 の帯に戻っている")
        XCTAssertEqual(JPOutlineSize.inline.height, 36)
        XCTAssertEqual(JPOutlineSize.inline.height + JPOutlineSize.inline.tapSlack * 2, WebTheme.minTapTarget)
        XCTAssertEqual(DailyThemeCard.joinInset, 14)
    }

    // MARK: - ④ 季節の段は「おすすめ」の中・写真の大1→2→2 の後ろ

    func testSeasonShelfOnlyInRecommended() {
        XCTAssertTrue(HomeFeed.recommended.showsSeasonShelf)
        XCTAssertFalse(HomeFeed.following.showsSeasonShelf, "フォロー中に季節の段を出している")
        XCTAssertFalse(HomeFeed.latest.showsSeasonShelf, "新着に季節の段を出している")
    }

    /// 段の前は5枚（大1→2→2 のひと回り）。後ろの写真も大きい1枚から始まる（並びのリズムを崩さない）
    func testSeasonShelfSplitsAfterOneCycle() throws {
        let photos = try (0..<8).map { try photo("p\($0)", owner: "a", at: "2026-01-0\($0 + 1)") }
        let split = HomeFeed.splitForSeasonShelf(photos)
        XCTAssertEqual(split.lead.map(\.id), ["p0", "p1", "p2", "p3", "p4"])
        XCTAssertEqual(split.rest.map(\.id), ["p5", "p6", "p7"])
        let leadRows = EditorialLayout.rows(split.lead)
        XCTAssertEqual(leadRows.count, 3)
        guard case .hero = leadRows[0], case .pair(_, _?) = leadRows[1], case .pair(_, _?) = leadRows[2] else {
            return XCTFail("段の前が大1→2→2 でない")
        }
        guard case .hero(let first)? = EditorialLayout.rows(split.rest).first else {
            return XCTFail("段の後ろが大きい1枚から始まらない")
        }
        XCTAssertEqual(first.id, "p5")
        // 5枚に満たなければ全部が前（段は一覧の最後）
        let short = HomeFeed.splitForSeasonShelf(Array(photos.prefix(3)))
        XCTAssertEqual(short.lead.count, 3)
        XCTAssertTrue(short.rest.isEmpty)
    }

    func testSeasonShelfMovedIntoTheFeed() throws {
        let gallery = try source("Features/Gallery/GalleryView.swift")
        // #426: 束ねと 5 枚の割りは控え（`HomeFeedPageMemo.make`）が計算する
        let make = slice(gallery, from: "static func make(_ page: HomeFeed,", to: "private struct PassResolveKey")
        assertInOrder(["PhotoGroups.group(hidden.visible(photos))", "guard page.showsSeasonShelf else",
                       "HomeFeed.splitForSeasonShelf(groups)"], in: make, "季節の段の前後に割る")
        let section = slice(gallery, from: "private func feedSection(_ page: HomeFeed, rows: HomeFeedPageMemo.Rows) -> some View {",
                            to: "nonisolated static let seasonShelfTopTrim")
        // 「おすすめ」では段の有無に関係なくいつも5枚で割り、段だけを挟む（後から届いた段で一覧を作り直さない）。
        // 写真が0枚の日は段を出さない
        assertInOrder(["featuredSections(page)",
                       "if page.showsSeasonShelf {",
                       "let split = (lead: rows.lead, rest: rows.rest)",
                       "HomeMosaic(groups: split.lead",
                       "if !groups.isEmpty, let seasonShelf {",
                       "HomeSpotShelfView(shelf: seasonShelf.shelf",
                       "HomeMosaic(groups: split.rest",
                       "} else {",
                       "HomeMosaic(groups: groups"], in: section, "季節の段の置き場所")
        // #426: 続きの目印は札の中身に置かない（外側の遅延の並びの子・`TabSwitchUnifyTests.testNextPageMarkerIsLazy`）
        XCTAssertFalse(section.contains("{ pageFooter }"))
        XCTAssertFalse(section.contains("showsSeasonShelf, let seasonShelf"),
                       "段の有無で写真の一覧の枝が替わる（段が届いた瞬間に一覧が作り直される）")
        // 上の札の並びの下には置かない（2段続きに戻さない）
        let top = try source("Features/Gallery/HomeTopCardView.swift")
        XCTAssertFalse(top.contains("HomeSpotShelfView("), "季節の段が上の札の下に残っている")
        XCTAssertTrue(top.contains("seasonShelf = visibleShelf(choices).map { HomeSeasonShelfSlot(shelf: $0, spots: spots) }"),
                      "段の中身を一覧へ渡していない")
        XCTAssertTrue(gallery.contains("seasonShelf: $seasonShelf"))
        XCTAssertEqual(GalleryView.seasonShelfTopTrim, -8)
        XCTAssertEqual(GalleryView.seasonShelfBottomTrim, -12)
    }

    // MARK: - ⑤ 段は眉だけ・注記は札の下

    func testSeasonShelfHeaderIsEyebrowOnly() throws {
        let shelf = try source("Features/Gallery/HomeSpotShelfView.swift")
        let header = slice(shelf, from: "private var header: some View", to: "private func card(")
        XCTAssertTrue(header.contains("JPSectionHeading(eyebrow: HomeSpotShelf.eyebrow(shelf.season)"))
        XCTAssertFalse(header.contains("title:"), "季節の段に明朝の題が戻っている")
        XCTAssertFalse(header.contains("HomeSpotShelf.note"), "作例の注記が札の上に残っている")
        let body = slice(shelf, from: "var body: some View", to: "private var header: some View")
        assertInOrder(["header", "ForEach(shelf.entries)", "Text(HomeSpotShelf.note)",
                       ".accessibilityLabel(HomeSpotShelf.heading)"], in: body, "注記は札の下")
        // 文は変えない
        XCTAssertTrue(HomeSpotShelf.note.contains(L("各撮影スポットの作例", "examples for each spot")))
    }

    // MARK: - ⑥ 「行きたい」は行の中の小ボタン

    func testWishIsAnInlineButton() throws {
        XCTAssertEqual(HomeSpotShelfView.wishHeight, 36)
        XCTAssertEqual(HomeSpotShelfView.wishHeight + JPOutlineSize.inline.tapSlack * 2, WebTheme.minTapTarget)
        XCTAssertEqual(HomeSpotShelfView.wishInset, 14)
        let shelf = try source("Features/Gallery/HomeSpotShelfView.swift")
        // 文字の中でも型の呼び出しに見えると参照の検査が止めるので、名前を割って書く
        XCTAssertFalse(shelf.contains("SpotDetailParts" + ".actionLabel("), "幅いっぱいの 64 の帯に戻っている")
        let label = slice(shelf, from: "private func wishLabel(", to: "nonisolated static let wishHeight")
        assertInOrder(["fill: wanted ? WebTheme.accentBackground : WebTheme.surface",
                       "fullWidth: false", "minHeight: Self.wishHeight",
                       ".padding(.vertical, JPOutlineSize.inline.tapSlack)"], in: label, "小ボタン（白 7%・36・当たり 44）")
    }

    // MARK: - ⑦ NEW の段を外した

    func testFreshStripIsGone() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for path in ["Sources/JourneyPhoto/Features/Gallery/HomeFreshStrip.swift",
                     "Sources/JourneyPhoto/Core/Text/HomeFreshPhotos.swift"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path), "\(path) が残っている")
        }
        let gallery = try source("Features/Gallery/GalleryView.swift")
        XCTAssertFalse(gallery.contains("HomeFreshStrip("), "NEW の段がホームに戻っている")
        XCTAssertFalse(gallery.contains("freshGroups"))
        XCTAssertFalse(gallery.contains("home.fresh"))
    }

    // MARK: - ⑧ 切り替えは見出しの下に留まる

    func testFeedPickerIsPinned() throws {
        let gallery = try source("Features/Gallery/GalleryView.swift")
        let feed = slice(gallery, from: "private func feed(_ photos: [Photo]) -> some View", to: "private static let feedTopID")
        // #426 Mac の確かめ: 節の見出しで留めるのをやめ、マイページと同じ（流れる札の行＋縦の送りの外に重ねる札）
        assertInOrder(["VStack(spacing: Self.feedSpacing) {",
                       "HomeTopCardView(",
                       "feedPicker(followingHasNew: followingHasNew, stuck: false)",
                       "ProfileTabPager(tabs: HomeFeed.allCases, selection: feedSelection,",
                       "feedSection(page, rows: pageRows(page, selected: photos))",
                       "if feedRowPinned { pinnedFeedRow(followingHasNew: followingHasNew) }"],
                      in: feed, "切り替えは写真の一覧の頭・送ると上に重ねて留める")
        // 留まった姿はマイページと同じ札の部品の `stuck`（地は黒 100%・下の線は白 12%）
        let picker = slice(gallery, from: "private func feedPicker(followingHasNew: Bool, stuck: Bool) -> some View",
                           to: "private var feedSelection: Binding<HomeFeed>")
        assertInOrder(["ProfileTabBar(tabs: HomeFeed.allCases, selection: feedSelection, stuck: stuck,",
                       ".background(WebTheme.background)",
                       "feedPicker(followingHasNew: followingHasNew, stuck: true)"], in: picker, "留まった切り替えの地と下の線")
        XCTAssertEqual(ProfileTabStyle.lineOpacity(stuck: true), 0.12)
        // 既定の選びは「おすすめ」のまま（owner の過去の判断）
        XCTAssertEqual(HomeFeed.allCases.first, .recommended)
        XCTAssertTrue(try source("Features/Gallery/GalleryViewModel.swift")
            .contains("@Published private(set) var feed: HomeFeed = .recommended"))
    }

    /// 留まった切り替えで別のフィードを押したら、新しい一覧の頭へ送る（上の札が見えている間は送らない）
    func testPinnedPickerScrollsToTheListHead() throws {
        let gallery = try source("Features/Gallery/GalleryView.swift")
        // #426: 押した・払ったのどちらも `model.feed` が替わる。深く送っていれば札の行を上端へ（マイページと同じ）
        XCTAssertTrue(gallery.contains("Binding(get: { model.feed }, set: { selectFeed($0) })"), "払った回が一覧の頭へ送らない")
        XCTAssertFalse(gallery.contains("topCardsVisible"), "上の札の出入りで留まりを見ている（境がずれる）")
        let feed = slice(gallery, from: "private func feed(_ photos: [Photo]) -> some View", to: "private static let feedTopID")
        assertInOrder([".id(Self.feedRowID)",
                       ".onChange(of: model.feed) { _, _ in",
                       "guard ProfileTabScroll.scrollsToRow(rowMinY: feedRowSpot.minY, visibleTop: 0) else { return }",
                       "withAnimation(ProfileTabMotion.animation(reduceMotion: reduceMotion)) {",
                       "proxy.scrollTo(Self.feedRowID, anchor: .top)"],
                      in: feed, "一覧の頭へ送る仕組み")
        XCTAssertFalse(gallery.contains("feedPickerID"), "留まった札の行を目印に scrollTo している（いちばん上まで戻る）")
        XCTAssertFalse(gallery.contains("feedHeadRequests"))
    }

    // MARK: - ⑨ 「フォロー中」の真鍮の点

    func testFollowingDotMeasuresAndSpeaks() throws {
        // #426: 点は札の部品（`ProfileTabDot`）が描く。位置と大きさは `ProfileTabStyle`
        XCTAssertEqual(ProfileTabStyle.dotSize, 8)
        XCTAssertEqual(ProfileTabStyle.dotOffset.x, 11, "字の右端から 11 でない")
        XCTAssertEqual(ProfileTabStyle.dotOffset.y, 9, "上から 9 でない")
        let gallery = try source("Features/Gallery/GalleryView.swift")
        let picker = slice(gallery, from: "private func feedPicker(followingHasNew: Bool, stuck: Bool) -> some View",
                           to: "private var feedSelection: Binding<HomeFeed>")
        assertInOrder(["dot: { $0 == .following && followingHasNew },",
                       "spokenLabel: { HomeFollowingNews.spokenLabel($0.label, hasNew: $0 == .following && followingHasNew) })"],
                      in: picker, "点と読み上げ")
        XCTAssertEqual(HomeFeed.latest.tabIdentifier, "home.feed.latest", "UI テストの道しるべが変わった")
        XCTAssertEqual(HomeFeed.following.tabTitle, HomeFeed.following.label, "UI テストは「新着」「フォロー中」を字でも探す")
        let bar = try source("Features/Profile/ProfileTabBar.swift")
        let dot = slice(bar, from: "struct ProfileTabDot: View {", to: "enum ProfileTabStyle {")
        assertInOrder(["Circle().fill(WebTheme.accent)", ".strokeBorder(WebTheme.background, lineWidth: 2)"],
                      in: dot, "真鍮の点と黒 2 の縁")
        assertInOrder([".overlay(alignment: .topTrailing) {", "if dot(option) { ProfileTabDot() }",
                       ".accessibilityLabel(spoken(option))"], in: bar, "札の部品の点と読み上げ")
        XCTAssertEqual(HomeFollowingNews.spokenLabel("フォロー中", hasNew: true), L("フォロー中・新しい写真あり", "フォロー中, new photos"))
        XCTAssertEqual(HomeFollowingNews.spokenLabel("フォロー中", hasNew: false), "フォロー中")
    }

    /// 「新しい」はフォロー中の人の、下書きでない・自分のでない写真のいちばん新しい投稿日
    func testFollowingNewestCountsOnlyFollowedPublishedOthers() throws {
        let photos = [
            try photo("mine", owner: "me", at: "2026-10-30"),
            try photo("stranger", owner: "x", at: "2026-10-29"),
            try photo("draft", owner: "f", at: "2026-10-28", published: false),
            try photo("friend", owner: "f", at: "2026-10-01"),
            try photo("nodate", owner: "f", at: nil),
        ]
        XCTAssertEqual(HomeFollowingNews.newest(photos, viewerId: "me", followingIds: ["f", "me"]), "2026-10-01")
        XCTAssertNil(HomeFollowingNews.newest(photos, viewerId: nil, followingIds: ["f"]), "未ログインで点を出す")
        XCTAssertNil(HomeFollowingNews.newest(photos, viewerId: "me", followingIds: []), "誰もフォローしていないのに点を出す")
    }

    func testDotRules() {
        // 覚えが無い日（初めて）は出さない
        XCTAssertFalse(HomeFollowingNews.showsDot(feed: .recommended, newest: "2026-10-02", seen: nil))
        XCTAssertTrue(HomeFollowingNews.showsDot(feed: .recommended, newest: "2026-10-02", seen: "2026-10-01"))
        XCTAssertTrue(HomeFollowingNews.showsDot(feed: .latest, newest: "2026-10-02", seen: "2026-10-01"))
        XCTAssertFalse(HomeFollowingNews.showsDot(feed: .following, newest: "2026-10-02", seen: "2026-10-01"),
                       "開いている「フォロー中」に点を出している")
        XCTAssertFalse(HomeFollowingNews.showsDot(feed: .recommended, newest: "2026-10-01", seen: "2026-10-01"))
        XCTAssertFalse(HomeFollowingNews.showsDot(feed: .recommended, newest: nil, seen: "2026-10-01"))
    }

    func testSeenRules() {
        XCTAssertEqual(HomeFollowingNews.seenToStore(feed: .recommended, newest: "b", seen: nil), "b", "初めての日に覚えない")
        XCTAssertNil(HomeFollowingNews.seenToStore(feed: .recommended, newest: "b", seen: "a"),
                     "「フォロー中」を開いていないのに既読にした")
        XCTAssertEqual(HomeFollowingNews.seenToStore(feed: .following, newest: "b", seen: "a"), "b")
        XCTAssertNil(HomeFollowingNews.seenToStore(feed: .following, newest: "a", seen: "b"), "既読を戻した")
        XCTAssertNil(HomeFollowingNews.seenToStore(feed: .following, newest: nil, seen: "a"))
    }

    /// 🔴 振る舞い: 初めて → 点なし。新しい写真が届く → 点。「フォロー中」を開く → 既読で消える。戻っても出ない。
    /// 人ごとに分かれる・戻さない・退会で消える
    func testFollowingDotLifecycle() throws {
        let suite = "HomeTidyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FollowingSeenStore(defaults: defaults)
        var feed = HomeFeed.recommended
        var photos = [try photo("old", owner: "f", at: "2026-10-01T00:00:00Z")]

        /// 画面の `syncFollowingSeen` と同じ順: 覚え直す → 点を決める
        func render() -> Bool {
            let newest = HomeFollowingNews.newest(photos, viewerId: "me", followingIds: ["f"])
            if let value = HomeFollowingNews.seenToStore(feed: feed, newest: newest, seen: store.seen(for: "me")) {
                store.mark(value, for: "me")
            }
            return HomeFollowingNews.showsDot(feed: feed, newest: newest, seen: store.seen(for: "me"))
        }

        XCTAssertFalse(render(), "初めての日に（前に見たか分からない写真で）点を出した")
        XCTAssertEqual(store.seen(for: "me"), "2026-10-01T00:00:00Z")
        photos.append(try photo("new", owner: "f", at: "2026-10-30T00:00:00Z"))
        XCTAssertTrue(render(), "フォロー中の人の新しい写真で点が出ない")
        feed = .following
        XCTAssertFalse(render(), "開いている「フォロー中」に点を出した")
        feed = .recommended
        XCTAssertFalse(render(), "開いて見た分で、戻ったあとも点が出る")
        // 別の人には前の人の既読を使わない（初めての日として覚えるだけ）
        XCTAssertNil(store.seen(for: "other"))
        // 古い値で戻さない
        store.mark("2026-01-01T00:00:00Z", for: "me")
        XCTAssertEqual(store.seen(for: "me"), "2026-10-30T00:00:00Z")
        store.removeData(for: "me")
        XCTAssertNil(store.seen(for: "me"))
    }

    /// 既読の覚えは退会で消す・画面は開いた／届いた／人が替わったで覚え直す
    func testSeenIsWiredIntoTheScreenAndAccountRemoval() throws {
        XCTAssertTrue(try source("Core/Storage/AccountLocalData.swift").contains("FollowingSeenStore(defaults: defaults).removeData(for: userId)"))
        let gallery = try source("Features/Gallery/GalleryView.swift")
        XCTAssertTrue(gallery.contains(".onChange(of: FollowingSeenKey(feed: model.feed, newest: followingNewest, viewer: auth.userId),\n                  initial: true)"),
                      "「フォロー中」を開いても既読にならない")
        XCTAssertTrue(gallery.contains("model.followingNewest(viewerId: auth.userId, hiding: dropped)"),
                      "ブロック・通報を落とした写しで決めていない")
    }
}
