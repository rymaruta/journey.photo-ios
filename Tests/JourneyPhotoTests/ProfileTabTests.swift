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
}
