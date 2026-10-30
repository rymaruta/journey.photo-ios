import XCTest
@testable import JourneyPhoto

/// プロフィールの下の札の切り替え（2026-10-24 owner「切り替えスムーズにできるようにしたい」・`ProfileTabPager`）。
/// 一度開いた札を持ち続けること・並べ方・動き・払い・両方のページが同じ部品を使うことを見張る
final class ProfileTabPagerTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 🔴 一度開いた札は持ち続ける（戻ったときに作り直さない）。開いていない札は作らない
    func testVisitedTabsAreKept() {
        var pages = ProfileTabPages(initial: .posts)
        XCTAssertTrue(pages.isBuilt(.posts))
        XCTAssertFalse(pages.isBuilt(.trips), "開いていない札まで作っている")
        pages.select(.trips)
        pages.select(.posts)
        XCTAssertTrue(pages.isBuilt(.trips), "戻ったら前の札を捨てている")
        XCTAssertTrue(pages.isBuilt(.posts))
        XCTAssertFalse(pages.isBuilt(.favorites))
        pages.select(.trips)
        XCTAssertEqual(pages.built, [.posts, .trips], "同じ札を二度足している")
    }

    /// 札は横に並ぶ（選んだ札が 0・右隣が画面幅 1つ分）
    func testPagesSitSideBySide() {
        let tabs = ProfileTab.tabs(isMe: true)
        XCTAssertEqual(ProfileTabPages.offset(of: .posts, selected: .posts, in: tabs), 0)
        XCTAssertEqual(ProfileTabPages.offset(of: .trips, selected: .posts, in: tabs), 1)
        XCTAssertEqual(ProfileTabPages.offset(of: .posts, selected: .wishlist, in: tabs), -2)
        XCTAssertEqual(ProfileTabPagerLayout.x(of: 3, selected: 1, width: 390), 780)
        XCTAssertEqual(ProfileTabPagerLayout.x(of: 0, selected: 1, width: 390), -390)
        XCTAssertEqual(ProfileTabPagerLayout.x(of: 1, selected: 1, width: 390), 0)
    }

    /// 「視差効果を減らす」のときは動かさない
    func testReduceMotionStopsTheSlide() {
        XCTAssertNil(ProfileTabMotion.animation(reduceMotion: true))
        XCTAssertNotNil(ProfileTabMotion.animation(reduceMotion: false))
    }

    /// 払いの判定（端で回り込まない）。人のページ（投稿 / マップ）でも同じ。**投稿から地図へ入る払いは効く**
    func testSwipeMovesToTheNeighbour() {
        let mine = ProfileTab.tabs(isMe: true)
        XCTAssertEqual(ProfileTab.settled(from: .posts, in: mine, dx: -150, velocity: 0, width: 390), .trips)
        XCTAssertEqual(ProfileTab.settled(from: .trips, in: mine, dx: 150, velocity: 0, width: 390), .posts)
        XCTAssertNil(ProfileTab.settled(from: .posts, in: mine, dx: 150, velocity: 0, width: 390), "端で回り込んでいる")
        let theirs = ProfileTab.tabs(isMe: false)
        XCTAssertTrue(ProfileTab.startsSwipe(from: .posts, in: theirs, dx: -12, dy: 2), "投稿から地図へ払い始められない")
        XCTAssertEqual(ProfileTab.settled(from: .posts, in: theirs, dx: -60, velocity: -700, width: 390), .map)
        XCTAssertEqual(ProfileTab.settled(from: .map, in: theirs, dx: 150, velocity: 0, width: 390), .posts)
    }

    /// 🔴 2026-10-28（owner の実機で払っても替わらない）: 払いは SwiftUI の `DragGesture` ではなく、縦の送りの
    /// `UIScrollView` に足す UIKit のパンで受ける（`DragGesture` は縦の送りが始まると取り消され、離したときの
    /// 判定まで届かなかった）。縦の送りはパンが「始めない」と決まってから・中身は指に付いてくる
    func testSwipeIsAUIKitPanThatLocksDirection() throws {
        let pager = try source("Sources/JourneyPhoto/Features/Profile/ProfileTabPager.swift")
        let swipe = String(pager[pager.range(of: "struct ProfileTabSwipe")!.lowerBound...])
        XCTAssertFalse(swipe.contains("DragGesture("), "払いが SwiftUI の DragGesture に戻っている")
        XCTAssertFalse(swipe.contains(".simultaneousGesture("))
        XCTAssertTrue(swipe.contains("UIPanGestureRecognizer("))
        XCTAssertTrue(swipe.contains("shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {\n            gestureRecognizer === pan && otherGestureRecognizer === host?.panGestureRecognizer"),
                      "縦の送りがパンの判定を待たない（向きが固定されない）")
        XCTAssertTrue(swipe.contains("ProfileTab.startsSwipe(from: selection, in: tabs, dx: dx, dy: dy)"))
        XCTAssertTrue(swipe.contains("ProfileTab.settled(from: selection, in: tabs,"))
        // 選んでいる札が止めている（地図）ときは、枠の中の指を受けない
        XCTAssertTrue(swipe.contains("handlers?.isEnabled == true"))
        // 中身が指に付いてくる
        XCTAssertTrue(pager.contains("content.offset(x: drag.offset)"))
        XCTAssertTrue(pager.contains("enabled: !swipeBlocked.contains(selection), follow: drag,"))
    }

    /// 🔴 2026-10-28 確かめ役の見直し: 払っている間に入れ物の `body`（全部の札の `page()`）を作り直さない。
    /// 横の量は見張らない箱に置き、小さな子だけが読む。隣の札は未作成のときだけ足す。途中で離れたら残さない
    func testDragDoesNotRebuildEveryPage() throws {
        let pager = try source("Sources/JourneyPhoto/Features/Profile/ProfileTabPager.swift")
        let body = String(pager[pager.range(of: "struct ProfileTabPager<")!.lowerBound..<pager.range(of: "enum ProfileTabPrebuild")!.lowerBound])
        XCTAssertTrue(body.contains("@State private var drag = ProfileTabDrag()"), "横の量を入れ物の状態で持っている")
        XCTAssertFalse(body.contains("@State private var drag: CGFloat"))
        XCTAssertFalse(body.contains(".onChange(of: drag)"), "入れ物が横の量を見張っている")
        XCTAssertFalse(body.contains("drag.offset)"), "入れ物の body が横の量を読んでいる")
        // 子は中身を値で受ける（関数で受けると、子の描き直しのたびに全部の札を作り直す）
        XCTAssertTrue(pager.contains("    let content: Content\n"))
        XCTAssertTrue(body.contains("if !pages.isBuilt(next) { pages.select(next) }"))
        XCTAssertTrue(body.contains(".onDisappear { drag.offset = 0 }"))
        XCTAssertTrue(pager.contains("if pan.state == .began || pan.state == .changed {\n                handlers?.onEnd(0, 0,"),
                      "払いの途中で外したときに終えていない")
    }

    /// 🔴 深く送ってから払うと、入ってくる札は「札の行を上端へ送ったときの位置」から見える（空に見えない）
    func testIncomingPageIsLiftedToTheVisibleTop() throws {
        XCTAssertEqual(ProfileTabScroll.rowOverflow(rowMinY: -300, visibleTop: 0), 300)
        XCTAssertEqual(ProfileTabScroll.rowOverflow(rowMinY: 30, visibleTop: 59), 29)
        XCTAssertEqual(ProfileTabScroll.rowOverflow(rowMinY: 420, visibleTop: 0), 0, "送っていないのに下げる")
        let pager = try source("Sources/JourneyPhoto/Features/Profile/ProfileTabPager.swift")
        XCTAssertTrue(pager.contains(".offset(y: shown ? 0 : lift)"))
        for page in ["MyPageView", "UserProfileView"] {
            let text = try source("Sources/JourneyPhoto/Features/Profile/\(page).swift")
            XCTAssertTrue(text.contains("rowOverflow: { ProfileTabScroll.rowOverflow(rowMinY: tabRow.minY, visibleTop: visibleTop) }"),
                          "\(page) が札の行のはみ出しを渡していない")
        }
        // 人のページの地図は、開いて少し待ってから先に作る
        let theirs = try source("Sources/JourneyPhoto/Features/Profile/UserProfileView.swift")
        XCTAssertTrue(theirs.contains("prebuilt: [.map]"))
    }

    /// 🔴 マイページと人のページが同じ入れ物を使い、中身を `if tab ==` の枝で作り直していない。
    /// 札の行でも払える・人のページの地図の中身では払いを受けない・最低の高さを渡している
    func testBothPagesUseThePager() throws {
        let mine = try source("Sources/JourneyPhoto/Features/Profile/MyPageView.swift")
        XCTAssertTrue(mine.contains("ProfileTabPager(tabs: ProfileTab.tabs(isMe: true), selection: $tab,"))
        XCTAssertTrue(mine.contains("minHeight: ProfileTabScroll.minPageHeight(viewport: scrollHeight, visibleTop: visibleTop,"))
        // 札の行は上に留まる見出しの中（2026-10-30 #418）。そこでも払える
        XCTAssertTrue(mine.contains("tabPicker(stuck: stuck)\n                            .modifier(ProfileTabSwipe("))
        XCTAssertFalse(mine.contains("private var photoArea"), "選んだ札だけを作る枝が残っている")
        XCTAssertFalse(mine.contains("simultaneousGesture(tabSwipe)"))
        let theirs = try source("Sources/JourneyPhoto/Features/Profile/UserProfileView.swift")
        XCTAssertTrue(theirs.contains("minHeight: ProfileTabScroll.minPageHeight(viewport: scrollHeight, visibleTop: visibleTop,"))
        XCTAssertTrue(theirs.contains("swipeBlocked: [.map]"))
        XCTAssertTrue(theirs.contains(".modifier(ProfileTabSwipe(tabs: ProfileTab.tabs(isMe: false)"))
        XCTAssertFalse(theirs.contains("private var photoArea"))
        // 選んでいない札は押せず、読み上げにも出さない
        let pager = try source("Sources/JourneyPhoto/Features/Profile/ProfileTabPager.swift")
        XCTAssertTrue(pager.contains(".allowsHitTesting(shown)"))
        XCTAssertTrue(pager.contains(".accessibilityHidden(!shown)"))
        XCTAssertTrue(pager.contains(".frame(minHeight: minHeight, alignment: .top)"))
    }

    /// 🔴 下線は1本で、選んだ札へ滑る（札ごとに透明の下線を描かない）。押したときも払ったときも同じ動き
    func testUnderlineSlides() throws {
        let bar = try source("Sources/JourneyPhoto/Features/Profile/ProfileTabBar.swift")
        // 🔴 `ViewThatFits` の2案（詰めた並び・広げた並び）で id を分ける（同じ id だと両方が元になる）
        XCTAssertTrue(bar.contains(".matchedGeometryEffect(id: \"profile.tab.underline.\\(fill)\", in: underline)"),
                      "下線の id に並びの別が無い")
        XCTAssertFalse(bar.contains("selected ? WebTheme.accent : Color.clear"), "札ごとの下線が残っている")
        XCTAssertTrue(bar.contains("withAnimation(ProfileTabMotion.animation(reduceMotion: reduceMotion))"))
        // 押せる高さは 48（#418 案A・見た目も当たりも 48）
        XCTAssertTrue(bar.contains(".frame(minHeight: ProfileTabStyle.height)"))
    }

    // MARK: - 2026-10-24 確かめ役の見直し

    /// 🔴 深く送ってから替えたときだけ、札の行を上端へ送る（まだ送っていなければ動かさない）
    func testScrollsToTheRowOnlyWhenItIsAboveTheTop() {
        XCTAssertTrue(ProfileTabScroll.scrollsToRow(rowMinY: -300, visibleTop: 0), "深く送った回に頭へ戻さない")
        XCTAssertFalse(ProfileTabScroll.scrollsToRow(rowMinY: 420, visibleTop: 0), "まだ送っていない回まで動かす")
        XCTAssertFalse(ProfileTabScroll.scrollsToRow(rowMinY: 0, visibleTop: 0), "上端にちょうど居るのに動かす")
        // カバーを時計の裏まで伸ばしたマイページ: 時計の下（59）より上に出ていたら送る
        XCTAssertTrue(ProfileTabScroll.scrollsToRow(rowMinY: 30, visibleTop: 59))
        XCTAssertFalse(ProfileTabScroll.scrollsToRow(rowMinY: 59, visibleTop: 59))
    }

    /// `scrollTo` の目印: 札の行の上端が見えている上端に来る割合
    func testAnchorPutsTheRowAtTheVisibleTop() {
        XCTAssertEqual(ProfileTabScroll.anchorY(visibleTop: 0, viewport: 800, rowHeight: 44), 0)
        let y = ProfileTabScroll.anchorY(visibleTop: 59, viewport: 903, rowHeight: 44)
        // 行の上端 = y × (見えている高さ − 行の高さ)
        XCTAssertEqual(y * (903 - 44), 59, accuracy: 0.001)
        XCTAssertEqual(ProfileTabScroll.anchorY(visibleTop: 10, viewport: 20, rowHeight: 44), 0, "高さが足りないとき割合が壊れる")
    }

    /// 🔴 最低の高さは「見えている高さ − 札の行と間」（画面1枚分そのままだと、行が上端を越えて送れてしまう）
    func testMinimumHeightKeepsTheRowAtTheTop() {
        XCTAssertEqual(ProfileTabScroll.minPageHeight(viewport: 800, visibleTop: 0, rowHeight: 44, spacing: 14), 742)
        XCTAssertEqual(ProfileTabScroll.minPageHeight(viewport: 903, visibleTop: 59, rowHeight: 45, spacing: 14), 785)
        XCTAssertEqual(ProfileTabScroll.minPageHeight(viewport: 30, visibleTop: 0, rowHeight: 44, spacing: 14), 0)
    }

    /// 両方のページが、札を替えたときに札の行の位置を見て上端へ送る（動きを減らす設定では動きなし）
    func testBothPagesScrollToTheRowOnSwitch() throws {
        for page in ["MyPageView", "UserProfileView"] {
            let text = try source("Sources/JourneyPhoto/Features/Profile/\(page).swift")
            XCTAssertTrue(text.contains(".id(ProfileTabScroll.rowID)"), "\(page) の札の行に目印が無い")
            XCTAssertTrue(text.contains("guard ProfileTabScroll.scrollsToRow(rowMinY: tabRow.minY, visibleTop: visibleTop)"),
                          "\(page) が札を替えても頭へ戻さない")
            XCTAssertTrue(text.contains("withAnimation(ProfileTabMotion.animation(reduceMotion: reduceMotion)) {\n                reader.scrollTo("),
                          "\(page) の送りが動きを減らす設定を見ていない")
        }
    }

    /// 🔴 同じ入力なら計算し直さない（保持した札の中身を描き直しのたびに計算しない）
    func testMemoComputesOnlyWhenInputChanges() {
        let memo = DerivedMemo<[Int], Int>()
        let input = [1, 2, 3]
        XCTAssertEqual(memo.value(for: input) { input.reduce(0, +) }, 6)
        XCTAssertEqual(memo.value(for: input) { input.reduce(0, +) }, 6)
        XCTAssertEqual(memo.computeCount, 1, "同じ入力で計算し直している")
        XCTAssertEqual(memo.value(for: [4]) { 4 }, 4)
        XCTAssertEqual(memo.computeCount, 2, "入力が変わったのに前の答えを返している")
    }

    /// マイページの札の中身（旅の棚・行きたい場所）が控えを通る。描き直しで同じ写真なら1度だけ計算する
    func testMyPageTabsUseTheMemo() throws {
        let memo = MyPageTabMemo()
        let photos: [Photo] = []
        _ = memo.shelfTrips(photos)
        _ = memo.shelfTrips(photos)
        _ = memo.postedShots(photos)
        _ = memo.postedShots(photos)
        let pool = memo.wishlistPool(own: photos, feed: photos, hidden: ModerationSnapshot())
        _ = memo.wishlistPool(own: photos, feed: photos, hidden: ModerationSnapshot())
        _ = memo.wantedPlaces(keys: ["a"], pool: pool)
        _ = memo.wantedPlaces(keys: ["a"], pool: pool)
        XCTAssertEqual(memo.shelf.computeCount, 1)
        XCTAssertEqual(memo.posted.computeCount, 1)
        XCTAssertEqual(memo.pool.computeCount, 1)
        XCTAssertEqual(memo.wanted.computeCount, 1)
        _ = memo.wantedPlaces(keys: ["b"], pool: pool)
        XCTAssertEqual(memo.wanted.computeCount, 2)
        // 画面は控えから引き、描き直しのたびの直の計算が残っていない
        let view = try source("Sources/JourneyPhoto/Features/Profile/MyPageView.swift")
        for direct in ["TripBook.shelfTrips(from: model.photos)", "LibraryTrips.postedShots(of: model.photos)",
                       "ProfileSections.wishlistPool(feed: feed, mine: model.photos)",
                       "ProfileSections.wantedPlaces(keys: wishIds", "LikedPhotos.resolve(savedIds"] {
            XCTAssertFalse(view.contains(direct), "描き直しのたびに計算している: \(direct)")
        }
    }
}
