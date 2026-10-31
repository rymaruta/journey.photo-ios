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

    /// 🔴 ホームのフィードの切り替えは、マイページと同じ札の部品で、中身を横にめくる（札の行でも中身でも払える）
    func testHomeFeedUsesTheMyPageTabParts() throws {
        let gallery = try source("Features/Gallery/GalleryView.swift")
        XCTAssertTrue(gallery.contains("ProfileTabBar(tabs: HomeFeed.allCases, selection: feedSelection, stuck: feedRowPinned,"),
                      "ホームの切り替えが共通の札でない（下線が滑らない・当たりが狭い）")
        // 札の行の上の払いは中身の払い1つが枠を広げて受ける（2つ付けると留まった札の行の上で指を取り合う）
        XCTAssertFalse(gallery.contains(".modifier(ProfileTabSwipe(tabs: HomeFeed.allCases"),
                       "札の行に別の払いを付けている（留まった札の行の上で中身の払いと指を取り合う）")
        XCTAssertTrue(gallery.contains("swipeExtendsUp: feedRowHeight + Self.feedSpacing) { page in"),
                      "札の行の上で払っても替わらない（中身の払いの枠が札の行まで届かない）")
        XCTAssertTrue(gallery.contains("keepsDistantPages: false,"), "離れた札の中身まで持ち続けている（ホームが重い）")
        XCTAssertTrue(gallery.contains("ProfileTabPager(tabs: HomeFeed.allCases, selection: feedSelection,"),
                      "中身を横にめくって切り替えない")
        XCTAssertTrue(gallery.contains("rowOverflow: { feedRow.overflow }"), "深く送ってから払うと入ってくる札が空に見える")
        XCTAssertTrue(gallery.contains("minHeight: ProfileTabScroll.minPageHeight(viewport: feedViewport,"),
                      "短いフィードへ替えると送りの位置が詰められて札の行が跳ぶ")
        // 中身はフィードごとに作る（選んでいる1つだけを `model.feed` で分ける形に戻さない）
        XCTAssertTrue(gallery.contains("private func feedSection(_ page: HomeFeed, rows: HomeFeedPageMemo.Rows) -> some View {"))
        XCTAssertFalse(gallery.contains("if model.feed.showsFeatured"), "中身を選んでいるフィードで分けている（隣の札が同じ中身になる）")
        // 自前の札（瞬時に入れ替わる下線）に戻さない
        XCTAssertFalse(gallery.contains(".fill(selected ? WebTheme.accent : Color.clear)"), "自前の下線が残っている")
        XCTAssertEqual(HomeFeed.allCases.map(\.tabIdentifier), ["home.feed.recommended", "home.feed.following", "home.feed.latest"],
                       "UI テスト・画面写真の道しるべが変わった")
    }

    /// 払いの決まりはマイページと同じ（端で回り込まない・3 割か勢いで替わる）
    func testHomeFeedSwipesLikeMyPage() {
        let feeds = HomeFeed.allCases
        XCTAssertEqual(HomeFeed.settled(from: .recommended, in: feeds, dx: -150, velocity: 0, width: 390), .following)
        XCTAssertEqual(HomeFeed.settled(from: .following, in: feeds, dx: -20, velocity: -700, width: 390), .latest)
        XCTAssertEqual(HomeFeed.settled(from: .latest, in: feeds, dx: 150, velocity: 0, width: 390), .following)
        XCTAssertNil(HomeFeed.settled(from: .recommended, in: feeds, dx: 150, velocity: 0, width: 390), "端で回り込んでいる")
        XCTAssertNil(HomeFeed.settled(from: .recommended, in: feeds, dx: -60, velocity: 0, width: 390), "少し動かしただけで替わる")
        XCTAssertFalse(HomeFeed.startsSwipe(from: .following, in: feeds, dx: 10, dy: 20), "縦の送りで札の払いが始まる")
        XCTAssertEqual(HomeFeed.swipeCommitFraction, ProfileTab.swipeCommitFraction)
        XCTAssertEqual(HomeFeed.swipeFlingVelocity, ProfileTab.swipeFlingVelocity)
    }

    /// 🔴 札の行が留まったか・中身がどれだけ流れたかは、見出し（札の行）の下端と中身の上端の間で見る。
    /// 留まっていない間は間が変わらず、留まると中身だけ流れて詰まる。**元の間は測った中でいちばん広い間**
    func testPinnedRowSpotMeasuresTheOverflow() {
        let spot = PinnedTabRowSpot()
        XCTAssertFalse(spot.settle(), "何も測っていないのに留まっている")
        XCTAssertEqual(spot.overflow, 0)
        // 開いたとき（札の行は画面の中ほど・間 24）
        spot.recordHeader(maxY: 600, settled: { _ in })
        spot.recordContent(minY: 624, settled: { _ in })
        XCTAssertFalse(spot.settle())
        XCTAssertEqual(spot.restGap, 24)
        // 送っても留まる前は間が変わらない
        spot.recordHeader(maxY: 120, settled: { _ in })
        spot.recordContent(minY: 144, settled: { _ in })
        XCTAssertFalse(spot.settle(), "留まる前に留まったと言う")
        // 留まった（札の行は見出しの下で止まり、中身だけ上へ流れる）
        spot.recordHeader(maxY: 48, settled: { _ in })
        spot.recordContent(minY: -500, settled: { _ in })
        XCTAssertTrue(spot.settle(), "中身が札の行の下へ潜っても留まったと言わない")
        XCTAssertEqual(spot.overflow, 572, "隣の札を下げる量が違う（48 + 24 + 500）")
        XCTAssertEqual(spot.restGap, 24, "留まって詰まった間を元の間として覚えた")
        // 引き下げ（上に伸びる）も2つ一緒に動くので留まらない
        spot.recordHeader(maxY: 700, settled: { _ in })
        spot.recordContent(minY: 724, settled: { _ in })
        XCTAssertFalse(spot.settle())
        XCTAssertEqual(ProfileTabScroll.pinnedOverflow(gap: 24, restGap: 24), 0)
        XCTAssertEqual(ProfileTabScroll.pinnedOverflow(gap: 30, restGap: 24), 0, "間が広がったのにはみ出しを出した")
    }

    /// 🔴 2つの位置は別々に届くので、片方だけ新しい値で間を覚えない（次の回りにまとめて計算する）
    func testPinnedRowSpotSettlesAfterBothPositionsArrive() throws {
        let pager = try source("Features/Profile/ProfileTabPager.swift")
        let spot = pager.components(separatedBy: "final class PinnedTabRowSpot {")[1]
            .components(separatedBy: "/// 札の行の位置の計算")[0]
        XCTAssertTrue(spot.contains("DispatchQueue.main.async { [self] in"), "届いたその場で計算している（1フレームずれた間を覚える）")
        XCTAssertTrue(spot.contains("guard !scheduled else { return }"), "送るたびに何度も計算を積む")
        let record = spot.components(separatedBy: "func recordHeader(")[1].components(separatedBy: "func settle()")[0]
        XCTAssertFalse(record.contains("restGap ="), "位置が届いたその場で元の間を覚えている")
    }

    /// 🔴 ホームの「おすすめ」には横に流れる列（PICKS・季節の撮影スポット）がある。その上で始まった指は列に渡す
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

    /// 🔴 「新着」の続きを読む目印は、外側の `LazyVStack` の子（札の中身の外）。札の中身の普通の並びに置くと、
    /// 画面の外でも `onAppear` が走り、作り直すたびにまた読んで、送らなくても全部のページを読んでいた
    func testNextPageMarkerIsLazy() throws {
        let gallery = try source("Features/Gallery/GalleryView.swift")
        let feed = gallery.components(separatedBy: "private func feed(_ photos: [Photo]) -> some View {")[1]
            .components(separatedBy: "private static let feedTopID")[0]
        let lazy = try XCTUnwrap(feed.range(of: "LazyVStack(spacing: 24, pinnedViews: [.sectionHeaders]) {"))
        let header = try XCTUnwrap(feed.range(of: "} header: {"))
        let footer = try XCTUnwrap(feed.range(of: "\n                pageFooter\n"), "目印が外側の遅延の並びの子でない")
        let lazyEnd = try XCTUnwrap(feed.range(of: "            .padding(.top, 8)"))
        XCTAssertLessThan(lazy.lowerBound, footer.lowerBound)
        XCTAssertLessThan(header.lowerBound, footer.lowerBound, "目印が札の行より前にある")
        XCTAssertLessThan(footer.lowerBound, lazyEnd.lowerBound, "目印が遅延の並びの外にある")
        let section = gallery.components(separatedBy: "private func feedSection(_ page: HomeFeed,")[1]
            .components(separatedBy: "nonisolated static let seasonShelfTopTrim")[0]
        XCTAssertFalse(section.contains("{ pageFooter }"), "札の中身に続きの目印を置いている（画面の外でも読む）")
        XCTAssertFalse(section.contains("\n        pageFooter"), "札の中身に続きの目印を置いている（画面の外でも読む）")
    }

    /// 🔴 元の間は「留まっていない」と分かる回に覚え直す。一度広すぎる間を測っても、留まったと思い込み続けない
    func testPinnedRowSpotRelearnsATooWideGap() {
        let spot = PinnedTabRowSpot()
        // 開いた最初の回にずれた間（100）を測った
        spot.recordHeader(maxY: 600, settled: { _ in })
        spot.recordContent(minY: 700, settled: { _ in })
        spot.settle()
        // 中身だけ動いた（留まりと見分けられない）回は覚え直さない
        spot.recordHeader(maxY: 520, settled: { _ in })
        spot.recordContent(minY: 544, settled: { _ in })
        spot.settle()
        // 2つが同じだけ動いた＝流れている → 本当の間（24）を覚え直す
        spot.recordHeader(maxY: 500, settled: { _ in })
        spot.recordContent(minY: 524, settled: { _ in })
        XCTAssertFalse(spot.settle(), "広すぎる間を覚えたまま、留まったと思い込んでいる")
        XCTAssertEqual(spot.restGap, 24)
        XCTAssertTrue(PinnedTabRowSpot.isFlowing(header: 10, content: 30, previousHeader: nil, previousContent: nil))
        XCTAssertFalse(PinnedTabRowSpot.isFlowing(header: 48, content: -300, previousHeader: 48, previousContent: -200),
                       "留まった札の行の下で中身だけ流れた回を、流れていると言う")
    }

    /// ホームは選んでいる札と左右の隣だけを持つ（マイページ・人のページは持ち続ける）
    func testDistantPagesAreDropped() {
        let feeds = HomeFeed.allCases
        var pages = ProfileTabPages<HomeFeed>(initial: .recommended)
        pages.select(.following)
        pages.select(.latest)
        pages.trim(around: .latest, in: feeds)
        XCTAssertEqual(pages.built, [.following, .latest], "2つ離れた「おすすめ」を持ち続けている")
        pages.trim(around: .following, in: feeds)
        XCTAssertEqual(pages.built, [.following, .latest], "隣を捨てた（払って戻るたびに作り直す）")
        // 🔴 直前に選んでいた札は捨てない（滑っている最中に出ていく札が空になる・すぐ戻るとちらつく）
        var jump = ProfileTabPages<HomeFeed>(initial: .recommended)
        jump.select(.latest)
        jump.trim(around: .latest, keeping: .recommended, in: feeds)
        XCTAssertTrue(jump.isBuilt(.recommended), "おすすめ → 新着と飛んだとき、出ていくおすすめを捨てた")
        jump.select(.following)
        jump.trim(around: .following, keeping: .latest, in: feeds)
        XCTAssertEqual(Set(jump.built), [.recommended, .latest, .following])
    }

    /// 🔴 めくりの入れ物は、選び替えのたびに（直前の札を残して）捨てる
    func testPagerTrimsOnSelectionChange() throws {
        let pager = try source("Features/Profile/ProfileTabPager.swift")
        let body = pager.components(separatedBy: "struct ProfileTabPager<")[1].components(separatedBy: "enum ProfileTabPrebuild")[0]
        XCTAssertTrue(body.contains(".onChange(of: selection) { previous, next in\n            pages.select(next)\n            if !keepsDistantPages { pages.trim(around: next, keeping: previous, in: tabs) }\n        }"),
                      "選び替えたときに離れた札を捨てていない（または直前の札まで捨てる）")
    }

    /// 🔴 札ごとの束ね（見せない・束ねる・季節の段の割り）は、元の写真か「見せない」が変わったときだけ計算する
    func testPageRowsAreMemoized() throws {
        let photos = try ["a", "b", "c"].map { id in
            try JSONDecoder.api.decode(Photo.self, from: Data("{\"id\":\"\(id)\",\"src\":\"/u/\(id).jpg\",\"userId\":\"u\(id)\"}".utf8))
        }
        let memo = HomeFeedPageMemo()
        let first = memo.rows(.recommended, photos: photos, hidden: ModerationSnapshot())
        _ = memo.rows(.recommended, photos: photos, hidden: ModerationSnapshot())
        _ = memo.rows(.recommended, photos: Array(photos), hidden: ModerationSnapshot())
        XCTAssertEqual(memo.computeCount(.recommended), 1, "描き直しのたびに束ね直している")
        XCTAssertEqual(first.groups.count, 3)
        XCTAssertEqual(first.lead.count, 3, "5枚より少ないのに季節の段の後ろへ回した")
        _ = memo.rows(.recommended, photos: Array(photos.prefix(2)), hidden: ModerationSnapshot())
        XCTAssertEqual(memo.computeCount(.recommended), 2, "元の写真が変わったのに計算し直さない")
        let latest = memo.rows(.latest, photos: photos, hidden: ModerationSnapshot())
        XCTAssertEqual(latest.lead.count, 3)
        XCTAssertTrue(latest.rest.isEmpty, "季節の段の無いフィードを割った")
        XCTAssertEqual(memo.computeCount(.recommended), 2, "別の札の計算でおすすめの控えが消えた")
        // 🔴 「見せない」が変わったら計算し直す（ブロックした人の写真が札に残らない）
        let blocked = try XCTUnwrap(photos.first?.userId)
        var hidden = ModerationSnapshot()
        hidden.blocked = [blocked]
        let dropped = memo.rows(.recommended, photos: Array(photos.prefix(2)), hidden: hidden)
        XCTAssertEqual(memo.computeCount(.recommended), 3, "「見せない」が変わったのに前の束ねを返した")
        XCTAssertEqual(dropped.groups.count, 1, "ブロックした人の写真が札に残っている")
        XCTAssertTrue(try source("Features/Gallery/GalleryView.swift").contains("return pageMemo.rows(page, photos: raw, hidden: dropped)"),
                      "ホームが控えを通さずに束ねている")
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
        XCTAssertEqual(ProfileTabStyle.position(of: HomeFeed.following, in: HomeFeed.allCases), L("3つのうち2つ目", "2 of 3"))
        XCTAssertEqual(ProfileTabStyle.position(of: ProfileTab.favorites, in: ProfileTab.tabs(isMe: true)), L("4つのうち4つ目", "4 of 4"))
        XCTAssertFalse(L("3つのうち2つ目", "2 of 3").contains("/"))
        XCTAssertNil(ProfileTabStyle.position(of: ProfileTab.map, in: ProfileTab.tabs(isMe: true)))
    }

    /// 払いの枠を上へ広げる口（ホーム）。広げた分も同じ1つの払いが受ける
    func testSwipeAreaCanReachTheRowAbove() throws {
        let pager = try source("Features/Profile/ProfileTabPager.swift")
        XCTAssertTrue(pager.contains("extendsUp: swipeExtendsUp,"))
        XCTAssertTrue(pager.contains("                    })\n                    // 枠を上へ広げる（札の行が中身の上の見出しの画面）。広げた分も同じ1つの払いが受ける\n                    .padding(.top, -extendsUp)"),
                      "払いの枠が札の行まで届かない")
    }

    // MARK: - 2026-10-31 Mac の確かめ（run 41187923424・testSwipesHomeFeedTabs）

    /// 🔴 留まったまま替えたら、測った量だけ送りを戻す（いちばん上より上へは行かない）。
    /// 札の行は留まりの位置のまま、新しい札の頭が札の行のすぐ下に出る
    func testScrollBackUsesTheMeasuredOverflow() throws {
        // 深く送った（送りの位置 1570）・中身の頭が札の行の下から 1128 上へ流れている → 442 へ戻す（札の行は留まりの境）
        XCTAssertEqual(ProfileTabScroll.offsetBack(current: 1570, distance: 1128, top: -116), 442)
        // いちばん上より上へは行かない
        XCTAssertEqual(ProfileTabScroll.offsetBack(current: 100, distance: 900, top: -116), -116)
        XCTAssertEqual(ProfileTabScroll.offsetBack(current: 300, distance: -20, top: -116), 300, "負の量で先へ送った")
        let pager = try source("Features/Profile/ProfileTabPager.swift")
        let handle = pager.components(separatedBy: "final class ScrollHostHandle {")[1]
            .components(separatedBy: "struct ScrollHostProbe: View {")[0]
        XCTAssertTrue(handle.contains("let target = ProfileTabScroll.offsetBack(current: scroll.contentOffset.y, distance: distance,"))
        XCTAssertTrue(handle.contains("top: -scroll.adjustedContentInset.top)"))
        XCTAssertTrue(handle.contains("usingSpringWithDamping: ProfileTabScroll.scrollBackDamping"))
        XCTAssertEqual(ProfileTabScroll.scrollBackDamping, 1, "戻す動きが行き過ぎる（留まった札の行が一度外れて下がる）")
        // 🔴 Mac の2回目（札の行が 116 → 118.33）: はみ出しをちょうど戻すと境目に来て、小さなずれで留まりから外れる。
        // 留まりの側に 4 残す。残りが遊び以下なら戻さない（2回目の切り替えで動かない）
        XCTAssertTrue(handle.contains("let distance = ProfileTabScroll.scrollBackDistance(overflow: overflow)"))
        XCTAssertEqual(ProfileTabScroll.pinnedSlack, 4)
        XCTAssertEqual(ProfileTabScroll.scrollBackDistance(overflow: 1128), 1124)
        XCTAssertEqual(ProfileTabScroll.scrollBackDistance(overflow: 4), 0, "前に戻した残りをまた戻す（札の行が境目を越える）")
        XCTAssertEqual(ProfileTabScroll.scrollBackDistance(overflow: 2.33), 0)
        // 戻した後も札の行は留まったと見なされる（遊び 4 > 判定の 0.5）——次の切り替えで「留まっていない」扱いにならない
        XCTAssertGreaterThan(ProfileTabScroll.pinnedSlack, 0.5)
        XCTAssertTrue(handle.contains("scroll.setContentOffset(point, animated: false)"), "視差効果を減らすでも動かしている")
        let gallery = try source("Features/Gallery/GalleryView.swift")
        XCTAssertTrue(gallery.contains("if changed, feedRow.isPinned { feedScroll.scrollBack(feedRow.overflow, reduceMotion: reduceMotion) }"))
        XCTAssertFalse(gallery.contains("proxy.scrollTo(Self.feedPickerID"), "留まった札の行を目印に scrollTo している")
    }
}
