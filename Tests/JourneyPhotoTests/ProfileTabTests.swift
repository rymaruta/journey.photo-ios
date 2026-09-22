import XCTest
@testable import JourneyPhoto

final class ProfileTabTests: XCTestCase {

    /// モック2 の並び（投稿 → 行きたい場所 → マップ）を崩さない
    func testMyPageOrder() {
        XCTAssertEqual(ProfileTab.tabs(isMe: true), [.posts, .wishlist, .map, .favorites])
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
