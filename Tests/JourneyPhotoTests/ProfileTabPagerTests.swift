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

    /// 払いの判定（はっきり横・端で回り込まない）。人のページ（投稿 / マップ）でも同じ
    func testSwipeMovesToTheNeighbour() {
        let mine = ProfileTab.tabs(isMe: true)
        XCTAssertEqual(ProfileTab.swiped(from: .posts, in: mine, dx: -80, dy: 5), .trips)
        XCTAssertEqual(ProfileTab.swiped(from: .trips, in: mine, dx: 80, dy: 5), .posts)
        XCTAssertNil(ProfileTab.swiped(from: .posts, in: mine, dx: 80, dy: 0), "端で回り込んでいる")
        XCTAssertNil(ProfileTab.swiped(from: .posts, in: mine, dx: -80, dy: 70), "斜めの縦スクロールで切り替わる")
        let theirs = ProfileTab.tabs(isMe: false)
        XCTAssertEqual(ProfileTab.swiped(from: .posts, in: theirs, dx: -80, dy: 0), .map)
        XCTAssertEqual(ProfileTab.swiped(from: .map, in: theirs, dx: 80, dy: 0), .posts)
    }

    /// 🔴 マイページと人のページが同じ入れ物を使い、中身を `if tab ==` の枝で作り直していない。
    /// 札の行でも払える・人のページの地図の中身では払いを受けない・最低の高さを渡している
    func testBothPagesUseThePager() throws {
        let mine = try source("Sources/JourneyPhoto/Features/Profile/MyPageView.swift")
        XCTAssertTrue(mine.contains("ProfileTabPager(tabs: ProfileTab.tabs(isMe: true), selection: $tab,"))
        XCTAssertTrue(mine.contains("minHeight: ProfileTabScroll.minPageHeight(viewport: scrollHeight, visibleTop: visibleTop,"))
        XCTAssertTrue(mine.contains("tabPicker\n                        .modifier(ProfileTabSwipe("))
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
        // 押せる高さは 44
        XCTAssertTrue(bar.contains("minHeight: WebTheme.minTapTarget"))
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
            XCTAssertTrue(text.contains("guard ProfileTabScroll.scrollsToRow(rowMinY: tabRowMinY, visibleTop: visibleTop)"),
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
