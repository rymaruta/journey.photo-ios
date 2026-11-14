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
        // 札の面は 2026-11-12 に `TopCardFace` へ切り出した（探すの今日の一問も同じ面）
        let card = try source("Features/Gallery/TopCardFace.swift")
        // 題・一行・小さい行（写真の無い札）の3つと、出典の行（`creditLine`）の形の3つ（全文の形・作者・ライセンス）。
        // 2026-11-14: 出典の行も1行のまま（札の背を変えない・owner「出典のせいで縦をとるのあんまり好きじゃない」）
        XCTAssertEqual(card.components(separatedBy: ".lineLimit(HomeTopCardView.lineLimit)").count - 1, 6,
                       "題・一行・小さい行・出典の行が1行でない")
        XCTAssertFalse(card.contains(".lineLimit(2)"))
        assertInOrder([".lineLimit(HomeTopCardView.lineLimit)", ".truncationMode(detailTruncation)"], in: card,
                      "写真の無い札の小さい行の切り方が無い")
    }

    /// 出典は1行（地域　作者とライセンス）。改行で2行にしない（`TopCardCredit`・2026-11-14 判断）
    func testSpotDetailIsOneLine() {
        let photo = SpotImage(url: URL(string: "https://example.com/a.jpg")!, author: "A", license: "CC BY-SA 4.0",
                              pageUrl: nil)
        let credit = TopCardCredit(region: "岡山", prefecture: "岡山", photo: photo)
        XCTAssertEqual(credit.spoken, "岡山\u{2002}" + L("写真: A", "Photo: A") + " / CC BY-SA 4.0")
        XCTAssertTrue(credit.wholeLines.allSatisfy { !$0.contains("\n") })
        XCTAssertEqual(TopCardCredit(photo: photo).spoken, photo.credit)
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

    // MARK: - ④ 季節の段は1本の並びの中・写真の大1→2→2 の後ろ（札 #595 で「おすすめ」の札は無くなった）

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
        // 束ねと 5 枚の割りは控え（`HomeFeedPageMemo.make`）が計算する
        let make = slice(gallery, from: "static func make(_ input: Input, hidden: ModerationSnapshot) -> Rows {",
                         to: "private struct PassResolveKey")
        assertInOrder(["HomeFeed.arrange(following: hidden.visible(input.following),",
                       "HomeFeed.splitForSeasonShelf(main)"], in: make, "季節の段の前後に割る")
        let section = slice(gallery, from: "private func feedSection(_ rows: HomeFeedPageMemo.Rows, featured: [FeaturedGroups.Group]) -> some View {",
                            to: "nonisolated static let seasonShelfTopTrim")
        // 段の有無に関係なくいつも5枚で割り、段だけを挟む（後から届いた段で一覧を作り直さない）。写真が0枚の日は段を出さない
        assertInOrder(["featuredSections(featured)",
                       "HomeMosaic(groups: rows.lead",
                       "if !isEmpty, let seasonShelf {",
                       "HomeSpotShelfView(shelf: seasonShelf.shelf",
                       "HomeMosaic(groups: rows.rest"], in: section, "季節の段の置き場所")
        // 続きの目印は並びの遅れて作る段の最後（`HomeMosaic` の footer）。普通の並びに置かない
        XCTAssertFalse(section.contains("{ pageFooter }"))
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
        XCTAssertTrue(HomeSpotShelf.note.contains(L("各観光スポットの作例", "examples for each spot")))
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

    // MARK: - ⑧⑨ 札 #595: 切り替え（留まる札の行・「フォロー中」の点）はやめて1本の並び

    /// 上から: 上の札 → フォロー中の人の新しい写真 → 選ばれた写真の横並び → 混ぜた並び。切り替えの札・留まる札・点は無い
    func testHomeIsOneFeedWithFollowingOnTop() throws {
        let gallery = try source("Features/Gallery/GalleryView.swift")
        let feed = slice(gallery, from: "private func feed(_ photos: [Photo]) -> some View", to: "private static let feedTopID")
        assertInOrder(["VStack(spacing: Self.feedSpacing) {",
                       "HomeTopCardView(",
                       "feedSection(rows, featured: featured)"], in: feed, "上の札の下に1本の並び")
        let section = slice(gallery, from: "private func feedSection(_ rows: HomeFeedPageMemo.Rows, featured: [FeaturedGroups.Group]) -> some View {",
                            to: "nonisolated static let seasonShelfTopTrim")
        assertInOrder(["if !rows.following.isEmpty {",
                       "JPSectionHeading(eyebrow: \"FOLLOWING\"",
                       "HomeMosaic(groups: rows.following",
                       "featuredSections(featured)",
                       "HomeMosaic(groups: rows.lead"], in: section, "フォロー中の人の新しい写真がいちばん上")
        for gone in ["feedPicker(", "pinnedFeedRow(", "feedRowPinned", "ProfileTabDot", "followingHasNew", "model.feed"] {
            XCTAssertFalse(gallery.contains(gone), "切り替えの名残（\(gone)）が残っている")
        }
        XCTAssertFalse(try source("Features/Gallery/GalleryViewModel.swift").contains("var feed: HomeFeed"),
                       "選んでいるフィードの状態が残っている")
        // 推薦の仕組みがあるように見せない: 「おすすめ」の注釈・札の言葉を画面に出さない
        let homeFeed = try source("Core/Text/HomeFeed.swift")
        XCTAssertFalse(homeFeed.contains("L(\"おすすめ\""), "「おすすめ」の札の言葉が残っている")
        XCTAssertFalse(homeFeed.contains("選ばれた写真と、よく見られている写真から"), "おすすめの注釈が残っている")
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
        XCTAssertNil(HomeFollowingNews.newest(photos, viewerId: nil, followingIds: ["f"]), "未ログインでフォロー中の段を作る")
        XCTAssertNil(HomeFollowingNews.newest(photos, viewerId: "me", followingIds: []), "誰もフォローしていないのにフォロー中の段を作る")
    }

    /// 🔴 振る舞い: 覚えが無い → 全部が新しい（上に出す）。出したら覚える。**見ている間は基準を替えない**
    /// （上の段が消えて下がずれない）。引き下げ（基準の読み直し）で、出した分は上から外れ、届いた新しい分だけが上に出る。
    /// 人ごとに分かれる・戻さない・退会で消える
    func testFollowingSectionLifecycle() throws {
        let suite = "HomeTidyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FollowingSeenStore(defaults: defaults)
        var baseline = FollowingBaseline()
        var photos = [try photo("old", owner: "f", at: "2026-10-01T00:00:00Z")]

        /// 画面と同じ順: 基準で上の段を作る → 出したら、いちばん新しい投稿日を覚える（基準は替えない）
        func render() -> [String] {
            let shown = HomeFeed.followingFresh(photos, viewerId: "me", followingIds: ["f"], seen: baseline.seen)
            if !shown.isEmpty, let newest = HomeFollowingNews.newest(photos, viewerId: "me", followingIds: ["f"]) {
                store.mark(newest, for: "me")
            }
            return shown.map(\.id)
        }

        baseline.capture(viewer: "me", store: store)
        XCTAssertEqual(render(), ["old"], "覚えが無いのに上に出さない")
        XCTAssertEqual(store.seen(for: "me"), "2026-10-01T00:00:00Z")
        XCTAssertEqual(render(), ["old"], "見ている間に上の段が消えた（基準を替えた）")
        baseline.capture(viewer: "me", store: store)   // 引き下げ
        XCTAssertEqual(render(), [], "一度上に出した写真を、引き下げのあともまた上に出した")
        photos.append(try photo("new", owner: "f", at: "2026-10-30T00:00:00Z"))
        XCTAssertEqual(render(), ["new"], "フォロー中の人の新しい写真が上に出ない")
        // 別の人には前の人の覚えを使わない
        baseline.capture(viewer: "other", store: store)
        XCTAssertEqual(baseline.viewer, "other")
        XCTAssertNil(baseline.seen)
        // 古い値で戻さない
        store.mark("2026-01-01T00:00:00Z", for: "me")
        XCTAssertEqual(store.seen(for: "me"), "2026-10-30T00:00:00Z")
        store.removeData(for: "me")
        XCTAssertNil(store.seen(for: "me"))
    }

    /// 覚えは退会で消す・画面は人が決まったとき・引き下げで基準を読み直し、上の段を出したら覚える
    func testSeenIsWiredIntoTheScreenAndAccountRemoval() throws {
        XCTAssertTrue(try source("Core/Storage/AccountLocalData.swift").contains("FollowingSeenStore(defaults: defaults).removeData(for: userId)"))
        let gallery = try source("Features/Gallery/GalleryView.swift")
        XCTAssertEqual(gallery.components(separatedBy: "followingBaseline.capture(viewer:").count - 1, 2,
                       "人が決まったとき・引き下げのときに基準を読み直していない")
        XCTAssertTrue(gallery.contains(".onChange(of: rows.following.map(\\.id), initial: true)"), "上の段を出しても覚えない")
        XCTAssertTrue(gallery.contains("markFollowingShown(fresh)"), "上に出した分ではなく、候補の全部で覚えている")
        XCTAssertTrue(gallery.contains("alwaysNew: followingBaseline.followees, hiding: dropped)"),
                      "ブロック・通報を落とした写しで決めていない・新しくフォローした人を覚えに関係なく出していない")
        XCTAssertTrue(gallery.contains("followingBaseline.settle(candidates: key.candidates, atHead: key.atHead)"),
                      "上に出す分を、頭にいるときだけ決め直していない")
        XCTAssertTrue(gallery.contains("followingBaseline.addFollowees(followed)"), "おすすめの人でフォローした人の写真が上に出ない")
    }
}
