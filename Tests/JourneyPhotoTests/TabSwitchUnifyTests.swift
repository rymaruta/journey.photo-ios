import XCTest
@testable import JourneyPhoto

/// 下線の札の切り替えをアプリ全体でそろえる（2026-10-31 #426・owner「ホームのタブの切り替えもマイページと同じように
/// スムーズに。同じような機能のある画面に水平展開」）。
///
/// お手本はマイページの札（#418・#423）: 下線がばねで滑る・当たりを札の間の半分まで広げる・中身を横にめくる・
/// 一覧を送ると札の行が上に留まる。部品は1つ（`ProfileTabBar`・`ProfileTabPager`・`ProfileTabSection`）で、
/// 画面ごとに写しを作らない
final class TabSwitchUnifyTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto").appendingPathComponent(path),
                          encoding: .utf8)
    }

    // MARK: - ホーム

    // 札 #595（2026-11-13 owner 決定）: ホームの「おすすめ・フォロー中・新着」の切り替えはやめ、1本の並びにした。
    // ホームに札が無いことは `V2HomeSearchNotificationsTests.testHomeHasNoFeedTabs` と
    // `HomeTidyTests.testHomeIsOneFeedWithFollowingOnTop` が見る（ここではマイページ以下の札の部品を見る）

    /// 🔴 札の中身に横に流れる列があっても、その上で始まった指は列に渡す
    func testSwipeLeavesHorizontalScrollersAlone() throws {
        let pager = try source("Features/Profile/ProfileTabPager.swift")
        XCTAssertTrue(pager.contains("return !Self.startsInHorizontalScroller(touch.view, host: host)"),
                      "横に流れる列の上の指まで札の払いが受けている")
        XCTAssertTrue(pager.contains("scroll.isScrollEnabled, scroll.contentSize.width > scroll.bounds.width + 1"))
    }

    // MARK: - 水平展開

    /// 🔴 下線の札の切り替えを持つ画面は、どれも同じ札の部品を使う。自前の下線（瞬時に入れ替わる・当たりが字の幅）を残さない。
    /// 横にめくる画面（中身が縦の一覧）と、めくらない画面（中身が横の操作を持つ）を分ける
    func testEveryUnderlineTabUsesTheSharedParts() throws {
        // 札＋横にめくる中身（縦の送りの中を流れる札の行・`ProfileTabSection`）
        let paged: [(String, String)] = [
            ("Features/Profile/FollowListView.swift", "ProfileTabSection(tabs: Kind.order, selection: selection,"),
            ("Features/Stories/StoryInsightsView.swift", "ProfileTabSection(tabs: Scope.allCases, selection: $scope,"),
            ("Features/Pass/PassBookView.swift", "ProfileTabSection(tabs: PassBook.Order.allCases, selection: $order,"),
            ("Features/Upload/InspiredPickerView.swift", "ProfileTabSection(tabs: InspiredBy.Shelf.allCases, selection: $selectedShelf,"),
        ]
        // 札だけ（中身は横にめくらない——地図を横に動かす・フィルムの列とつまみを横に動かす）
        let barOnly: [(String, String)] = [
            ("Features/Map/PhotoMapView.swift", "ProfileTabBar(tabs: PhotoMapViewModel.Mode.allCases, selection: $model.mode, movesContent: false)"),
            ("Features/Upload/PhotoEditView.swift", "ProfileTabBar(tabs: PhotoEditScreen.Tab.allCases, selection: $screen.tab, movesContent: false)"),
        ]
        for (path, call) in paged + barOnly {
            let text = try source(path)
            XCTAssertTrue(text.contains(call), "\(path) が共通の札を使っていない")
            XCTAssertFalse(text.contains(".fill(selected ? WebTheme.accent : Color.clear)"), "\(path) に自前の下線が残っている")
            XCTAssertFalse(text.contains("Rectangle().fill(selected ? WebTheme.accent : Color.clear)"), "\(path) に自前の下線が残っている")
        }
        for (path, _) in barOnly {
            XCTAssertFalse(try source(path).contains("ProfileTabPager("), "\(path) の中身を横にめくっている（横の操作とぶつかる）")
        }
        // 自前の下線の札が新しく生えていないか（キャンピングカーの部屋は別の板・下の注記）
        let allowed: Set<String> = ["CamperRoomView.swift", "CamperRoomDexView.swift"]
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(files.isEmpty)
        for file in files where !allowed.contains(file.lastPathComponent) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for pattern in ["fill(selected ? WebTheme.accent : Color.clear)", "fill(on ? WebTheme.accent : Color.clear)"] {
                XCTAssertFalse(text.contains(pattern), "\(file.lastPathComponent) に自前の下線の札がある（`ProfileTabBar` を使う）")
            }
        }
    }

    /// 区分の目印（UI テスト・画面写真の道しるべ）は今までの名前のまま
    func testIdentifiersSurvive() {
        XCTAssertEqual(ProfileTab.posts.tabIdentifier, "profile.tab.posts")
        XCTAssertEqual(PhotoMapViewModel.Mode.spots.tabIdentifier, "map.mode.spots")
        XCTAssertEqual(InspiredBy.Shelf.wishlist.tabIdentifier, "inspiredPicker.shelf.wishlist")
        XCTAssertEqual(PhotoEditScreen.Tab.adjust.tabTitle, L("調整", "Adjust"))
        XCTAssertEqual(FollowListView.Kind.followers.tabTitle, FollowListView.Kind.followers.title)
        XCTAssertEqual(PassBook.Order.allCases.map(\.tabTitle), PassBook.Order.allCases.map(\.label))
    }

    /// 流れる札の行の部品は、人のページと同じ手順（位置の控え・替えたら頭から・はみ出し・最低の高さ）を持つ
    func testFlowingSectionKeepsTheProfileSteps() throws {
        let pager = try source("Features/Profile/ProfileTabPager.swift")
        let section = pager.components(separatedBy: "struct ProfileTabSection<")[1]
            .components(separatedBy: "/// 画面を開いてから先に札を作るまでの待ち")[0]
        for part in [".modifier(ProfileTabSwipe(tabs: tabs, selection: $selection))",
                     "if let height = row.record(frame, height: rowHeight) { rowHeight = height }",
                     "rowOverflow: { ProfileTabScroll.rowOverflow(rowMinY: row.minY, visibleTop: 0) }",
                     "ProfileTabScroll.minPageHeight(viewport: viewport, visibleTop: 0,",
                     "guard ProfileTabScroll.scrollsToRow(rowMinY: row.minY, visibleTop: 0) else { return }",
                     "withAnimation(ProfileTabMotion.animation(reduceMotion: reduceMotion)) {"] {
            XCTAssertTrue(section.contains(part), "流れる札の行の部品に「\(part)」が無い")
        }
    }

    // MARK: - 2026-10-31 確かめ役の見直し

    /// 🔴 続きを読む目印は、写真の一覧の遅れて作る並び（`HomeMosaic` の `LazyVStack`）の最後の段。普通の並びに置くと、
    /// 画面の外でも `onAppear` が走り、作り直すたびにまた読んで、送らなくても全部のページを読んでいた
    func testNextPageMarkerIsLazy() throws {
        let gallery = try source("Features/Gallery/GalleryView.swift")
        XCTAssertTrue(gallery.contains("HomeMosaic(groups: rows.rest, onReport: { reportTarget = $0 }, footer: footer(rows))"),
                      "続きの目印が写真の一覧の遅れて作る並びの中に無い")
        XCTAssertTrue(gallery.contains("rows.truncated || model.hasMorePages ? AnyView(pageFooter) : nil"),
                      "並びを切った所（読めた新着を使い切った所）に目印を置いていない")
        let mosaic = try source("Features/Gallery/HomeMosaic.swift")
        let body = mosaic.components(separatedBy: "LazyVStack(spacing: gap) {")[1]
            .components(separatedBy: ".padding(.horizontal, Self.edge)")[0]
        XCTAssertTrue(body.contains("if let footer { footer }"), "目印が遅れて作る並びの外にある（画面の外でも読む）")
        let section = gallery.components(separatedBy: "private func feedSection(_ rows: HomeFeedPageMemo.Rows,")[1]
            .components(separatedBy: "nonisolated static let seasonShelfTopTrim")[0]
        XCTAssertFalse(section.contains("{ pageFooter }"), "普通の並びに続きの目印を置いている（画面の外でも読む）")
    }

    /// 離れた札を捨てる入れ物（`keepsDistantPages: false`）は、選んでいる札と左右の隣だけを持つ
    func testDistantPagesAreDropped() {
        let tabs: [ProfileTab] = [.posts, .trips, .wishlist]
        var pages = ProfileTabPages<ProfileTab>(initial: .posts)
        pages.select(.trips)
        pages.select(.wishlist)
        pages.trim(around: .wishlist, in: tabs)
        XCTAssertEqual(pages.built, [.trips, .wishlist], "2つ離れた札を持ち続けている")
        pages.trim(around: .trips, in: tabs)
        XCTAssertEqual(pages.built, [.trips, .wishlist], "隣を捨てた（払って戻るたびに作り直す）")
        // 🔴 直前に選んでいた札は捨てない（滑っている最中に出ていく札が空になる・すぐ戻るとちらつく）
        var jump = ProfileTabPages<ProfileTab>(initial: .posts)
        jump.select(.wishlist)
        jump.trim(around: .wishlist, keeping: .posts, in: tabs)
        XCTAssertTrue(jump.isBuilt(.posts), "飛んだとき、出ていく札を捨てた")
        jump.select(.trips)
        jump.trim(around: .trips, keeping: .wishlist, in: tabs)
        XCTAssertEqual(Set(jump.built), [.posts, .wishlist, .trips])
    }

    /// 🔴 めくりの入れ物は、選び替えのたびに（直前の札を残して）捨てる
    func testPagerTrimsOnSelectionChange() throws {
        let pager = try source("Features/Profile/ProfileTabPager.swift")
        let body = pager.components(separatedBy: "struct ProfileTabPager<")[1].components(separatedBy: "enum ProfileTabPrebuild")[0]
        XCTAssertTrue(body.contains(".onChange(of: selection) { previous, next in\n            pages.select(next)\n            if !keepsDistantPages { pages.trim(around: next, keeping: previous, in: tabs) }\n        }"),
                      "選び替えたときに離れた札を捨てていない（または直前の札まで捨てる）")
    }

    /// 🔴 ホームの1本の並び（混ぜる・見せない・束ねる・季節の段の割り）は、材料か「見せない」が変わったときだけ計算する
    func testPageRowsAreMemoized() throws {
        let photos = try ["a", "b", "c"].map { id in
            try JSONDecoder.api.decode(Photo.self, from: Data("{\"id\":\"\(id)\",\"src\":\"/u/\(id).jpg\",\"userId\":\"u\(id)\"}".utf8))
        }
        let memo = HomeFeedPageMemo()
        func input(_ rec: [Photo]) -> HomeFeedPageMemo.Input {
            HomeFeedPageMemo.Input(following: [], recommended: rec, latest: [], latestHasMore: false, excluding: [])
        }
        let first = memo.rows(input(photos), hidden: ModerationSnapshot())
        _ = memo.rows(input(photos), hidden: ModerationSnapshot())
        _ = memo.rows(input(Array(photos)), hidden: ModerationSnapshot())
        XCTAssertEqual(memo.computeCount, 1, "描き直しのたびに並べ直している")
        XCTAssertEqual(first.lead.count, 3, "5枚より少ないのに季節の段の後ろへ回した")
        XCTAssertTrue(first.rest.isEmpty)
        _ = memo.rows(input(Array(photos.prefix(2))), hidden: ModerationSnapshot())
        XCTAssertEqual(memo.computeCount, 2, "材料が変わったのに計算し直さない")
        // 🔴 「見せない」が変わったら計算し直す（ブロックした人の写真が並びに残らない）
        var hidden = ModerationSnapshot()
        hidden.blocked = [try XCTUnwrap(photos.first?.userId)]
        let dropped = memo.rows(input(Array(photos.prefix(2))), hidden: hidden)
        XCTAssertEqual(memo.computeCount, 3, "「見せない」が変わったのに前の並びを返した")
        XCTAssertEqual(dropped.lead.count, 1, "ブロックした人の写真が並びに残っている")
        XCTAssertTrue(try source("Features/Gallery/GalleryView.swift").contains("let rows = pageMemo.rows(HomeFeedPageMemo.Input("),
                      "ホームが控えを通さずに並べている")
    }

    /// 🔴 札だけの画面（地図・写真の編集）は中身を動かさない: 選び替えは取引の外で書き、下線だけをばねで動かす。
    /// 既定（横にめくる画面）は今までどおり `withAnimation` で中身も滑る
    func testBarOnlyScreensMoveOnlyTheUnderline() throws {
        let bar = try source("Features/Profile/ProfileTabBar.swift")
        XCTAssertTrue(bar.contains("var movesContent: Bool = true"))
        XCTAssertTrue(bar.contains("if movesContent {\n                withAnimation(ProfileTabMotion.animation(reduceMotion: reduceMotion)) {\n                    selection = option\n                }\n            } else {\n                selection = option\n            }"),
                      "札だけの画面でも中身をばねの取引で替えている")
        XCTAssertTrue(bar.contains(".modifier(ProfileTabRowMotion(selection: selection, animation: movesContent ? nil"),
                      "札だけの画面で下線が滑らない")
        let motion = bar.components(separatedBy: "struct ProfileTabRowMotion<")[1].components(separatedBy: "/// 札の名前の右上の真鍮の点")[0]
        XCTAssertTrue(motion.contains("if let animation {\n            content.animation(animation, value: selection)\n        } else {\n            content\n        }"),
                      "既定の画面にも `.animation(nil, value:)` を掛けて、押したときの滑りを消している")
    }

    /// 🔴 読み上げ: 札の並び全体はタブの並び、札ごとに「何番目 / いくつ」
    func testTabRowSpeaksAsATabBar() throws {
        let bar = try source("Features/Profile/ProfileTabBar.swift")
        let body = bar.components(separatedBy: "var body: some View {")[1].components(separatedBy: "private func tab(")[0]
        XCTAssertTrue(body.contains(".accessibilityElement(children: .contain)"), "札の並びを1つのまとまりにしていない")
        // 🔴 `.isTabBar` を付けると XCUITest の `app.tabBars` に数えられ、下のタブより先に掴まれる
        let code = bar.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertFalse(code.contains(".isTabBar"), "札の行にタブバーの印を付けている（UI テストの下のタブの探し方が崩れる）")
        XCTAssertFalse(code.contains("UIAccessibilityTraits.tabBar"))
        XCTAssertTrue(bar.contains(".accessibilityValue(ProfileTabStyle.position(of: option, in: tabs) ?? \"\")"))
        // 「2/3」は分数と読まれうる。言葉で「3つのうち2つ目」
        XCTAssertEqual(ProfileTabStyle.position(of: ProfileTab.trips, in: [ProfileTab.posts, .trips, .wishlist]), L("3つのうち2つ目", "2 of 3"))
        XCTAssertEqual(ProfileTabStyle.position(of: ProfileTab.favorites, in: ProfileTab.tabs(isMe: true)), L("4つのうち4つ目", "4 of 4"))
        XCTAssertFalse(L("3つのうち2つ目", "2 of 3").contains("/"))
        XCTAssertNil(ProfileTabStyle.position(of: ProfileTab.map, in: ProfileTab.tabs(isMe: true)))
    }

    /// 払いの枠を上へ広げる口（札の行が中身の上の見出しの画面）。広げた分も同じ1つの払いが受ける
    func testSwipeAreaCanReachTheRowAbove() throws {
        let pager = try source("Features/Profile/ProfileTabPager.swift")
        XCTAssertTrue(pager.contains("extendsUp: swipeExtendsUp,"))
        XCTAssertTrue(pager.contains("                    })\n                    // 枠を上へ広げる（札の行が中身の上の見出しの画面）。広げた分も同じ1つの払いが受ける\n                    .padding(.top, -extendsUp)"),
                      "払いの枠が札の行まで届かない")
    }

    // MARK: - 2026-10-31 Mac の確かめ（run 41201788362 の数）

    /// 🔴 ホームの外側の並びは `VStack`（写真の一覧の遅れて作る並びは `HomeMosaic` の中）。外側を遅れて作る並びにすると、
    /// 上の札（`HomeTopCardView`）が流れ出たときに作り直され、季節の段の中身などの状態が消える。節の見出しで留めない
    func testHomeOuterStackIsNotLazy() throws {
        let gallery = try source("Features/Gallery/GalleryView.swift")
        let feed = gallery.components(separatedBy: "private func feed(_ photos: [Photo]) -> some View {")[1]
            .components(separatedBy: "private static let feedTopID")[0]
        XCTAssertFalse(feed.contains("pinnedViews:"), "節の見出しで留めている")
        XCTAssertFalse(feed.contains("LazyVStack("), "外側が遅れて作る並びになっている")
        XCTAssertTrue(feed.contains("VStack(spacing: Self.feedSpacing) {"))
    }

    /// 重ねた札の行の払い: 中身の払いと同じ決まりで、中身の横の量の箱を動かす。入れ物は隣の札を作る手順を入れる
    func testOverlaySwipeSharesThePagerBox() throws {
        let bar = try source("Features/Profile/ProfileTabBar.swift")
        let overlay = bar.components(separatedBy: "struct ProfileTabOverlaySwipe<")[1]
            .components(separatedBy: "/// 札の行の中だけに掛けるばね")[0]
        for part in ["Tab.startsSwipe(from: selection, in: tabs, dx: dx, dy: Double(value.translation.height))",
                     "control.willShow?(next)",
                     "control.drag.offset = CGFloat(Tab.followOffset(from: selection, in: tabs, dx: dx, width: Double(width)))",
                     "let next = Tab.settled(from: selection, in: tabs, dx: Double(value.translation.width),",
                     "control.drag.offset = 0"] {
            XCTAssertTrue(overlay.contains(part), "重ねた札の払いに「\(part)」が無い")
        }
        let pager = try source("Features/Profile/ProfileTabPager.swift")
        XCTAssertTrue(pager.contains("private var dragBox: ProfileTabDrag { control?.drag ?? drag }"))
        XCTAssertTrue(pager.contains("control?.willShow = { next in prepare(next) }"), "重ねた札の払いで隣の札が作られない（空の札が出る）")
        XCTAssertTrue(pager.contains("ProfileTabDragOffset(drag: dragBox, content:"))
    }

    // MARK: - 2026-10-31 177a6ac の確かめ

    /// 🔴 払いの途中で重ねた札が消えたら（留まりが外れた・画面を離れた）、取り消しとして終える
    /// （`onEnded` が来ず、中身のずらしが残っていた・UIKit の払いの `detach` と同じ扱い）
    func testOverlaySwipeCancelsWhenTheRowGoesAway() throws {
        let bar = try source("Features/Profile/ProfileTabBar.swift")
        let overlay = bar.components(separatedBy: "struct ProfileTabOverlaySwipe<")[1]
            .components(separatedBy: "/// 札の行の中だけに掛けるばね")[0]
        XCTAssertTrue(overlay.contains(".onDisappear {\n                if swiping == true { control.drag.offset = 0 }\n                swiping = nil\n            }"),
                      "払いの途中で重ねた札が消えると、中身のずらしが残る")
    }

    /// 🔴 マイページの留まった札も、ホームと同じく札の行の上で払える（手ざわりを割らない）
    func testMyPagePinnedRowSwipesLikeHome() throws {
        let mine = try source("Features/Profile/MyPageView.swift")
        let pinned = mine.components(separatedBy: "private var pinnedTabRow: some View {")[1]
            .components(separatedBy: "\n    }\n")[0]
        XCTAssertTrue(pinned.contains(".modifier(ProfileTabOverlaySwipe(tabs: ProfileTab.tabs(isMe: true), selection: $tab, control: tabPager))"),
                      "マイページの留まった札の上で払えない")
        XCTAssertTrue(mine.contains("control: tabPager) { page in"), "留まった札の払いが中身の箱を動かさない（指に付いてこない）")
    }

    /// 🔴 外側を `VStack` にしたので、上の札は流れ出ても `onDisappear` が来ない。main（`LazyVStack`）の扱い
    /// （流れ出たら差し替えを後回し・戻ったら前面の確定を待って読み直す）を位置で続ける
    func testTopCardsKeepTheScrolledAwayHandling() throws {
        let gallery = try source("Features/Gallery/GalleryView.swift")
        XCTAssertTrue(gallery.contains("scrolledAway: topCardsAway)"))
        XCTAssertTrue(gallery.contains("proxy.frame(in: .scrollView).maxY < 0"), "流れ切ったかを測っていない")
        let top = try source("Features/Gallery/HomeTopCardView.swift")
        XCTAssertTrue(top.contains(".onChange(of: scrolledAway) { _, away in\n                if away { wentOutOfView() } else { cameIntoView() }\n            }"),
                      "流れ出ても札の差し替えを後回しにしない（深く送っている間に札の高さが変わって下の写真がずれる）")
        XCTAssertTrue(top.contains(".onAppear { cameIntoView() }"))
        XCTAssertTrue(top.contains(".onDisappear { wentOutOfView() }"))
        let out = top.components(separatedBy: "private func wentOutOfView() {")[1].components(separatedBy: "\n    }\n")[0]
        XCTAssertTrue(out.contains("front.disappear()") && out.contains("isShown = false"))
    }
}
