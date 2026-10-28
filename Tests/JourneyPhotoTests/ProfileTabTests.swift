import XCTest
@testable import JourneyPhoto

final class ProfileTabTests: XCTestCase {

    /// 整理案 05c の並び（投稿 → 旅の記録 → 行きたい場所 → お気に入り）。
    /// **本人のページに「マップ」は出さない**——下の札の「マップ」と重なる
    func testMyPageOrder() {
        XCTAssertEqual(ProfileTab.tabs(isMe: true), [.posts, .trips, .wishlist, .favorites])
        XCTAssertFalse(ProfileTab.tabs(isMe: true).contains(.map))
    }

    /// 旅の記録は本人の記録。**他人のページには出さない**
    func testOthersPageHasNoTrips() {
        XCTAssertFalse(ProfileTab.tabs(isMe: false).contains(.trips))
    }

    /// **端末にしか無いものは他人のページに出さない。**
    /// 押しても何も出ない札は、壊れているのと見分けが付かない
    func testOthersPageHidesDeviceOnlyTabs() {
        let others = ProfileTab.tabs(isMe: false)
        XCTAssertFalse(others.contains(.wishlist))
        XCTAssertFalse(others.contains(.favorites))
        XCTAssertEqual(others, [.posts, .map])
    }

    func testEveryTabHasALabelAndIcon() {
        for tab in ProfileTab.allCases {
            XCTAssertFalse(tab.label.isEmpty, "\(tab) の札が空")
            XCTAssertFalse(tab.systemImage.isEmpty, "\(tab) の絵が空")
        }
    }

    /// 板 05c の印（投稿は 2×2 の格子）
    func testPostsIconMatchesBoard() {
        XCTAssertEqual(ProfileTab.posts.systemImage, "square.grid.2x2")
    }

    // MARK: - 横に払って切り替える

    private let mine = ProfileTab.tabs(isMe: true)

    /// 指を左へ払うと右隣、右へ払うと左隣
    func testSwipeMovesToNeighbour() {
        XCTAssertEqual(ProfileTab.neighbor(of: .posts, in: mine, towards: -1), .trips)
        XCTAssertEqual(ProfileTab.neighbor(of: .wishlist, in: mine, towards: 1), .trips)
        XCTAssertEqual(ProfileTab.neighbor(of: .wishlist, in: mine, towards: -1), .favorites)
        XCTAssertNil(ProfileTab.neighbor(of: .posts, in: mine, towards: 0))
    }

    /// 端では回り込まない（最後から最初へ飛ぶと、どこにいるか分からなくなる）。
    /// 隣の無い向きへは払いを始めない（人のページの「戻る」の払いに渡す）
    func testSwipeStopsAtEdges() {
        XCTAssertNil(ProfileTab.neighbor(of: .posts, in: mine, towards: 1))
        XCTAssertNil(ProfileTab.neighbor(of: .favorites, in: mine, towards: -1))
        XCTAssertFalse(ProfileTab.startsSwipe(from: .posts, in: mine, dx: 12, dy: 0))
        XCTAssertNil(ProfileTab.settled(from: .favorites, in: mine, dx: -300, velocity: -900, width: 390))
        XCTAssertEqual(ProfileTab.followOffset(from: .posts, in: mine, dx: 120, width: 390), 0, "隣の無い向きへ中身が動く")
    }

    /// 🔴 始めるのは動き始めの横が縦の 1.2 倍より大きいときだけ（2026-10-28: 以前の 1.5 倍は厳しすぎた）。
    /// 始まったらその指の間は縦に送らない（向きの固定・`ProfileTabSwipe`）
    func testSwipeStartsOnlyWhenMostlyHorizontal() {
        XCTAssertTrue(ProfileTab.startsSwipe(from: .posts, in: mine, dx: -12, dy: 3))
        XCTAssertTrue(ProfileTab.startsSwipe(from: .posts, in: mine, dx: -10, dy: 8), "約 40° より寝た払いで始まらない")
        XCTAssertFalse(ProfileTab.startsSwipe(from: .posts, in: mine, dx: -9, dy: 8), "斜めの縦送り（約 42°）で始まる")
        XCTAssertFalse(ProfileTab.startsSwipe(from: .posts, in: mine, dx: -8, dy: 8), "斜め 45° の縦送りで始まる")
        XCTAssertFalse(ProfileTab.startsSwipe(from: .posts, in: mine, dx: -3, dy: -12), "縦の送りで始まる")
    }

    /// 動いている間は指に付いてくる（画面の幅まで）
    func testContentFollowsTheFinger() {
        XCTAssertEqual(ProfileTab.followOffset(from: .posts, in: mine, dx: -120, width: 390), -120)
        XCTAssertEqual(ProfileTab.followOffset(from: .posts, in: mine, dx: -600, width: 390), -390)
        XCTAssertEqual(ProfileTab.followOffset(from: .trips, in: mine, dx: 80, width: 390), 80)
    }

    /// 🔴 離したとき: 幅の 3 割動かしたか、同じ向きに速く払えば隣へ。足りなければ戻る
    func testSettlesByDistanceOrFling() {
        // 普通の速さで、指を3割以上動かした
        XCTAssertEqual(ProfileTab.settled(from: .posts, in: mine, dx: -130, velocity: -100, width: 390), .trips)
        // 短いが勢いがある（以前は 50pt に届かないと替わらなかった）
        XCTAssertEqual(ProfileTab.settled(from: .posts, in: mine, dx: -40, velocity: -800, width: 390), .trips)
        XCTAssertEqual(ProfileTab.settled(from: .trips, in: mine, dx: 40, velocity: 500, width: 390), .posts)
        // 短くてゆっくり → 戻る
        XCTAssertNil(ProfileTab.settled(from: .posts, in: mine, dx: -100, velocity: -100, width: 390))
        // 少し動かした指の揺れ（以前の 300pt/秒 なら替わっていた）→ 戻る
        XCTAssertNil(ProfileTab.settled(from: .posts, in: mine, dx: -40, velocity: -400, width: 390))
        // 動かしてから逆へ払い戻した → 戻る（替えない）。🔴 旅の記録なら逆向きにも隣（投稿）があるので、
        // 逆向きの払いで反対側の札へ飛ばないこと（`settled` の向きの guard）
        XCTAssertNil(ProfileTab.settled(from: .posts, in: mine, dx: -200, velocity: 900, width: 390))
        XCTAssertNil(ProfileTab.settled(from: .trips, in: mine, dx: -200, velocity: 900, width: 390),
                     "左へ動かしてから右へ払い戻したのに、反対側の札へ替わった")
        // 境目
        XCTAssertEqual(ProfileTab.settled(from: .posts, in: mine, dx: -390 * ProfileTab.swipeCommitFraction,
                                          velocity: 0, width: 390), .trips)
        XCTAssertEqual(ProfileTab.settled(from: .posts, in: mine, dx: -10,
                                          velocity: -ProfileTab.swipeFlingVelocity, width: 390), .trips)
        // 取り消し（量も速さも 0）
        XCTAssertNil(ProfileTab.settled(from: .posts, in: mine, dx: 0, velocity: 0, width: 390))
    }

    /// 並びに無いタブ（本人のページのマップ）からは動かない
    func testSwipeFromUnknownTabIsNil() {
        XCTAssertNil(ProfileTab.neighbor(of: .map, in: mine, towards: -1))
        XCTAssertFalse(ProfileTab.startsSwipe(from: .map, in: mine, dx: -80, dy: 0))
    }
}
