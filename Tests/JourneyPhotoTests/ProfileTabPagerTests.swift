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
        XCTAssertTrue(mine.contains("ProfileTabPager(tabs: ProfileTab.tabs(isMe: true), selection: $tab, minHeight: viewport)"))
        XCTAssertTrue(mine.contains("tabPicker\n                        .modifier(ProfileTabSwipe("))
        XCTAssertFalse(mine.contains("private var photoArea"), "選んだ札だけを作る枝が残っている")
        XCTAssertFalse(mine.contains("simultaneousGesture(tabSwipe)"))
        let theirs = try source("Sources/JourneyPhoto/Features/Profile/UserProfileView.swift")
        XCTAssertTrue(theirs.contains("minHeight: viewportHeight, swipeBlocked: [.map]"))
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
        XCTAssertTrue(bar.contains(".matchedGeometryEffect(id: \"profile.tab.underline\", in: underline)"))
        XCTAssertFalse(bar.contains("selected ? WebTheme.accent : Color.clear"), "札ごとの下線が残っている")
        XCTAssertTrue(bar.contains("withAnimation(ProfileTabMotion.animation(reduceMotion: reduceMotion))"))
        // 押せる高さは 44
        XCTAssertTrue(bar.contains("minHeight: WebTheme.minTapTarget"))
    }
}
