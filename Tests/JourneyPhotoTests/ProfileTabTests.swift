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

    // MARK: - 横に払って切り替える

    private let mine = ProfileTab.tabs(isMe: true)

    /// 指を左へ払うと右隣、右へ払うと左隣
    func testSwipeMovesToNeighbour() {
        XCTAssertEqual(ProfileTab.swiped(from: .posts, in: mine, dx: -80, dy: 0), .trips)
        XCTAssertEqual(ProfileTab.swiped(from: .wishlist, in: mine, dx: 80, dy: 0), .trips)
        XCTAssertEqual(ProfileTab.swiped(from: .wishlist, in: mine, dx: -80, dy: 0), .favorites)
    }

    /// 端では回り込まない（最後から最初へ飛ぶと、どこにいるか分からなくなる）
    func testSwipeStopsAtEdges() {
        XCTAssertNil(ProfileTab.swiped(from: .posts, in: mine, dx: 80, dy: 0))
        XCTAssertNil(ProfileTab.swiped(from: .favorites, in: mine, dx: -80, dy: 0))
    }

    /// **縦のスクロールでタブが変わらない**——斜めの流しや短い揺れは無視
    func testSwipeIgnoresVerticalAndShortDrags() {
        // 縦が主
        XCTAssertNil(ProfileTab.swiped(from: .posts, in: mine, dx: -60, dy: 200))
        // 斜め（横が縦の 1.5 倍に届かない）
        XCTAssertNil(ProfileTab.swiped(from: .posts, in: mine, dx: -90, dy: 70))
        // 比のちょうど境目（横がちょうど縦の 1.5 倍）は切り替えない
        XCTAssertNil(ProfileTab.swiped(from: .posts, in: mine, dx: -75, dy: 50))
        XCTAssertEqual(ProfileTab.swiped(from: .posts, in: mine, dx: -76, dy: 50), .trips)
        // 短い
        XCTAssertNil(ProfileTab.swiped(from: .posts, in: mine, dx: -30, dy: 0))
        // 境目: ちょうど最小距離なら切り替わる
        XCTAssertEqual(ProfileTab.swiped(from: .posts, in: mine,
                                         dx: -ProfileTab.swipeMinDistance, dy: 0), .trips)
    }

    /// 並びに無いタブ（本人のページのマップ）からは動かない
    func testSwipeFromUnknownTabIsNil() {
        XCTAssertNil(ProfileTab.swiped(from: .map, in: mine, dx: -80, dy: 0))
    }
}
