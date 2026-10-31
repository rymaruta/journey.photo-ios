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
        XCTAssertTrue(gallery.contains(".modifier(ProfileTabSwipe(tabs: HomeFeed.allCases, selection: feedSelection))"),
                      "札の行の上で払っても替わらない")
        XCTAssertTrue(gallery.contains("ProfileTabPager(tabs: HomeFeed.allCases, selection: feedSelection,"),
                      "中身を横にめくって切り替えない")
        XCTAssertTrue(gallery.contains("rowOverflow: { feedRow.overflow }"), "深く送ってから払うと入ってくる札が空に見える")
        XCTAssertTrue(gallery.contains("minHeight: ProfileTabScroll.minPageHeight(viewport: feedViewport,"),
                      "短いフィードへ替えると送りの位置が詰められて札の行が跳ぶ")
        // 中身はフィードごとに作る（選んでいる1つだけを `model.feed` で分ける形に戻さない）
        XCTAssertTrue(gallery.contains("private func feedSection(_ page: HomeFeed, photos: [Photo]) -> some View {"))
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
            ("Features/Map/PhotoMapView.swift", "ProfileTabBar(tabs: PhotoMapViewModel.Mode.allCases, selection: $model.mode)"),
            ("Features/Upload/PhotoEditView.swift", "ProfileTabBar(tabs: PhotoEditScreen.Tab.allCases, selection: $screen.tab)"),
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
}
