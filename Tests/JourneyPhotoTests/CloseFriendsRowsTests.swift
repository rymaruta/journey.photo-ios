import XCTest
@testable import JourneyPhoto

/// 「親しい友達」の画面に並べる人（`CloseFriendsRows`）。
final class CloseFriendsRowsTests: XCTestCase {

    private func user(_ id: String) -> FollowUser {
        FollowUser(id: id, name: id, deleted: nil)
    }

    /// 🔴 **フォロー中に居ない親しい友達も並べる。** 並べないと外せず、
    /// フォローを外した相手が限定公開のストーリーを見続けられた
    func testChosenPeopleOutsideTheFollowingListAreListed() {
        let rows = CloseFriendsRows.split(following: [user("a"), user("b")],
                                          chosen: ["b", "gone", "past50"])
        XCTAssertEqual(rows.others, ["gone", "past50"])
        XCTAssertEqual(rows.following.map(\.id), ["a", "b"])
    }

    /// フォロー中の人は二重に並べない（上の段に出すのは一覧に居ない人だけ）
    func testFollowedPeopleAreNotDuplicated() {
        let rows = CloseFriendsRows.split(following: [user("a")], chosen: ["a"])
        XCTAssertTrue(rows.others.isEmpty)
    }

    /// 同じ id が2回来ても1行（`ForEach` の id が重なると表示が崩れる）
    func testDuplicateIdsBecomeOneRow() {
        let rows = CloseFriendsRows.split(following: [], chosen: ["x", "x"])
        XCTAssertEqual(rows.others, ["x"])
    }

    /// フォローが0人でも、選んでいる人がいれば並ぶ（「まだいません」で隠さない）
    func testWorksWithNoFollowing() {
        let rows = CloseFriendsRows.split(following: [], chosen: ["x"])
        XCTAssertEqual(rows.others, ["x"])
    }
}
